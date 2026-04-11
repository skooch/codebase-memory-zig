// pipeline — Indexing pipeline orchestrator.
//
// Orchestrates discovery, extraction, symbol registry, resolution passes, and
// persistence to the store.

const std = @import("std");
const discover = @import("discover.zig");
const GraphBuffer = @import("graph_buffer.zig").GraphBuffer;
const BufferNode = @import("graph_buffer.zig").BufferNode;
const GraphBufferError = @import("graph_buffer.zig").GraphBufferError;
const extractor = @import("extractor.zig");
const minhash = @import("minhash.zig");
const Registry = @import("registry.zig").Registry;
const store = @import("store.zig");

pub const IndexMode = enum {
    full, // read everything, build from scratch
    fast, // skip non-essential files
};

pub const PipelineError = error{
    Cancelled,
    DiscoveryFailed,
    OutOfMemory,
} || store.StoreError;

pub const PipelineContext = struct {
    project_name: []const u8,
    repo_path: []const u8,
    allocator: std.mem.Allocator,
    cancelled: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
};

const OwnedExtraction = struct {
    allocator: std.mem.Allocator,
    extraction: extractor.FileExtraction,
};

pub const Pipeline = struct {
    allocator: std.mem.Allocator,
    repo_path: []const u8,
    mode: IndexMode,
    project_name: []const u8 = "",
    cancelled: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    pub fn init(allocator: std.mem.Allocator, repo_path: []const u8, mode: IndexMode) Pipeline {
        const base = std.fs.path.basename(repo_path);
        const project_name = if (base.len == 0) "project" else base;
        return .{
            .allocator = allocator,
            .repo_path = repo_path,
            .mode = mode,
            .project_name = project_name,
        };
    }

    pub fn deinit(self: *Pipeline) void {
        _ = self;
    }

    pub fn run(self: *Pipeline, db: *store.Store) PipelineError!void {
        if (self.cancelled.load(.acquire)) return PipelineError.Cancelled;

        const discovered_files = discover.discoverFiles(
            self.allocator,
            self.repo_path,
            .{ .mode = self.mode },
        ) catch |err| {
            std.log.warn("pipeline discovery failed for {s}: {}", .{ self.repo_path, err });
            return PipelineError.DiscoveryFailed;
        };
        defer self.freeDiscoveredFiles(discovered_files);

        if (discovered_files.len == 0) {
            std.log.info("pipeline discovered 0 indexable files in {s}", .{self.repo_path});
            return;
        }

        try db.beginImmediate();
        var committed = false;
        errdefer if (!committed) db.rollback() catch {};

        const stored_hashes = try db.getFileHashes(self.project_name);
        defer db.freeFileHashes(stored_hashes);
        if (stored_hashes.len > 0 and
            discovered_files.len <= stored_hashes.len + (stored_hashes.len / 2))
        {
            const used_incremental = self.runIncremental(db, discovered_files, stored_hashes) catch |err| switch (err) {
                error.Cancelled => return PipelineError.Cancelled,
                error.OutOfMemory => return PipelineError.OutOfMemory,
                error.SqlError => return PipelineError.SqlError,
                error.OpenFailed => return PipelineError.OpenFailed,
                error.NotFound => return PipelineError.NotFound,
                else => return PipelineError.DiscoveryFailed,
            };
            if (used_incremental) {
                try db.commit();
                committed = true;
                return;
            }
        }

        try db.deleteProject(self.project_name);
        try db.upsertProject(self.project_name, self.repo_path);

        var gb = GraphBuffer.init(self.allocator, self.project_name);
        defer gb.deinit();

        var reg = Registry.init(self.allocator);
        defer reg.deinit();

        var extractions = std.ArrayList(OwnedExtraction).empty;
        defer {
            for (extractions.items) |owned| {
                extractor.freeFileExtraction(owned.allocator, owned.extraction);
            }
            extractions.deinit(self.allocator);
        }

        try collectExtractions(self, discovered_files, &gb, &reg, &extractions);

        try resolveExtractions(&gb, &reg, extractions.items, &self.cancelled);
        try runSimilarityPass(self.allocator, self.repo_path, &gb);

        try gb.dumpToStore(db);
        try persistFileHashes(db, self.project_name, discovered_files);
        std.log.info(
            "pipeline graph buffer: {} nodes, {} edges",
            .{ gb.nodeCount(), gb.edgeCount() },
        );
        try db.commit();
        committed = true;
    }

    pub fn cancel(self: *Pipeline) void {
        self.cancelled.store(true, .release);
    }

    fn runIncremental(
        self: *Pipeline,
        db: *store.Store,
        discovered_files: []discover.FileInfo,
        stored_hashes: []const store.FileHash,
    ) !bool {
        const classification = try classifyDiscoveredFiles(
            self.allocator,
            discovered_files,
            stored_hashes,
        );
        defer freeFileClassification(self.allocator, classification);

        if (classification.changed_files.len == 0 and classification.deleted_paths.len == 0) {
            try db.upsertProject(self.project_name, self.repo_path);
            try persistFileHashes(db, self.project_name, discovered_files);
            std.log.info("pipeline incremental: no changes for {s}", .{self.project_name});
            return true;
        }

        var gb = GraphBuffer.init(self.allocator, self.project_name);
        defer gb.deinit();
        try gb.loadFromStore(db);

        for (classification.changed_files) |file| {
            gb.deleteByFile(file.rel_path);
        }
        for (classification.deleted_paths) |rel_path| {
            gb.deleteByFile(rel_path);
        }

        var reg = Registry.init(self.allocator);
        defer reg.deinit();
        try seedRegistryFromGraphBuffer(&gb, &reg);

        var extractions = std.ArrayList(OwnedExtraction).empty;
        defer {
            for (extractions.items) |owned| {
                extractor.freeFileExtraction(owned.allocator, owned.extraction);
            }
            extractions.deinit(self.allocator);
        }

        try collectExtractions(self, classification.changed_files, &gb, &reg, &extractions);

        try resolveExtractions(&gb, &reg, extractions.items, &self.cancelled);
        try runSimilarityPass(self.allocator, self.repo_path, &gb);

        try db.deleteProject(self.project_name);
        try db.upsertProject(self.project_name, self.repo_path);
        try gb.dumpToStore(db);
        try persistFileHashes(db, self.project_name, discovered_files);
        std.log.info(
            "pipeline incremental graph buffer: {} nodes, {} edges",
            .{ gb.nodeCount(), gb.edgeCount() },
        );
        return true;
    }

    fn freeDiscoveredFiles(self: *Pipeline, discovered_files: []discover.FileInfo) void {
        for (discovered_files) |file| {
            self.allocator.free(file.path);
            self.allocator.free(file.rel_path);
        }
        self.allocator.free(discovered_files);
    }
};

fn extractFile(
    allocator: std.mem.Allocator,
    project_name: []const u8,
    file: discover.FileInfo,
    gb: *GraphBuffer,
) !extractor.FileExtraction {
    return try extractor.extractFile(allocator, project_name, file, gb);
}

fn normalizeImportAlias(raw: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, raw, " \t\"'");
    if (trimmed.len == 0) return "";
    var start: usize = 0;
    var i: usize = 0;
    while (i < trimmed.len) : (i += 1) {
        if (trimmed[i] == '/' or trimmed[i] == '\\' or trimmed[i] == '.') {
            start = i + 1;
            continue;
        }
        if (trimmed[i] == ':') {
            if (i + 1 < trimmed.len and trimmed[i + 1] == ':') {
                start = i + 2;
                i += 1;
            } else {
                start = i + 1;
            }
        }
    }
    if (start < trimmed.len) {
        return trimmed[start..];
    }
    if (std.mem.lastIndexOf(u8, trimmed, ".")) |dot| {
        if (dot + 1 < trimmed.len) return trimmed[dot + 1 ..];
    }
    return trimmed;
}

fn resolveSemanticTarget(
    reg: *const Registry,
    hint: extractor.SemanticHint,
    file_path: []const u8,
) ?@import("registry.zig").Resolution {
    if (std.mem.eql(u8, hint.relation, "IMPLEMENTS")) {
        return reg.resolve(hint.parent_name, hint.child_id, file_path, "Trait") orelse
            reg.resolve(hint.parent_name, hint.child_id, file_path, "Interface") orelse
            reg.resolve(hint.parent_name, hint.child_id, file_path, null);
    }
    if (std.mem.eql(u8, hint.relation, "INHERITS")) {
        return reg.resolve(hint.parent_name, hint.child_id, file_path, "Class") orelse
            reg.resolve(hint.parent_name, hint.child_id, file_path, "Interface") orelse
            reg.resolve(hint.parent_name, hint.child_id, file_path, null);
    }
    if (std.mem.eql(u8, hint.relation, "DECORATES")) {
        return reg.resolve(hint.parent_name, hint.child_id, file_path, "Function") orelse
            reg.resolve(hint.parent_name, hint.child_id, file_path, null);
    }
    return reg.resolve(hint.parent_name, hint.child_id, file_path, null);
}

const FileClassification = struct {
    changed_files: []discover.FileInfo,
    deleted_paths: [][]u8,
};

fn classifyDiscoveredFiles(
    allocator: std.mem.Allocator,
    discovered_files: []discover.FileInfo,
    stored_hashes: []const store.FileHash,
) !FileClassification {
    var stored_by_path = std.StringHashMap(*const store.FileHash).init(allocator);
    defer stored_by_path.deinit();
    for (stored_hashes) |*hash| {
        try stored_by_path.put(hash.rel_path, hash);
    }

    var seen_paths = std.StringHashMap(void).init(allocator);
    defer seen_paths.deinit();

    var changed_files = std.ArrayList(discover.FileInfo).empty;
    errdefer changed_files.deinit(allocator);

    for (discovered_files) |file| {
        try seen_paths.put(file.rel_path, {});
        if (stored_by_path.get(file.rel_path)) |stored| {
            const stat = try statFile(file.path);
            if (stat.mtime_ns != stored.mtime_ns or stat.size != stored.size) {
                try changed_files.append(allocator, file);
            }
        } else {
            try changed_files.append(allocator, file);
        }
    }

    var deleted_paths = std.ArrayList([]u8).empty;
    errdefer {
        for (deleted_paths.items) |path| allocator.free(path);
        deleted_paths.deinit(allocator);
    }
    for (stored_hashes) |hash| {
        if (!seen_paths.contains(hash.rel_path)) {
            try deleted_paths.append(allocator, try allocator.dupe(u8, hash.rel_path));
        }
    }

    return .{
        .changed_files = try changed_files.toOwnedSlice(allocator),
        .deleted_paths = try deleted_paths.toOwnedSlice(allocator),
    };
}

fn freeFileClassification(allocator: std.mem.Allocator, classification: FileClassification) void {
    allocator.free(classification.changed_files);
    for (classification.deleted_paths) |path| allocator.free(path);
    allocator.free(classification.deleted_paths);
}

const FileStatSnapshot = struct {
    mtime_ns: i64,
    size: i64,
};

fn statFile(path: []const u8) !FileStatSnapshot {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const stat = try file.stat();
    return .{
        .mtime_ns = @intCast(stat.mtime),
        .size = @intCast(stat.size),
    };
}

fn persistFileHashes(
    db: *store.Store,
    project_name: []const u8,
    discovered_files: []discover.FileInfo,
) !void {
    try db.deleteFileHashes(project_name);
    for (discovered_files) |file| {
        const stat = statFile(file.path) catch continue;
        try db.upsertFileHash(project_name, file.rel_path, "", stat.mtime_ns, stat.size);
    }
}

fn collectExtractions(
    self: *Pipeline,
    files: []const discover.FileInfo,
    gb: *GraphBuffer,
    reg: *Registry,
    out: *std.ArrayList(OwnedExtraction),
) PipelineError!void {
    const cpu_count = std.Thread.getCpuCount() catch 1;
    if (files.len >= 32 and cpu_count > 1) {
        collectExtractionsParallel(self, files, gb, reg, out, @min(cpu_count, files.len)) catch |err| switch (err) {
            error.OutOfMemory => return PipelineError.OutOfMemory,
            else => try collectExtractionsSequential(self, files, gb, reg, out),
        };
        return;
    }
    try collectExtractionsSequential(self, files, gb, reg, out);
}

fn collectExtractionsSequential(
    self: *Pipeline,
    files: []const discover.FileInfo,
    gb: *GraphBuffer,
    reg: *Registry,
    out: *std.ArrayList(OwnedExtraction),
) PipelineError!void {
    for (files) |file| {
        if (self.cancelled.load(.acquire)) return PipelineError.Cancelled;

        const extraction = extractFile(self.allocator, self.project_name, file, gb) catch |err| {
            std.log.warn("extractor failed for {s}: {}", .{ file.rel_path, err });
            continue;
        };
        try registerExtraction(reg, extraction);
        logExtractionDebug(extraction);
        try out.append(self.allocator, .{
            .allocator = self.allocator,
            .extraction = extraction,
        });
    }
}

const ParallelFileResult = struct {
    allocator: std.mem.Allocator,
    buffer: GraphBuffer,
    extraction: extractor.FileExtraction,

    fn deinit(self: *ParallelFileResult) void {
        extractor.freeFileExtraction(self.allocator, self.extraction);
        self.buffer.deinit();
    }
};

const ParallelWorkerContext = struct {
    project_name: []const u8,
    files: []const discover.FileInfo,
    results: []?*ParallelFileResult,
    start: usize,
    end: usize,
    cancelled: *const std.atomic.Value(bool),
};

fn collectExtractionsParallel(
    self: *Pipeline,
    files: []const discover.FileInfo,
    gb: *GraphBuffer,
    reg: *Registry,
    out: *std.ArrayList(OwnedExtraction),
    worker_count: usize,
) !void {
    const results = try self.allocator.alloc(?*ParallelFileResult, files.len);
    defer self.allocator.free(results);
    @memset(results, null);

    const contexts = try self.allocator.alloc(ParallelWorkerContext, worker_count);
    defer self.allocator.free(contexts);
    const threads = try self.allocator.alloc(std.Thread, worker_count);
    defer self.allocator.free(threads);

    const chunk_size = @max(@as(usize, 1), files.len / worker_count);
    var worker_index: usize = 0;
    var start: usize = 0;
    while (worker_index < worker_count and start < files.len) : (worker_index += 1) {
        const end = if (worker_index + 1 == worker_count) files.len else @min(files.len, start + chunk_size);
        contexts[worker_index] = .{
            .project_name = self.project_name,
            .files = files,
            .results = results,
            .start = start,
            .end = end,
            .cancelled = &self.cancelled,
        };
        threads[worker_index] = try std.Thread.spawn(.{}, parallelExtractWorker, .{&contexts[worker_index]});
        start = end;
    }

    var joined: usize = 0;
    defer {
        while (joined < worker_index) : (joined += 1) {
            threads[joined].join();
        }
    }

    while (joined < worker_index) : (joined += 1) {
        threads[joined].join();
    }

    for (results) |maybe_result| {
        const result = maybe_result orelse continue;

        try mergeParallelExtraction(self.allocator, gb, result);
        try registerExtraction(reg, result.extraction);
        logExtractionDebug(result.extraction);
        try out.append(self.allocator, .{
            .allocator = result.allocator,
            .extraction = result.extraction,
        });
        result.buffer.deinit();
        result.allocator.destroy(result);
    }
}

fn parallelExtractWorker(ctx: *ParallelWorkerContext) void {
    var idx = ctx.start;
    while (idx < ctx.end) : (idx += 1) {
        if (ctx.cancelled.load(.acquire)) return;

        var local_gb = GraphBuffer.init(std.heap.c_allocator, ctx.project_name);
        const extraction = extractFile(std.heap.c_allocator, ctx.project_name, ctx.files[idx], &local_gb) catch {
            local_gb.deinit();
            continue;
        };

        const result = std.heap.c_allocator.create(ParallelFileResult) catch {
            extractor.freeFileExtraction(std.heap.c_allocator, extraction);
            local_gb.deinit();
            continue;
        };
        result.* = .{
            .allocator = std.heap.c_allocator,
            .buffer = local_gb,
            .extraction = extraction,
        };
        ctx.results[idx] = result;
    }
}

fn mergeParallelExtraction(
    allocator: std.mem.Allocator,
    gb: *GraphBuffer,
    result: *ParallelFileResult,
) !void {
    var id_map = std.AutoHashMap(i64, i64).init(allocator);
    defer id_map.deinit();

    for (result.buffer.nodes()) |node| {
        const new_id = try gb.upsertNodeWithProperties(
            node.label,
            node.name,
            node.qualified_name,
            node.file_path,
            node.start_line,
            node.end_line,
            node.properties_json,
        );
        try id_map.put(node.id, new_id);
    }

    for (result.buffer.edgeItems()) |edge| {
        const source_id = id_map.get(edge.source_id) orelse continue;
        const target_id = id_map.get(edge.target_id) orelse continue;
        _ = gb.insertEdgeWithProperties(source_id, target_id, edge.edge_type, edge.properties_json) catch |err| switch (err) {
            GraphBufferError.DuplicateEdge => 0,
            else => return err,
        };
    }

    remapExtractionIds(&result.extraction, &id_map);
}

fn remapExtractionIds(
    extraction: *extractor.FileExtraction,
    id_map: *const std.AutoHashMap(i64, i64),
) void {
    extraction.file_id = id_map.get(extraction.file_id) orelse extraction.file_id;
    extraction.module_id = id_map.get(extraction.module_id) orelse extraction.module_id;

    for (extraction.symbols) |*sym| {
        sym.id = id_map.get(sym.id) orelse sym.id;
    }
    for (extraction.unresolved_imports) |*imp| {
        imp.importer_id = id_map.get(imp.importer_id) orelse imp.importer_id;
    }
    for (extraction.unresolved_calls) |*call| {
        call.caller_id = id_map.get(call.caller_id) orelse call.caller_id;
    }
    for (extraction.unresolved_usages) |*usage| {
        usage.user_id = id_map.get(usage.user_id) orelse usage.user_id;
    }
    for (extraction.semantic_hints) |*hint| {
        hint.child_id = id_map.get(hint.child_id) orelse hint.child_id;
    }
}

fn registerExtraction(reg: *Registry, extraction: extractor.FileExtraction) !void {
    for (extraction.symbols) |sym| {
        try reg.add(sym.name, sym.qualified_name, sym.label, sym.file_path);
    }
    for (extraction.unresolved_imports) |imp| {
        const alias = if (imp.binding_alias.len > 0)
            imp.binding_alias
        else
            normalizeImportAlias(imp.import_name);
        if (alias.len == 0) continue;
        try reg.addImportBinding(imp.importer_id, alias, imp.import_name, imp.file_path);
    }
}

fn logExtractionDebug(extraction: extractor.FileExtraction) void {
    std.log.debug(
        "file {s} extracted {d} symbols, {d} imports, {d} calls, {d} usages, {d} semantic hints",
        .{
            extraction.file_path,
            extraction.symbols.len,
            extraction.unresolved_imports.len,
            extraction.unresolved_calls.len,
            extraction.unresolved_usages.len,
            extraction.semantic_hints.len,
        },
    );
}

const SimilarityCandidate = struct {
    node_id: i64,
    file_path: []const u8,
    file_ext: []const u8,
    fingerprint: minhash.Fingerprint,
};

fn runSimilarityPass(
    allocator: std.mem.Allocator,
    repo_path: []const u8,
    gb: *GraphBuffer,
) error{OutOfMemory}!void {
    var file_cache = std.StringHashMap([]u8).init(allocator);
    defer {
        var it = file_cache.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        file_cache.deinit();
    }

    var candidates = std.ArrayList(SimilarityCandidate).empty;
    defer candidates.deinit(allocator);

    var function_indices = std.ArrayList(usize).empty;
    defer function_indices.deinit(allocator);

    for (gb.nodes_by_id.items, 0..) |node, idx| {
        if (!std.mem.eql(u8, node.label, "Function")) continue;
        if (node.file_path.len == 0 or node.start_line <= 0) continue;
        try function_indices.append(allocator, idx);
    }

    std.sort.pdq(usize, function_indices.items, gb, lessFunctionNodeIndex);

    var idx: usize = 0;
    while (idx < function_indices.items.len) : (idx += 1) {
        const node_index = function_indices.items[idx];
        const node = &gb.nodes_by_id.items[node_index];
        const file_bytes = cachedFileBytes(allocator, &file_cache, repo_path, node.file_path) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => continue,
        };
        const end_line = nextFunctionStartLine(gb, function_indices.items, idx) orelse countLines(file_bytes);
        if (end_line < node.start_line) continue;

        const snippet = try readInlineLines(allocator, file_bytes, node.start_line, end_line);
        defer allocator.free(snippet);

        const fingerprint = (try minhash.computeFromSource(allocator, snippet)) orelse {
            try setNodeFingerprintProperty(allocator, node, null);
            continue;
        };
        try setNodeFingerprintProperty(allocator, node, fingerprint);
        try candidates.append(allocator, .{
            .node_id = node.id,
            .file_path = node.file_path,
            .file_ext = std.fs.path.extension(node.file_path),
            .fingerprint = fingerprint,
        });
    }

    if (candidates.items.len < 2) return;

    var index = minhash.LshIndex.init(allocator);
    defer index.deinit();
    for (candidates.items) |candidate| {
        _ = try index.insert(.{
            .node_id = candidate.node_id,
            .fingerprint = candidate.fingerprint,
            .file_path = candidate.file_path,
            .file_ext = candidate.file_ext,
        });
    }

    var emitted_per_node = std.AutoHashMap(i64, usize).init(allocator);
    defer emitted_per_node.deinit();

    var candidate_indexes = std.ArrayList(usize).empty;
    defer candidate_indexes.deinit(allocator);

    for (candidates.items) |candidate| {
        if ((emitted_per_node.get(candidate.node_id) orelse 0) >= minhash.max_edges_per_node) continue;

        candidate_indexes.clearRetainingCapacity();
        try index.query(&candidate.fingerprint, &candidate_indexes);
        for (candidate_indexes.items) |candidate_index| {
            const other = candidates.items[candidate_index];
            if (other.node_id == candidate.node_id) continue;
            if (!std.mem.eql(u8, candidate.file_ext, other.file_ext)) continue;
            if (candidate.node_id >= other.node_id) continue;
            if ((emitted_per_node.get(candidate.node_id) orelse 0) >= minhash.max_edges_per_node) break;

            const score = minhash.jaccard(&candidate.fingerprint, &other.fingerprint);
            if (score < minhash.jaccard_threshold) continue;

            const props = try std.fmt.allocPrint(
                allocator,
                "{{\"jaccard\":{d:.3},\"same_file\":{s}}}",
                .{ score, if (std.mem.eql(u8, candidate.file_path, other.file_path)) "true" else "false" },
            );
            defer allocator.free(props);
            _ = gb.insertEdgeWithProperties(candidate.node_id, other.node_id, "SIMILAR_TO", props) catch |err| switch (err) {
                GraphBufferError.DuplicateEdge => 0,
                else => return error.OutOfMemory,
            };
            try emitted_per_node.put(candidate.node_id, (emitted_per_node.get(candidate.node_id) orelse 0) + 1);
        }
    }
}

fn lessFunctionNodeIndex(gb: *const GraphBuffer, lhs: usize, rhs: usize) bool {
    const left = gb.nodes_by_id.items[lhs];
    const right = gb.nodes_by_id.items[rhs];
    const file_order = std.mem.order(u8, left.file_path, right.file_path);
    if (file_order != .eq) {
        return file_order == .lt;
    }
    if (left.start_line != right.start_line) {
        return left.start_line < right.start_line;
    }
    return left.id < right.id;
}

fn nextFunctionStartLine(
    gb: *const GraphBuffer,
    sorted_indices: []const usize,
    start_idx: usize,
) ?i32 {
    const current = gb.nodes_by_id.items[sorted_indices[start_idx]];
    var idx = start_idx + 1;
    while (idx < sorted_indices.len) : (idx += 1) {
        const candidate = gb.nodes_by_id.items[sorted_indices[idx]];
        if (!std.mem.eql(u8, candidate.file_path, current.file_path)) return null;
        if (candidate.start_line > current.start_line) {
            return candidate.start_line - 1;
        }
    }
    return null;
}

fn cachedFileBytes(
    allocator: std.mem.Allocator,
    file_cache: *std.StringHashMap([]u8),
    repo_path: []const u8,
    rel_path: []const u8,
) ![]const u8 {
    if (file_cache.get(rel_path)) |bytes| {
        return bytes;
    }

    const absolute_path = try std.fs.path.resolve(allocator, &.{ repo_path, rel_path });
    defer allocator.free(absolute_path);

    const bytes = try std.fs.cwd().readFileAlloc(allocator, absolute_path, 8 * 1024 * 1024);
    const key = try allocator.dupe(u8, rel_path);
    errdefer allocator.free(key);
    try file_cache.put(key, bytes);
    return bytes;
}

fn setNodeFingerprintProperty(
    allocator: std.mem.Allocator,
    node: *BufferNode,
    fingerprint: ?minhash.Fingerprint,
) !void {
    allocator.free(node.properties_json);
    if (fingerprint) |fp| {
        var hex_buf: [minhash.k * 8]u8 = undefined;
        minhash.toHex(&fp, &hex_buf);
        node.properties_json = try std.fmt.allocPrint(
            allocator,
            "{{\"fp\":\"{s}\",\"similarity_source\":\"lexical_trigram\"}}",
            .{hex_buf},
        );
    } else {
        node.properties_json = try allocator.dupe(u8, "{}");
    }
}

fn countLines(bytes: []const u8) i32 {
    if (bytes.len == 0) return 0;
    var lines: i32 = 1;
    for (bytes) |byte| {
        if (byte == '\n') lines += 1;
    }
    return lines;
}

fn readInlineLines(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    start_line: i32,
    end_line: i32,
) ![]u8 {
    if (start_line <= 0 or end_line < start_line) return allocator.dupe(u8, "");

    var line_no: i32 = 1;
    var start_idx: ?usize = null;
    var end_idx: usize = bytes.len;
    var idx: usize = 0;

    while (idx <= bytes.len) : (idx += 1) {
        if (line_no == start_line and start_idx == null) {
            start_idx = idx;
        }
        if (idx == bytes.len or bytes[idx] == '\n') {
            if (line_no == end_line) {
                end_idx = if (idx < bytes.len) idx + 1 else idx;
                break;
            }
            line_no += 1;
        }
    }

    if (start_idx == null) return allocator.dupe(u8, "");
    return allocator.dupe(u8, bytes[start_idx.?..end_idx]);
}

fn seedRegistryFromGraphBuffer(gb: *const GraphBuffer, reg: *Registry) !void {
    for (gb.nodes()) |node| {
        try reg.add(node.name, node.qualified_name, node.label, node.file_path);
    }
}

fn resolveExtractions(
    gb: *GraphBuffer,
    reg: *Registry,
    extractions: []const OwnedExtraction,
    cancelled: *const std.atomic.Value(bool),
) !void {
    for (extractions) |owned| {
        if (cancelled.load(.acquire)) return PipelineError.Cancelled;
        const extraction = owned.extraction;

        for (extraction.unresolved_imports) |imp| {
            const importer_node = gb.findNodeById(imp.importer_id) orelse continue;
            if (reg.resolve(imp.import_name, imp.importer_id, importer_node.file_path, null)) |res| {
                if (gb.findNodeByQualifiedName(res.qualified_name)) |target| {
                    _ = gb.insertEdge(imp.importer_id, target.id, "IMPORTS") catch {};
                }
            }
        }

        for (extraction.unresolved_calls) |call| {
            const caller_node = gb.findNodeById(call.caller_id) orelse continue;
            if (reg.resolve(call.callee_name, call.caller_id, caller_node.file_path, null)) |res| {
                if (gb.findNodeByQualifiedName(res.qualified_name)) |target| {
                    if (std.mem.eql(u8, target.label, "Class") or std.mem.eql(u8, target.label, "Interface")) continue;
                    if (target.id != call.caller_id) {
                        _ = gb.insertEdge(call.caller_id, target.id, "CALLS") catch {};
                    }
                }
            }
        }

        for (extraction.unresolved_usages) |usage| {
            const user_node = gb.findNodeById(usage.user_id) orelse continue;
            if (reg.resolve(usage.ref_name, usage.user_id, user_node.file_path, null)) |res| {
                if (gb.findNodeByQualifiedName(res.qualified_name)) |target| {
                    if (target.id != usage.user_id) {
                        _ = gb.insertEdge(usage.user_id, target.id, "USAGE") catch {};
                    }
                }
            }
        }

        for (extraction.semantic_hints) |hint| {
            const child_node = gb.findNodeById(hint.child_id) orelse continue;
            if (resolveSemanticTarget(reg, hint, child_node.file_path)) |res| {
                if (gb.findNodeByQualifiedName(res.qualified_name)) |target| {
                    _ = gb.insertEdge(hint.child_id, target.id, hint.relation) catch {};
                }
            }
        }
    }
}

test "pipeline run handles simple extraction pipeline" {
    var s = try store.Store.openMemory(std.testing.allocator);
    defer s.deinit();

    var p = Pipeline.init(std.testing.allocator, "/tmp", .full);
    defer p.deinit();
    try p.run(&s);
}

test "pipeline retention enables call-edge emission across files" {
    const allocator = std.testing.allocator;

    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(
        allocator,
        "/tmp/cbm-pipeline-test-{x}",
        .{project_id},
    );
    defer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    {
        var dir = try std.fs.cwd().openDir(project_dir, .{});
        defer dir.close();

        var util = try dir.createFile("util.py", .{});
        try util.writeAll(
            \\def helper(x):
            \\    return x
            \\
        );
        util.close();

        var app = try dir.createFile("app.py", .{});
        try app.writeAll(
            \\from util import helper
            \\def main():
            \\    return helper(1)
            \\
        );
        app.close();
    }

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();

    var pipeline = Pipeline.init(allocator, project_dir, .full);
    defer pipeline.deinit();
    try pipeline.run(&db);

    const project_name = std.fs.path.basename(project_dir);

    const main_nodes = try db.searchNodes(.{
        .project = project_name,
        .name_pattern = "main",
        .label_pattern = "Function",
        .limit = 10,
    });
    defer db.freeNodes(main_nodes);
    try std.testing.expect(main_nodes.len == 1);

    const helper_nodes = try db.searchNodes(.{
        .project = project_name,
        .name_pattern = "helper",
        .label_pattern = "Function",
        .limit = 10,
    });
    defer db.freeNodes(helper_nodes);
    try std.testing.expect(helper_nodes.len == 1);

    const calls = try db.findEdgesBySource(project_name, main_nodes[0].id, "CALLS");
    defer db.freeEdges(calls);

    if (calls.len != 1) {
        return error.TestUnexpectedResult;
    }

    if (calls[0].target_id != helper_nodes[0].id) {
        std.debug.print(
            "helper node id {d}, expected call target {d}\n",
            .{ helper_nodes[0].id, calls[0].target_id },
        );
        return error.TestUnexpectedResult;
    }
}

test "pipeline resolves aliased imports across files" {
    const allocator = std.testing.allocator;

    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(
        allocator,
        "/tmp/cbm-pipeline-alias-test-{x}",
        .{project_id},
    );
    defer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    {
        var dir = try std.fs.cwd().openDir(project_dir, .{});
        defer dir.close();

        var util = try dir.createFile("util.py", .{});
        try util.writeAll(
            \\def helper(x):
            \\    return x
            \\
        );
        util.close();

        var other = try dir.createFile("other.py", .{});
        try other.writeAll(
            \\def renamed(x):
            \\    return x + 1
            \\
        );
        other.close();

        var app = try dir.createFile("app.py", .{});
        try app.writeAll(
            \\from util import helper as renamed
            \\def main():
            \\    return renamed(1)
            \\
        );
        app.close();
    }

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();

    var pipeline = Pipeline.init(allocator, project_dir, .full);
    defer pipeline.deinit();
    try pipeline.run(&db);

    const project_name = std.fs.path.basename(project_dir);

    const main_nodes = try db.searchNodes(.{
        .project = project_name,
        .name_pattern = "main",
        .label_pattern = "Function",
        .limit = 10,
    });
    defer db.freeNodes(main_nodes);
    try std.testing.expectEqual(@as(usize, 1), main_nodes.len);

    const call_edges = try db.findEdgesBySource(project_name, main_nodes[0].id, "CALLS");
    defer db.freeEdges(call_edges);
    try std.testing.expectEqual(@as(usize, 1), call_edges.len);

    const target = (try db.findNodeById(project_name, call_edges[0].target_id)).?;
    defer db.freeNode(target);
    try std.testing.expectEqualStrings("helper", target.name);
    try std.testing.expectEqualStrings("util.py", target.file_path);
}

test "pipeline incremental reindexes only changed files against stored hashes" {
    const allocator = std.testing.allocator;

    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(
        allocator,
        "/tmp/cbm-pipeline-incremental-test-{x}",
        .{project_id},
    );
    defer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    {
        var dir = try std.fs.cwd().openDir(project_dir, .{});
        defer dir.close();

        var util = try dir.createFile("util.py", .{});
        defer util.close();
        try util.writeAll(
            \\def helper(x):
            \\    return x
            \\
        );

        var app = try dir.createFile("app.py", .{});
        defer app.close();
        try app.writeAll(
            \\from util import helper
            \\def main():
            \\    return helper(1)
            \\
        );
    }

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();

    var pipeline = Pipeline.init(allocator, project_dir, .full);
    defer pipeline.deinit();
    try pipeline.run(&db);

    const project_name = std.fs.path.basename(project_dir);
    const initial_hashes = try db.getFileHashes(project_name);
    defer db.freeFileHashes(initial_hashes);
    try std.testing.expectEqual(@as(usize, 2), initial_hashes.len);

    {
        var dir = try std.fs.cwd().openDir(project_dir, .{});
        defer dir.close();
        var app = try dir.createFile("app.py", .{ .truncate = true });
        defer app.close();
        try app.writeAll(
            \\from util import helper
            \\def start():
            \\    return helper(2)
            \\
        );
    }

    const discovered_files = try discover.discoverFiles(
        allocator,
        project_dir,
        .{ .mode = .full },
    );
    defer pipeline.freeDiscoveredFiles(discovered_files);

    const stored_hashes = try db.getFileHashes(project_name);
    defer db.freeFileHashes(stored_hashes);
    try std.testing.expect(try pipeline.runIncremental(&db, discovered_files, stored_hashes));

    const helper_nodes = try db.searchNodes(.{
        .project = project_name,
        .label_pattern = "Function",
        .name_pattern = "helper",
        .limit = 5,
    });
    defer db.freeNodes(helper_nodes);
    try std.testing.expectEqual(@as(usize, 1), helper_nodes.len);

    const start_nodes = try db.searchNodes(.{
        .project = project_name,
        .label_pattern = "Function",
        .name_pattern = "start",
        .limit = 5,
    });
    defer db.freeNodes(start_nodes);
    try std.testing.expectEqual(@as(usize, 1), start_nodes.len);

    const main_nodes = try db.searchNodes(.{
        .project = project_name,
        .label_pattern = "Function",
        .name_pattern = "main",
        .limit = 5,
    });
    defer db.freeNodes(main_nodes);
    try std.testing.expectEqual(@as(usize, 0), main_nodes.len);

    const calls = try db.findEdgesBySource(project_name, start_nodes[0].id, "CALLS");
    defer db.freeEdges(calls);
    try std.testing.expectEqual(@as(usize, 1), calls.len);
    try std.testing.expectEqual(helper_nodes[0].id, calls[0].target_id);

    const final_hashes = try db.getFileHashes(project_name);
    defer db.freeFileHashes(final_hashes);
    try std.testing.expectEqual(@as(usize, 2), final_hashes.len);
}

test "pipeline parallel extraction path indexes larger projects" {
    if ((std.Thread.getCpuCount() catch 1) <= 1) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(
        allocator,
        "/tmp/cbm-pipeline-parallel-test-{x}",
        .{project_id},
    );
    defer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    var dir = try std.fs.cwd().openDir(project_dir, .{});
    defer dir.close();

    var file_index: usize = 0;
    while (file_index < 40) : (file_index += 1) {
        const file_name = try std.fmt.allocPrint(allocator, "mod{d:0>2}.py", .{file_index});
        defer allocator.free(file_name);
        var file = try dir.createFile(file_name, .{});
        defer file.close();
        const contents = try std.fmt.allocPrint(
            allocator,
            \\def fn_{d}(x):
            \\    return x + {d}
            \\
        ,
            .{ file_index, file_index },
        );
        defer allocator.free(contents);
        try file.writeAll(contents);
    }

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();

    var pipeline = Pipeline.init(allocator, project_dir, .full);
    defer pipeline.deinit();
    try pipeline.run(&db);

    const project_name = std.fs.path.basename(project_dir);
    const function_nodes = try db.searchNodes(.{
        .project = project_name,
        .label_pattern = "Function",
        .limit = 200,
    });
    defer db.freeNodes(function_nodes);
    try std.testing.expectEqual(@as(usize, 40), function_nodes.len);
}

test "pipeline retains parser-backed definitions and expected edges for all readiness languages" {
    const allocator = std.testing.allocator;

    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(
        allocator,
        "/tmp/cbm-pipeline-language-matrix-{x}",
        .{project_id},
    );
    defer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    {
        var dir = try std.fs.cwd().openDir(project_dir, .{});
        defer dir.close();

        try dir.makePath("python");
        var python = try dir.createFile("python/main.py", .{});
        defer python.close();
        try python.writeAll(
            \\class Parent:
            \\    pass
            \\
            \\class Child(Parent):
            \\    pass
            \\
            \\def helper():
            \\    return 1
            \\
            \\def main():
            \\    return helper()
            \\
        );

        try dir.makePath("javascript");
        var js = try dir.createFile("javascript/index.js", .{});
        defer js.close();
        try js.writeAll(
            \\function helper(value) {
            \\  return value + 1;
            \\}
            \\
            \\function main() {
            \\  return helper(7);
            \\}
            \\
        );

        try dir.makePath("typescript");
        var ts = try dir.createFile("typescript/index.ts", .{});
        defer ts.close();
        try ts.writeAll(
            \\interface ServicePort {
            \\  label: string;
            \\}
            \\
            \\class Worker implements ServicePort {
            \\  label: string;
            \\}
            \\
            \\function helper(value: number) {
            \\  return value + 1;
            \\}
            \\
            \\function main() {
            \\  return helper(1);
            \\}
            \\
        );

        try dir.makePath("tsx");
        var tsx = try dir.createFile("tsx/App.tsx", .{});
        defer tsx.close();
        try tsx.writeAll(
            \\type ViewProps = { title: string };
            \\
            \\function render(props: ViewProps) {
            \\  return <span>{props.title}</span>;
            \\}
            \\
            \\function main() {
            \\  return render({ title: "ok" });
            \\}
            \\
        );

        try dir.makePath("rust");
        var rs = try dir.createFile("rust/lib.rs", .{});
        defer rs.close();
        try rs.writeAll(
            \\struct Service {
            \\  id: u64
            \\}
            \\
            \\trait Speaker {}
            \\
            \\fn helper() {}
            \\
            \\fn main() {
            \\  helper();
            \\}
            \\
            \\impl Speaker for Service {
            \\  fn speak(self) {}
            \\}
            \\
        );

        try dir.makePath("zig");
        var zf = try dir.createFile("zig/main.zig", .{});
        defer zf.close();
        try zf.writeAll(
            \\const std = @import("std");
            \\
            \\fn helper() u8 {
            \\  return 1;
            \\}
            \\
            \\fn main() void {
            \\  _ = helper();
            \\}
            \\
        );
    }

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();

    var pipeline = Pipeline.init(allocator, project_dir, .full);
    defer pipeline.deinit();
    try pipeline.run(&db);

    const project_name = std.fs.path.basename(project_dir);

    const python_child = try findSingleNodeByNameInFile(&db, project_name, "Class", "Child", "python/main.py");
    const python_parent = try findSingleNodeByNameInFile(&db, project_name, "Class", "Parent", "python/main.py");
    const python_main = try findSingleNodeByNameInFile(&db, project_name, "Function", "main", "python/main.py");
    const py_helper = try findSingleNodeByNameInFile(&db, project_name, "Function", "helper", "python/main.py");
    const py_calls = try db.findEdgesBySource(project_name, python_main, "CALLS");
    defer db.freeEdges(py_calls);
    try std.testing.expectEqual(@as(usize, 1), py_calls.len);
    try std.testing.expectEqual(py_helper, py_calls[0].target_id);
    const py_inherits = try db.findEdgesBySource(project_name, python_child, "INHERITS");
    defer db.freeEdges(py_inherits);
    try std.testing.expectEqual(@as(usize, 1), py_inherits.len);
    try std.testing.expectEqual(python_parent, py_inherits[0].target_id);

    const js_main = try findSingleNodeByNameInFile(&db, project_name, "Function", "main", "javascript/index.js");
    const js_calls = try db.findEdgesBySource(project_name, js_main, "CALLS");
    defer db.freeEdges(js_calls);
    try std.testing.expectEqual(@as(usize, 1), js_calls.len);

    const ts_main = try findSingleNodeByNameInFile(&db, project_name, "Function", "main", "typescript/index.ts");
    const ts_calls = try db.findEdgesBySource(project_name, ts_main, "CALLS");
    defer db.freeEdges(ts_calls);
    try std.testing.expectEqual(@as(usize, 1), ts_calls.len);

    const tsx_main = try findSingleNodeByNameInFile(&db, project_name, "Function", "main", "tsx/App.tsx");
    const tsx_calls = try db.findEdgesBySource(project_name, tsx_main, "CALLS");
    defer db.freeEdges(tsx_calls);
    try std.testing.expectEqual(@as(usize, 1), tsx_calls.len);

    const rust_main = try findSingleNodeByNameInFile(&db, project_name, "Function", "main", "rust/lib.rs");
    const rust_calls = try db.findEdgesBySource(project_name, rust_main, "CALLS");
    defer db.freeEdges(rust_calls);
    try std.testing.expectEqual(@as(usize, 1), rust_calls.len);
    const rust_child = try findSingleNodeByNameInFile(&db, project_name, "Class", "Service", "rust/lib.rs");
    const rust_trait = try findSingleNodeByNameInFile(&db, project_name, "Interface", "Speaker", "rust/lib.rs");
    const rust_impls = try db.findEdgesBySource(project_name, rust_child, "IMPLEMENTS");
    defer db.freeEdges(rust_impls);
    try std.testing.expectEqual(@as(usize, 1), rust_impls.len);
    try std.testing.expectEqual(rust_trait, rust_impls[0].target_id);

    const zig_main = try findSingleNodeByNameInFile(&db, project_name, "Function", "main", "zig/main.zig");
    const zig_calls = try db.findEdgesBySource(project_name, zig_main, "CALLS");
    defer db.freeEdges(zig_calls);
    try std.testing.expectEqual(@as(usize, 1), zig_calls.len);

    const python_file = try findSingleNodeByNameInFile(&db, project_name, "File", "main.py", "python/main.py");
    const py_contains = try db.findEdgesBySource(project_name, python_file, "CONTAINS");
    defer db.freeEdges(py_contains);
    try std.testing.expect(py_contains.len > 0);
}

test "pipeline resolves rust use aliases across files" {
    const allocator = std.testing.allocator;

    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(
        allocator,
        "/tmp/cbm-pipeline-rust-use-{x}",
        .{project_id},
    );
    defer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    {
        var dir = try std.fs.cwd().openDir(project_dir, .{});
        defer dir.close();

        try dir.makePath("src");

        var util = try dir.createFile("src/util.rs", .{});
        try util.writeAll(
            \\pub fn helper() {}
            \\
        );
        util.close();

        var other = try dir.createFile("src/other.rs", .{});
        try other.writeAll(
            \\pub fn helper() {}
            \\
        );
        other.close();

        var main = try dir.createFile("src/main.rs", .{});
        try main.writeAll(
            \\use crate::util::helper;
            \\fn run() {
            \\    helper();
            \\}
            \\
        );
        main.close();
    }

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();

    var pipeline = Pipeline.init(allocator, project_dir, .full);
    defer pipeline.deinit();
    try pipeline.run(&db);

    const project_name = std.fs.path.basename(project_dir);
    const run_nodes = try db.searchNodes(.{
        .project = project_name,
        .name_pattern = "run",
        .label_pattern = "Function",
        .limit = 10,
    });
    defer db.freeNodes(run_nodes);
    try std.testing.expectEqual(@as(usize, 1), run_nodes.len);

    const call_edges = try db.findEdgesBySource(project_name, run_nodes[0].id, "CALLS");
    defer db.freeEdges(call_edges);
    try std.testing.expectEqual(@as(usize, 1), call_edges.len);

    const target = (try db.findNodeById(project_name, call_edges[0].target_id)).?;
    defer db.freeNode(target);
    try std.testing.expectEqualStrings("src/util.rs", target.file_path);
    try std.testing.expectEqualStrings("helper", target.name);
}

test "pipeline creates usage edges without duplicating direct calls" {
    const allocator = std.testing.allocator;

    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(
        allocator,
        "/tmp/cbm-pipeline-usage-{x}",
        .{project_id},
    );
    defer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    {
        var dir = try std.fs.cwd().openDir(project_dir, .{});
        defer dir.close();

        var util = try dir.createFile("util.py", .{});
        defer util.close();
        try util.writeAll(
            \\def helper():
            \\    return 1
            \\
        );

        var app = try dir.createFile("app.py", .{});
        defer app.close();
        try app.writeAll(
            \\from util import helper
            \\def main():
            \\    callback = helper
            \\    return helper()
            \\
        );
    }

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();

    var pipeline = Pipeline.init(allocator, project_dir, .full);
    defer pipeline.deinit();
    try pipeline.run(&db);

    const project_name = std.fs.path.basename(project_dir);
    const main_id = try findSingleNodeByNameInFile(&db, project_name, "Function", "main", "app.py");
    const helper_id = try findSingleNodeByNameInFile(&db, project_name, "Function", "helper", "util.py");

    const calls = try db.findEdgesBySource(project_name, main_id, "CALLS");
    defer db.freeEdges(calls);
    try std.testing.expectEqual(@as(usize, 1), calls.len);
    try std.testing.expectEqual(helper_id, calls[0].target_id);

    const usages = try db.findEdgesBySource(project_name, main_id, "USAGE");
    defer db.freeEdges(usages);
    try std.testing.expectEqual(@as(usize, 1), usages.len);
    try std.testing.expectEqual(helper_id, usages[0].target_id);
}

test "pipeline emits decorator and multi-target semantic edges" {
    const allocator = std.testing.allocator;

    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(
        allocator,
        "/tmp/cbm-pipeline-semantic-{x}",
        .{project_id},
    );
    defer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    {
        var dir = try std.fs.cwd().openDir(project_dir, .{});
        defer dir.close();

        var py = try dir.createFile("python_semantics.py", .{});
        defer py.close();
        try py.writeAll(
            \\def trace(fn):
            \\    return fn
            \\
            \\class Base:
            \\    pass
            \\
            \\class Mixin:
            \\    pass
            \\
            \\@trace
            \\def run():
            \\    return 1
            \\
            \\class Worker(Base, Mixin):
            \\    pass
            \\
        );

        var ts = try dir.createFile("types.ts", .{});
        defer ts.close();
        try ts.writeAll(
            \\interface BasePort {}
            \\interface ExtraPort {}
            \\interface WorkerPort extends BasePort, ExtraPort {}
            \\class Worker implements WorkerPort, BasePort {}
            \\
        );
    }

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();

    var pipeline = Pipeline.init(allocator, project_dir, .full);
    defer pipeline.deinit();
    try pipeline.run(&db);

    const project_name = std.fs.path.basename(project_dir);

    const run_id = try findSingleNodeByNameInFile(&db, project_name, "Function", "run", "python_semantics.py");
    const trace_id = try findSingleNodeByNameInFile(&db, project_name, "Function", "trace", "python_semantics.py");
    const run_decorators = try db.findEdgesBySource(project_name, run_id, "DECORATES");
    defer db.freeEdges(run_decorators);
    try std.testing.expectEqual(@as(usize, 1), run_decorators.len);
    try std.testing.expectEqual(trace_id, run_decorators[0].target_id);

    const worker_py_id = try findSingleNodeByNameInFile(&db, project_name, "Class", "Worker", "python_semantics.py");
    const base_id = try findSingleNodeByNameInFile(&db, project_name, "Class", "Base", "python_semantics.py");
    const mixin_id = try findSingleNodeByNameInFile(&db, project_name, "Class", "Mixin", "python_semantics.py");
    const py_inherits = try db.findEdgesBySource(project_name, worker_py_id, "INHERITS");
    defer db.freeEdges(py_inherits);
    try std.testing.expect(edgeTargetsContain(py_inherits, base_id));
    try std.testing.expect(edgeTargetsContain(py_inherits, mixin_id));

    const worker_ts_id = try findSingleNodeByNameInFile(&db, project_name, "Class", "Worker", "types.ts");
    const worker_port_id = try findSingleNodeByNameInFile(&db, project_name, "Interface", "WorkerPort", "types.ts");
    const base_port_id = try findSingleNodeByNameInFile(&db, project_name, "Interface", "BasePort", "types.ts");
    const extra_port_id = try findSingleNodeByNameInFile(&db, project_name, "Interface", "ExtraPort", "types.ts");

    const ts_implements = try db.findEdgesBySource(project_name, worker_ts_id, "IMPLEMENTS");
    defer db.freeEdges(ts_implements);
    try std.testing.expect(edgeTargetsContain(ts_implements, worker_port_id));
    try std.testing.expect(edgeTargetsContain(ts_implements, base_port_id));

    const worker_port_inherits = try db.findEdgesBySource(project_name, worker_port_id, "INHERITS");
    defer db.freeEdges(worker_port_inherits);
    try std.testing.expect(edgeTargetsContain(worker_port_inherits, base_port_id));
    try std.testing.expect(edgeTargetsContain(worker_port_inherits, extra_port_id));
}

test "pipeline aligns module-level declaration usages with semantic reference sources" {
    const allocator = std.testing.allocator;

    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(
        allocator,
        "/tmp/cbm-pipeline-decl-usage-{x}",
        .{project_id},
    );
    defer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    {
        var dir = try std.fs.cwd().openDir(project_dir, .{});
        defer dir.close();

        var py = try dir.createFile("python_semantics.py", .{});
        defer py.close();
        try py.writeAll(
            \\def trace(fn):
            \\    return fn
            \\
            \\class Base:
            \\    pass
            \\
            \\@trace
            \\def run() -> int:
            \\    return 1
            \\
            \\class Worker(Base):
            \\    pass
            \\
        );

        var js = try dir.createFile("logger.js", .{});
        defer js.close();
        try js.writeAll(
            \\class BaseLogger {
            \\  write(message) {
            \\    return message;
            \\  }
            \\}
            \\
            \\class FileLogger extends BaseLogger {
            \\  log(message) {
            \\    return this.write(message);
            \\  }
            \\}
            \\
        );

        try dir.makePath("src");
        var rs = try dir.createFile("src/lib.rs", .{});
        defer rs.close();
        try rs.writeAll(
            \\pub trait Runner {
            \\    fn run(&self) -> String;
            \\}
            \\
            \\pub struct Config {
            \\    pub mode: String,
            \\}
            \\
            \\pub struct Worker {
            \\    pub config: Config,
            \\}
            \\
            \\impl Runner for Worker {
            \\    fn run(&self) -> String {
            \\        self.config.mode.clone()
            \\    }
            \\}
            \\
        );
    }

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();

    var pipeline = Pipeline.init(allocator, project_dir, .full);
    defer pipeline.deinit();
    try pipeline.run(&db);

    const project_name = std.fs.path.basename(project_dir);

    const py_module_id = try findSingleNodeByNameInFile(&db, project_name, "Module", "python_semantics", "python_semantics.py");
    const trace_id = try findSingleNodeByNameInFile(&db, project_name, "Function", "trace", "python_semantics.py");
    const base_id = try findSingleNodeByNameInFile(&db, project_name, "Class", "Base", "python_semantics.py");
    const py_usages = try db.findEdgesBySource(project_name, py_module_id, "USAGE");
    defer db.freeEdges(py_usages);
    try std.testing.expect(edgeTargetsContain(py_usages, trace_id));
    try std.testing.expect(edgeTargetsContain(py_usages, base_id));

    const js_module_id = try findSingleNodeByNameInFile(&db, project_name, "Module", "logger", "logger.js");
    const js_base_id = try findSingleNodeByNameInFile(&db, project_name, "Class", "BaseLogger", "logger.js");
    const js_usages = try db.findEdgesBySource(project_name, js_module_id, "USAGE");
    defer db.freeEdges(js_usages);
    try std.testing.expect(edgeTargetsContain(js_usages, js_base_id));

    const rust_module_id = try findSingleNodeByNameInFile(&db, project_name, "Module", "lib", "src/lib.rs");
    const rust_worker_id = try findSingleNodeByNameInFile(&db, project_name, "Class", "Worker", "src/lib.rs");
    const rust_config_id = try findSingleNodeByNameInFile(&db, project_name, "Class", "Config", "src/lib.rs");
    const rust_runner_id = try findSingleNodeByNameInFile(&db, project_name, "Interface", "Runner", "src/lib.rs");
    const rust_usages = try db.findEdgesBySource(project_name, rust_module_id, "USAGE");
    defer db.freeEdges(rust_usages);
    try std.testing.expect(edgeTargetsContain(rust_usages, rust_worker_id));
    try std.testing.expect(edgeTargetsContain(rust_usages, rust_config_id));
    try std.testing.expect(!edgeTargetsContain(rust_usages, rust_runner_id));
}

test "pipeline emits similarity edges and fingerprints for near-duplicate functions" {
    const allocator = std.testing.allocator;

    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(
        allocator,
        "/tmp/cbm-pipeline-similarity-{x}",
        .{project_id},
    );
    defer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    {
        var dir = try std.fs.cwd().openDir(project_dir, .{});
        defer dir.close();

        var first = try dir.createFile("alpha.py", .{});
        defer first.close();
        try first.writeAll(
            \\def run(value):
            \\    total = value + 1
            \\    if total > 10:
            \\        return total
            \\    return value
            \\
        );

        var second = try dir.createFile("beta.py", .{});
        defer second.close();
        try second.writeAll(
            \\def run(item):
            \\    total = item + 1
            \\    if total > 10:
            \\        return total
            \\    return item
            \\
        );
    }

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();

    var pipeline = Pipeline.init(allocator, project_dir, .full);
    defer pipeline.deinit();
    try pipeline.run(&db);

    const project_name = std.fs.path.basename(project_dir);
    const alpha_id = try findSingleNodeByNameInFile(&db, project_name, "Function", "run", "alpha.py");
    const beta_id = try findSingleNodeByNameInFile(&db, project_name, "Function", "run", "beta.py");

    const alpha_nodes = try db.searchNodes(.{
        .project = project_name,
        .label_pattern = "Function",
        .name_pattern = "run",
        .file_pattern = "alpha.py",
        .limit = 1,
    });
    defer db.freeNodes(alpha_nodes);
    try std.testing.expectEqual(@as(usize, 1), alpha_nodes.len);
    try std.testing.expect(std.mem.indexOf(u8, alpha_nodes[0].properties_json, "\"fp\":\"") != null);

    const similar_edges = try db.listEdges(project_name, "SIMILAR_TO");
    defer db.freeEdges(similar_edges);
    try std.testing.expect(similar_edges.len > 0);

    var found_pair = false;
    for (similar_edges) |edge| {
        if ((edge.source_id == alpha_id and edge.target_id == beta_id) or
            (edge.source_id == beta_id and edge.target_id == alpha_id))
        {
            found_pair = true;
            break;
        }
    }
    try std.testing.expect(found_pair);
}

fn findSingleNodeByNameInFile(
    db: *store.Store,
    project_name: []const u8,
    label: []const u8,
    name: []const u8,
    file_path: []const u8,
) !i64 {
    const nodes = try db.searchNodes(.{
        .project = project_name,
        .label_pattern = label,
        .name_pattern = name,
        .file_pattern = file_path,
        .limit = 1,
    });
    defer db.freeNodes(nodes);
    if (nodes.len == 0) return error.TestUnexpectedResult;
    return nodes[0].id;
}

fn edgeTargetsContain(edges: []const store.Edge, target_id: i64) bool {
    for (edges) |edge| {
        if (edge.target_id == target_id) return true;
    }
    return false;
}

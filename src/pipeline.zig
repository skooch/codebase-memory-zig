// pipeline — Indexing pipeline orchestrator.
//
// Orchestrates discovery, extraction, symbol registry, resolution passes, and
// persistence to the store.

const std = @import("std");
const discover = @import("discover.zig");
const graph_buffer = @import("graph_buffer.zig");
const GraphBuffer = graph_buffer.GraphBuffer;
const BufferNode = graph_buffer.BufferNode;
const GraphBufferError = graph_buffer.GraphBufferError;
const extractor = @import("extractor.zig");
const minhash = @import("minhash.zig");
const Registry = @import("registry.zig").Registry;
const hybrid_resolution = @import("hybrid_resolution.zig");
const scip = @import("scip.zig");
const search_index = @import("search_index.zig");
const store = @import("store.zig");
const test_tagging = @import("test_tagging.zig");
const git_history = @import("git_history.zig");
const routes = @import("routes.zig");
const semantic_links = @import("semantic_links.zig");
const service_patterns = @import("service_patterns.zig");

pub const IndexMode = enum {
    full, // read everything, build from scratch
    fast, // skip non-essential files
};

pub const PipelineError = error{
    Cancelled,
    DiscoveryFailed,
    OutOfMemory,
    GraphTooLarge,
} || store.StoreError;

pub const PipelineContext = struct {
    project_name: []const u8,
    repo_path: []const u8,
    allocator: std.mem.Allocator,
    cancelled: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
};

const OwnedExtraction = struct {
    arena: ?*std.heap.ArenaAllocator,
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

        const stored_hashes = try db.getFileHashes(self.project_name);
        defer db.freeFileHashes(stored_hashes);
        if (stored_hashes.len > 0 and
            discovered_files.len <= stored_hashes.len + (stored_hashes.len / 2))
        {
            const used_incremental = self.runIncremental(db, discovered_files, stored_hashes) catch |err| switch (err) {
                error.Cancelled => return PipelineError.Cancelled,
                error.OutOfMemory => return PipelineError.OutOfMemory,
                error.GraphTooLarge => return PipelineError.GraphTooLarge,
                error.SqlError => return PipelineError.SqlError,
                error.OpenFailed => return PipelineError.OpenFailed,
                error.NotFound => return PipelineError.NotFound,
                else => return PipelineError.DiscoveryFailed,
            };
            if (used_incremental) {
                return;
            }
        }

        var gb = GraphBuffer.init(self.allocator, self.project_name);
        defer gb.deinit();

        var reg = Registry.init(self.allocator);
        defer reg.deinit();

        var extractions = std.ArrayList(OwnedExtraction).empty;
        defer freeOwnedExtractions(self.allocator, &extractions);

        try collectExtractions(self, discovered_files, &gb, &reg, &extractions);

        var hybrid = hybrid_resolution.Sidecar.load(self.allocator, self.repo_path) catch |err| blk: {
            std.log.warn("pipeline skipped hybrid resolution sidecar for {s}: {}", .{ self.project_name, err });
            break :blk hybrid_resolution.Sidecar.initEmpty();
        };
        defer hybrid.deinit();

        try resolveExtractions(&gb, &reg, &hybrid, extractions.items, &self.cancelled);
        freeOwnedExtractions(self.allocator, &extractions);

        if (self.cancelled.load(.acquire)) return PipelineError.Cancelled;
        _ = test_tagging.runPass(self.allocator, &gb) catch |err| {
            std.log.warn("pipeline test-tagging pass failed: {}", .{err});
        };

        if (self.cancelled.load(.acquire)) return PipelineError.Cancelled;
        runConfigLinkPass(self.allocator, &gb) catch |err| {
            std.log.warn("pipeline config-link pass failed: {}", .{err});
        };

        if (self.cancelled.load(.acquire)) return PipelineError.Cancelled;
        _ = git_history.runPass(self.allocator, self.repo_path, &gb) catch |err| {
            std.log.warn("pipeline git-history pass failed: {}", .{err});
        };

        if (self.cancelled.load(.acquire)) return PipelineError.Cancelled;
        _ = routes.runPass(self.allocator, &gb) catch |err| {
            std.log.warn("pipeline routes pass failed: {}", .{err});
        };

        if (self.cancelled.load(.acquire)) return PipelineError.Cancelled;
        _ = semantic_links.runPass(self.allocator, &gb) catch |err| {
            std.log.warn("pipeline semantic-links pass failed: {}", .{err});
        };

        if (self.cancelled.load(.acquire)) return PipelineError.Cancelled;
        runSimilarityPass(self.allocator, self.repo_path, &gb) catch |err| {
            std.log.warn("pipeline similarity pass failed: {}", .{err});
        };

        if (self.cancelled.load(.acquire)) return PipelineError.Cancelled;
        try gb.ensureWithinLimits(graph_buffer.default_graph_size_limit);

        try db.beginImmediate();
        var committed = false;
        errdefer if (!committed) db.rollback() catch {};
        try db.deleteProject(self.project_name);
        try db.upsertProject(self.project_name, self.repo_path);
        try gb.dumpToStore(db);

        if (self.cancelled.load(.acquire)) return PipelineError.Cancelled;
        try persistFileHashes(db, self.project_name, discovered_files);

        if (self.cancelled.load(.acquire)) return PipelineError.Cancelled;
        try search_index.refreshProject(self.allocator, db, self.project_name, discovered_files);
        const scip_imported = scip.importProjectOverlay(self.allocator, db, self.project_name, self.repo_path) catch |err| imported: {
            std.log.warn("pipeline skipped SCIP overlay import for {s}: {}", .{ self.project_name, err });
            break :imported 0;
        };
        if (scip_imported > 0) {
            std.log.info("pipeline imported {} SCIP overlay symbols for {s}", .{ scip_imported, self.project_name });
        }
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
            try db.beginImmediate();
            var committed = false;
            errdefer if (!committed) db.rollback() catch {};
            try db.upsertProject(self.project_name, self.repo_path);
            try persistFileHashes(db, self.project_name, discovered_files);
            try db.commit();
            committed = true;
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
        defer freeOwnedExtractions(self.allocator, &extractions);

        try collectExtractions(self, classification.changed_files, &gb, &reg, &extractions);

        var hybrid = hybrid_resolution.Sidecar.load(self.allocator, self.repo_path) catch |err| blk: {
            std.log.warn("pipeline skipped hybrid resolution sidecar for {s}: {}", .{ self.project_name, err });
            break :blk hybrid_resolution.Sidecar.initEmpty();
        };
        defer hybrid.deinit();

        try resolveExtractions(&gb, &reg, &hybrid, extractions.items, &self.cancelled);
        freeOwnedExtractions(self.allocator, &extractions);

        if (self.cancelled.load(.acquire)) return PipelineError.Cancelled;
        _ = test_tagging.runPass(self.allocator, &gb) catch |err| {
            std.log.warn("pipeline test-tagging pass failed: {}", .{err});
        };

        if (self.cancelled.load(.acquire)) return PipelineError.Cancelled;
        runConfigLinkPass(self.allocator, &gb) catch |err| {
            std.log.warn("pipeline config-link pass failed: {}", .{err});
        };

        if (self.cancelled.load(.acquire)) return PipelineError.Cancelled;
        _ = git_history.runPass(self.allocator, self.repo_path, &gb) catch |err| {
            std.log.warn("pipeline git-history pass failed: {}", .{err});
        };

        if (self.cancelled.load(.acquire)) return PipelineError.Cancelled;
        _ = routes.runPass(self.allocator, &gb) catch |err| {
            std.log.warn("pipeline routes pass failed: {}", .{err});
        };

        if (self.cancelled.load(.acquire)) return PipelineError.Cancelled;
        _ = semantic_links.runPass(self.allocator, &gb) catch |err| {
            std.log.warn("pipeline semantic-links pass failed: {}", .{err});
        };

        if (self.cancelled.load(.acquire)) return PipelineError.Cancelled;
        runSimilarityPass(self.allocator, self.repo_path, &gb) catch |err| {
            std.log.warn("pipeline similarity pass failed: {}", .{err});
        };

        if (self.cancelled.load(.acquire)) return PipelineError.Cancelled;
        try gb.ensureWithinLimits(graph_buffer.default_graph_size_limit);

        try db.beginImmediate();
        var committed = false;
        errdefer if (!committed) db.rollback() catch {};
        try db.deleteProject(self.project_name);
        try db.upsertProject(self.project_name, self.repo_path);
        try gb.dumpToStore(db);

        if (self.cancelled.load(.acquire)) return PipelineError.Cancelled;
        try persistFileHashes(db, self.project_name, discovered_files);

        if (self.cancelled.load(.acquire)) return PipelineError.Cancelled;
        try search_index.refreshProject(self.allocator, db, self.project_name, discovered_files);
        const scip_imported = scip.importProjectOverlay(self.allocator, db, self.project_name, self.repo_path) catch |err| imported: {
            std.log.warn("pipeline skipped SCIP overlay import for {s}: {}", .{ self.project_name, err });
            break :imported 0;
        };
        if (scip_imported > 0) {
            std.log.info("pipeline imported {} SCIP overlay symbols for {s}", .{ scip_imported, self.project_name });
        }
        std.log.info(
            "pipeline incremental graph buffer: {} nodes, {} edges",
            .{ gb.nodeCount(), gb.edgeCount() },
        );
        try db.commit();
        committed = true;
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

fn freeOwnedExtractions(
    allocator: std.mem.Allocator,
    extractions: *std.ArrayList(OwnedExtraction),
) void {
    for (extractions.items) |owned| {
        extractor.freeFileExtraction(owned.allocator, owned.extraction);
        if (owned.arena) |arena| {
            const backing = arena.child_allocator;
            arena.deinit();
            backing.destroy(arena);
        }
    }
    extractions.deinit(allocator);
    extractions.* = .empty;
}

fn extractFile(
    allocator: std.mem.Allocator,
    project_name: []const u8,
    file: discover.FileInfo,
    gb: *GraphBuffer,
) !extractor.FileExtraction {
    return try extractor.extractFile(allocator, project_name, file, gb);
}

fn normalizePath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const copied = try allocator.dupe(u8, path);
    for (copied) |*c| {
        if (c.* == std.fs.path.sep) c.* = '/';
    }
    return copied;
}

fn ensureProjectStructure(
    allocator: std.mem.Allocator,
    project_name: []const u8,
    file: discover.FileInfo,
    gb: *GraphBuffer,
) !void {
    const project_id = try gb.upsertNode("Project", project_name, project_name, "", 0, 0);

    const normalized_rel = try normalizePath(allocator, file.rel_path);
    defer allocator.free(normalized_rel);

    const file_name = std.fs.path.basename(file.rel_path);
    const file_qn = try std.fmt.allocPrint(
        allocator,
        "{s}:file:{s}:{s}",
        .{ project_name, normalized_rel, @tagName(file.language) },
    );
    defer allocator.free(file_qn);

    const ext = std.fs.path.extension(file_name);
    const file_props = if (test_tagging.isTestPath(file.rel_path))
        try std.fmt.allocPrint(
            allocator,
            "{{\"extension\":\"{s}\",\"is_test\":true}}",
            .{ext},
        )
    else
        try std.fmt.allocPrint(
            allocator,
            "{{\"extension\":\"{s}\"}}",
            .{ext},
        );
    defer allocator.free(file_props);

    const file_id = try gb.upsertNodeWithProperties(
        "File",
        file_name,
        file_qn,
        file.rel_path,
        1,
        1,
        file_props,
    );

    const maybe_dir = std.fs.path.dirname(file.rel_path);
    if (maybe_dir == null or maybe_dir.?.len == 0) {
        _ = gb.insertEdge(project_id, file_id, "CONTAINS_FILE") catch |err| switch (err) {
            GraphBufferError.DuplicateEdge => 0,
            else => return err,
        };
        return;
    }

    const parent_id = try ensureFolderChain(allocator, project_name, maybe_dir.?, gb);
    _ = gb.insertEdge(parent_id, file_id, "CONTAINS_FILE") catch |err| switch (err) {
        GraphBufferError.DuplicateEdge => 0,
        else => return err,
    };
}

fn ensureFolderChain(
    allocator: std.mem.Allocator,
    project_name: []const u8,
    dir_path: []const u8,
    gb: *GraphBuffer,
) !i64 {
    const normalized_dir = try normalizePath(allocator, dir_path);
    defer allocator.free(normalized_dir);

    var built = std.ArrayList(u8).empty;
    defer built.deinit(allocator);

    var last_folder_id = gb.findNodeId(project_name) orelse 0;
    var parts = std.mem.splitScalar(u8, normalized_dir, '/');
    while (parts.next()) |part| {
        if (part.len == 0) continue;
        if (built.items.len > 0) try built.append(allocator, '/');
        try built.appendSlice(allocator, part);

        const current_path = built.items;
        const folder_qn = try std.fmt.allocPrint(
            allocator,
            "{s}:folder:{s}",
            .{ project_name, current_path },
        );
        defer allocator.free(folder_qn);

        const folder_id = try gb.upsertNode("Folder", part, folder_qn, "", 0, 0);
        if (last_folder_id != 0) {
            _ = gb.insertEdge(last_folder_id, folder_id, "CONTAINS_FOLDER") catch |err| switch (err) {
                GraphBufferError.DuplicateEdge => 0,
                else => return err,
            };
        }
        last_folder_id = folder_id;
    }

    return last_folder_id;
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

        const file_arena = self.allocator.create(std.heap.ArenaAllocator) catch
            return PipelineError.OutOfMemory;
        file_arena.* = std.heap.ArenaAllocator.init(self.allocator);
        errdefer {
            file_arena.deinit();
            self.allocator.destroy(file_arena);
        }
        const arena_alloc = file_arena.allocator();

        ensureProjectStructure(arena_alloc, self.project_name, file, gb) catch |err| switch (err) {
            error.OutOfMemory => return PipelineError.OutOfMemory,
            else => return PipelineError.DiscoveryFailed,
        };
        const extraction = extractFile(arena_alloc, self.project_name, file, gb) catch |err| {
            std.log.warn("extractor failed for {s}: {}", .{ file.rel_path, err });
            file_arena.deinit();
            self.allocator.destroy(file_arena);
            continue;
        };
        try registerExtraction(reg, extraction);
        logExtractionDebug(extraction);
        try out.append(self.allocator, .{
            .arena = file_arena,
            .allocator = arena_alloc,
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
            .arena = null,
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
        ensureProjectStructure(std.heap.c_allocator, ctx.project_name, ctx.files[idx], &local_gb) catch |err| {
            std.log.warn("project structure failed for {s}: {}", .{ ctx.files[idx].rel_path, err });
            local_gb.deinit();
            continue;
        };
        const extraction = extractFile(std.heap.c_allocator, ctx.project_name, ctx.files[idx], &local_gb) catch |err| {
            std.log.warn("extractor failed for {s}: {}", .{ ctx.files[idx].rel_path, err });
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

const ConfigEntry = struct {
    node_id: i64,
    name: []const u8,
    normalized: []const u8,
};

const CodeEntry = struct {
    node_id: i64,
    normalized: []const u8,
};

fn runConfigLinkPass(
    allocator: std.mem.Allocator,
    gb: *GraphBuffer,
) error{OutOfMemory}!void {
    var config_entries = std.ArrayList(ConfigEntry).empty;
    defer {
        for (config_entries.items) |entry| {
            allocator.free(entry.name);
            allocator.free(entry.normalized);
        }
        config_entries.deinit(allocator);
    }

    var code_entries = std.ArrayList(CodeEntry).empty;
    defer {
        for (code_entries.items) |entry| allocator.free(entry.normalized);
        code_entries.deinit(allocator);
    }

    for (gb.nodes()) |node| {
        if (std.mem.eql(u8, node.label, "Variable") and hasConfigExtension(node.file_path)) {
            const normalized = normalizeConfigName(allocator, node.name, true) orelse continue;
            try config_entries.append(allocator, .{
                .node_id = node.id,
                .name = try allocator.dupe(u8, node.name),
                .normalized = normalized,
            });
            continue;
        }

        if (hasConfigExtension(node.file_path)) continue;
        if (!std.mem.eql(u8, node.label, "Function") and
            !std.mem.eql(u8, node.label, "Variable") and
            !std.mem.eql(u8, node.label, "Class"))
        {
            continue;
        }
        const normalized = normalizeConfigName(allocator, node.name, false) orelse continue;
        try code_entries.append(allocator, .{
            .node_id = node.id,
            .normalized = normalized,
        });
    }

    for (config_entries.items) |cfg| {
        for (code_entries.items) |code| {
            var confidence: f64 = 0.0;
            if (std.mem.eql(u8, code.normalized, cfg.normalized)) {
                confidence = 1.0;
            } else if (std.mem.indexOf(u8, code.normalized, cfg.normalized) != null) {
                confidence = 0.75;
            }
            if (confidence <= 0.0) continue;
            const props = try std.fmt.allocPrint(
                allocator,
                "{{\"strategy\":\"key_symbol\",\"confidence\":{d:.2},\"config_key\":\"{s}\"}}",
                .{ confidence, cfg.name },
            );
            defer allocator.free(props);
            _ = gb.insertEdgeWithProperties(code.node_id, cfg.node_id, "CONFIGURES", props) catch |err| switch (err) {
                GraphBufferError.DuplicateEdge => 0,
                else => return error.OutOfMemory,
            };
        }
    }

    runConfigLinkStrategy2(allocator, gb) catch |err| {
        std.log.warn("pipeline config-link strategy 2 failed: {}", .{err});
    };
}

fn isManifestFile(path: []const u8) bool {
    const base = std.fs.path.basename(path);
    return std.mem.eql(u8, base, "package.json") or
        std.mem.eql(u8, base, "Cargo.toml") or
        std.mem.eql(u8, base, "go.mod") or
        std.mem.eql(u8, base, "requirements.txt") or
        std.mem.eql(u8, base, "Gemfile") or
        std.mem.eql(u8, base, "pom.xml") or
        std.mem.eql(u8, base, "composer.json") or
        std.mem.eql(u8, base, "build.gradle") or
        std.mem.eql(u8, base, "pyproject.toml") or
        std.mem.eql(u8, base, "setup.py") or
        std.mem.eql(u8, base, "setup.cfg");
}

const DepEntry = struct {
    node_id: i64,
    name: []const u8,
};

fn runConfigLinkStrategy2(
    allocator: std.mem.Allocator,
    gb: *GraphBuffer,
) error{OutOfMemory}!void {
    // Collect dependency Variable nodes from manifest files.
    var dep_entries = std.ArrayList(DepEntry).empty;
    defer dep_entries.deinit(allocator);

    for (gb.nodes()) |node| {
        if (!std.mem.eql(u8, node.label, "Variable")) continue;
        if (!isManifestFile(node.file_path)) continue;
        try dep_entries.append(allocator, .{
            .node_id = node.id,
            .name = node.name,
        });
    }
    if (dep_entries.items.len == 0) return;

    // Collect all IMPORTS edges and their source/target nodes.
    for (gb.edgeItems()) |edge| {
        if (!std.mem.eql(u8, edge.edge_type, "IMPORTS")) continue;
        const source_node = gb.findNodeById(edge.source_id) orelse continue;
        const target_node = gb.findNodeById(edge.target_id) orelse continue;

        for (dep_entries.items) |dep| {
            var confidence: f64 = 0.0;

            // Exact match: dep name equals the import target name.
            if (std.mem.eql(u8, dep.name, target_node.name)) {
                confidence = 0.95;
            }
            // Substring match: dep name appears in the import target QN.
            else if (std.mem.indexOf(u8, target_node.qualified_name, dep.name) != null) {
                confidence = 0.80;
            }

            if (confidence <= 0.0) continue;

            const props = try std.fmt.allocPrint(
                allocator,
                "{{\"strategy\":\"dependency_import\",\"confidence\":{d:.2},\"dep_name\":\"{s}\"}}",
                .{ confidence, dep.name },
            );
            defer allocator.free(props);
            _ = gb.insertEdgeWithProperties(source_node.id, dep.node_id, "CONFIGURES", props) catch |err| switch (err) {
                GraphBufferError.DuplicateEdge => 0,
                else => return error.OutOfMemory,
            };
        }
    }
}

fn hasConfigExtension(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".yaml") or
        std.mem.endsWith(u8, path, ".yml") or
        std.mem.endsWith(u8, path, ".toml") or
        std.mem.endsWith(u8, path, ".json") or
        std.mem.endsWith(u8, path, ".ini") or
        std.mem.endsWith(u8, path, ".xml");
}

fn isEnvStyleConfigName(name: []const u8) bool {
    if (name.len == 0) return false;

    var saw_upper = false;
    for (name) |ch| {
        if (std.ascii.isUpper(ch)) {
            saw_upper = true;
            continue;
        }
        if (std.ascii.isDigit(ch) or ch == '_') continue;
        return false;
    }
    return saw_upper;
}

fn normalizeConfigName(
    allocator: std.mem.Allocator,
    name: []const u8,
    require_two_long_tokens: bool,
) ?[]u8 {
    if (name.len == 0) return null;
    const preserve_upper_runs = isEnvStyleConfigName(name);
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var token_lengths = std.ArrayList(usize).empty;
    defer token_lengths.deinit(allocator);

    var current_len: usize = 0;
    var prev_was_separator = true;
    var i: usize = 0;
    while (i < name.len) : (i += 1) {
        const ch = name[i];
        if (!std.ascii.isAlphanumeric(ch)) {
            if (current_len > 0) {
                token_lengths.append(allocator, current_len) catch return null;
                current_len = 0;
            }
            prev_was_separator = true;
            continue;
        }
        if (!preserve_upper_runs and std.ascii.isUpper(ch) and !prev_was_separator and current_len > 0) {
            token_lengths.append(allocator, current_len) catch return null;
            current_len = 0;
            prev_was_separator = true;
        }
        if (prev_was_separator and out.items.len > 0) {
            out.append(allocator, ' ') catch return null;
        }
        out.append(allocator, std.ascii.toLower(ch)) catch return null;
        current_len += 1;
        prev_was_separator = false;
    }
    if (current_len > 0) {
        token_lengths.append(allocator, current_len) catch return null;
    }
    if (out.items.len == 0) return null;
    if (require_two_long_tokens) {
        if (token_lengths.items.len < 2) return null;
        for (token_lengths.items) |len| {
            if (len < 3) return null;
        }
    }
    return out.toOwnedSlice(allocator) catch null;
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

fn resolveImportTarget(
    gb: *GraphBuffer,
    reg: *Registry,
    imp: extractor.UnresolvedImport,
    importer_file_path: []const u8,
) ?i64 {
    if (reg.resolve(imp.import_name, imp.importer_id, importer_file_path, null)) |res| {
        if (gb.findNodeByQualifiedName(res.qualified_name)) |target| {
            return target.id;
        }
    }

    if (!std.mem.endsWith(u8, imp.file_path, ".py") or imp.binding_alias.len > 0) return null;

    var module_path_buf: [512]u8 = undefined;
    if (pythonImportModulePath(imp.import_name, &module_path_buf)) |module_path| {
        for (gb.nodes()) |node| {
            if (!std.mem.eql(u8, node.label, "Module")) continue;
            if (std.mem.eql(u8, node.file_path, module_path)) return node.id;
        }
    }
    return null;
}

fn pythonImportModulePath(import_name: []const u8, buf: []u8) ?[]const u8 {
    if (import_name.len == 0 or import_name.len + 3 > buf.len) return null;
    var idx: usize = 0;
    for (import_name) |ch| {
        buf[idx] = if (ch == '.') '/' else ch;
        idx += 1;
    }
    @memcpy(buf[idx .. idx + 3], ".py");
    return buf[0 .. idx + 3];
}

fn resolveExtractions(
    gb: *GraphBuffer,
    reg: *Registry,
    hybrid: *const hybrid_resolution.Sidecar,
    extractions: []const OwnedExtraction,
    cancelled: *const std.atomic.Value(bool),
) !void {
    for (extractions) |owned| {
        if (cancelled.load(.acquire)) return PipelineError.Cancelled;
        const extraction = owned.extraction;

        for (extraction.unresolved_imports) |imp| {
            const importer_node = gb.findNodeById(imp.importer_id) orelse continue;
            if (!imp.emit_edge) continue;
            if (resolveImportTarget(gb, reg, imp, importer_node.file_path)) |target_id| {
                if (target_id != imp.importer_id) {
                    try insertResolvedEdge(gb, imp.importer_id, target_id, "IMPORTS");
                }
            }
        }

        for (extraction.unresolved_calls) |call| {
            const caller_node = gb.findNodeById(call.caller_id) orelse continue;
            if (call.route_path.len > 0 and call.route_method.len > 0) {
                try emitRouteRegistration(gb, reg, call, caller_node);
                continue;
            }
            if (hybrid.resolveCall(
                call.file_path,
                caller_node.qualified_name,
                call.callee_name,
                call.full_callee_name,
            )) |res| {
                if (try emitResolvedCall(gb, call, res.qualified_name, res.strategy, res.confidence)) {
                    continue;
                }
            }
            if (reg.resolve(call.callee_name, call.caller_id, caller_node.file_path, null)) |res| {
                if (try emitResolvedCall(gb, call, res.qualified_name, res.strategy, res.confidence)) {
                    continue;
                }
            } else if (service_patterns.classify(call.full_callee_name)) |kind| {
                const edge_type: []const u8 = switch (kind) {
                    .http_client => "HTTP_CALLS",
                    .async_broker => "ASYNC_CALLS",
                    .route_registration => "CALLS",
                };
                if (std.mem.eql(u8, edge_type, "HTTP_CALLS") or std.mem.eql(u8, edge_type, "ASYNC_CALLS")) {
                    _ = try emitServiceRouteCall(gb, call, edge_type, call.full_callee_name);
                }
            }
        }

        for (extraction.unresolved_usages) |usage| {
            const user_node = gb.findNodeById(usage.user_id) orelse continue;
            if (reg.resolve(usage.ref_name, usage.user_id, user_node.file_path, null)) |res| {
                if (gb.findNodeByQualifiedName(res.qualified_name)) |target| {
                    if (target.id != usage.user_id) {
                        try insertResolvedEdge(gb, usage.user_id, target.id, "USAGE");
                    }
                }
            }
        }

        for (extraction.semantic_hints) |hint| {
            const child_node = gb.findNodeById(hint.child_id) orelse continue;
            if (resolveSemanticTarget(reg, hint, child_node.file_path)) |res| {
                if (gb.findNodeByQualifiedName(res.qualified_name)) |target| {
                    try insertResolvedEdge(gb, hint.child_id, target.id, hint.relation);
                }
            }
        }

        for (extraction.unresolved_throws) |throw_item| {
            const thrower_node = gb.findNodeById(throw_item.thrower_id) orelse continue;
            if (reg.resolve(throw_item.exception_name, throw_item.thrower_id, thrower_node.file_path, null)) |res| {
                if (gb.findNodeByQualifiedName(res.qualified_name)) |target| {
                    const is_unchecked = std.mem.indexOf(u8, throw_item.exception_name, "Error") != null or
                        std.mem.indexOf(u8, throw_item.exception_name, "Panic") != null or
                        std.mem.indexOf(u8, throw_item.exception_name, "error") != null or
                        std.mem.indexOf(u8, throw_item.exception_name, "panic") != null;
                    const edge_type: []const u8 = if (is_unchecked) "RAISES" else "THROWS";
                    try insertResolvedEdge(gb, throw_item.thrower_id, target.id, edge_type);
                }
            }
        }
    }
}

fn emitResolvedCall(
    gb: *GraphBuffer,
    call: extractor.UnresolvedCall,
    qualified_name: []const u8,
    strategy: []const u8,
    confidence: f64,
) PipelineError!bool {
    const target = gb.findNodeByQualifiedName(qualified_name) orelse return false;
    if (std.mem.eql(u8, target.label, "Class") or std.mem.eql(u8, target.label, "Interface")) return false;

    const edge_type: []const u8 = if (classifyResolvedCall(call, qualified_name)) |kind| switch (kind) {
        .http_client => "HTTP_CALLS",
        .async_broker => "ASYNC_CALLS",
        .route_registration => "CALLS",
    } else "CALLS";

    if ((std.mem.eql(u8, edge_type, "HTTP_CALLS") or std.mem.eql(u8, edge_type, "ASYNC_CALLS")) and call.first_string_arg.len > 0) {
        if (try emitServiceRouteCall(gb, call, edge_type, qualified_name)) {
            return true;
        }
    }

    if (std.mem.eql(u8, strategy, "hybrid_sidecar")) {
        const props = std.fmt.allocPrint(
            gb.allocator,
            "{{\"callee\":\"{s}\",\"strategy\":\"{s}\",\"confidence\":{d}}}",
            .{
                if (call.full_callee_name.len > 0) call.full_callee_name else call.callee_name,
                strategy,
                confidence,
            },
        ) catch return PipelineError.OutOfMemory;
        defer gb.allocator.free(props);
        try insertResolvedEdgeWithProperties(gb, call.caller_id, target.id, edge_type, props);
    } else {
        try insertResolvedEdge(gb, call.caller_id, target.id, edge_type);
    }

    if (std.mem.eql(u8, edge_type, "CALLS")) {
        _ = try emitArgUrlRouteCall(gb, call);
    }
    return true;
}

fn emitRouteRegistration(
    gb: *GraphBuffer,
    reg: *Registry,
    call: extractor.UnresolvedCall,
    caller_node: *const BufferNode,
) PipelineError!void {
    const route_id = routes.upsertHttpRoute(
        gb.allocator,
        gb,
        call.file_path,
        call.route_method,
        call.route_path,
        "route_registration",
    ) catch return PipelineError.OutOfMemory;

    const call_props = std.fmt.allocPrint(
        gb.allocator,
        "{{\"callee\":\"{s}\",\"url_path\":\"{s}\",\"via\":\"route_registration\"}}",
        .{ if (call.full_callee_name.len > 0) call.full_callee_name else call.callee_name, call.route_path },
    ) catch return PipelineError.OutOfMemory;
    defer gb.allocator.free(call_props);
    try insertResolvedEdgeWithProperties(gb, call.caller_id, route_id, "CALLS", call_props);

    if (call.route_handler_ref.len == 0) return;
    if (reg.resolve(call.route_handler_ref, call.caller_id, caller_node.file_path, null)) |handler_res| {
        if (gb.findNodeByQualifiedName(handler_res.qualified_name)) |handler| {
            const handler_props = std.fmt.allocPrint(
                gb.allocator,
                "{{\"handler\":\"{s}\"}}",
                .{handler.qualified_name},
            ) catch return PipelineError.OutOfMemory;
            defer gb.allocator.free(handler_props);
            try insertResolvedEdgeWithProperties(gb, handler.id, route_id, "HANDLES", handler_props);
        }
    }
}

fn classifyResolvedCall(call: extractor.UnresolvedCall, resolved_qn: []const u8) ?service_patterns.PatternKind {
    if (service_patterns.classify(resolved_qn)) |kind| return kind;
    if (call.full_callee_name.len > 0) return service_patterns.classify(call.full_callee_name);
    return null;
}

fn emitArgUrlRouteCall(
    gb: *GraphBuffer,
    call: extractor.UnresolvedCall,
) PipelineError!bool {
    if (!isPathRouteArg(call.first_string_arg)) return false;

    const route_id = routes.upsertHttpRoute(
        gb.allocator,
        gb,
        call.file_path,
        "ANY",
        call.first_string_arg,
        "arg_url",
    ) catch return PipelineError.OutOfMemory;

    const props = std.fmt.allocPrint(
        gb.allocator,
        "{{\"callee\":\"{s}\",\"url_path\":\"{s}\",\"via\":\"arg_url\"}}",
        .{ if (call.full_callee_name.len > 0) call.full_callee_name else call.callee_name, call.first_string_arg },
    ) catch return PipelineError.OutOfMemory;
    defer gb.allocator.free(props);

    try insertResolvedEdgeWithProperties(gb, call.caller_id, route_id, "HTTP_CALLS", props);
    return true;
}

fn emitServiceRouteCall(
    gb: *GraphBuffer,
    call: extractor.UnresolvedCall,
    edge_type: []const u8,
    resolved_qn: []const u8,
) PipelineError!bool {
    const route_arg = serviceRouteArg(edge_type, call) orelse return false;

    const method_or_broker = if (std.mem.eql(u8, edge_type, "HTTP_CALLS"))
        (service_patterns.httpMethod(if (call.full_callee_name.len > 0) call.full_callee_name else resolved_qn) orelse
            service_patterns.httpMethod(resolved_qn) orelse
            httpMethodLiteral(call.first_string_arg) orelse
            "ANY")
    else
        (service_patterns.asyncBroker(if (call.full_callee_name.len > 0) call.full_callee_name else resolved_qn) orelse
            service_patterns.asyncBroker(resolved_qn) orelse
            "async");

    const route_id = if (std.mem.eql(u8, edge_type, "HTTP_CALLS"))
        routes.upsertHttpRoute(
            gb.allocator,
            gb,
            call.file_path,
            method_or_broker,
            route_arg,
            "service_call",
        ) catch return PipelineError.OutOfMemory
    else
        routes.upsertAsyncRoute(
            gb.allocator,
            gb,
            call.file_path,
            method_or_broker,
            route_arg,
            "service_call",
        ) catch return PipelineError.OutOfMemory;

    const call_props = if (std.mem.eql(u8, edge_type, "HTTP_CALLS"))
        std.fmt.allocPrint(
            gb.allocator,
            "{{\"callee\":\"{s}\",\"url_path\":\"{s}\",\"method\":\"{s}\"}}",
            .{ if (call.full_callee_name.len > 0) call.full_callee_name else call.callee_name, route_arg, method_or_broker },
        ) catch return PipelineError.OutOfMemory
    else
        std.fmt.allocPrint(
            gb.allocator,
            "{{\"callee\":\"{s}\",\"url_path\":\"{s}\",\"broker\":\"{s}\"}}",
            .{ if (call.full_callee_name.len > 0) call.full_callee_name else call.callee_name, route_arg, method_or_broker },
        ) catch return PipelineError.OutOfMemory;
    defer gb.allocator.free(call_props);

    try insertResolvedEdgeWithProperties(gb, call.caller_id, route_id, edge_type, call_props);
    return true;
}

fn isServiceRouteArg(edge_type: []const u8, arg: []const u8) bool {
    if (arg.len == 0) return false;
    if (std.mem.eql(u8, edge_type, "ASYNC_CALLS"))
        return arg[0] == '/' or std.mem.indexOf(u8, arg, "://") != null or arg.len > 2;
    return arg[0] == '/' or std.mem.indexOf(u8, arg, "://") != null;
}

fn serviceRouteArg(edge_type: []const u8, call: extractor.UnresolvedCall) ?[]const u8 {
    if (isServiceRouteArg(edge_type, call.first_string_arg)) return call.first_string_arg;
    if (isServiceRouteArg(edge_type, call.second_string_arg)) return call.second_string_arg;
    return null;
}

fn httpMethodLiteral(arg: []const u8) ?[]const u8 {
    if (std.ascii.eqlIgnoreCase(arg, "GET")) return "GET";
    if (std.ascii.eqlIgnoreCase(arg, "POST")) return "POST";
    if (std.ascii.eqlIgnoreCase(arg, "PUT")) return "PUT";
    if (std.ascii.eqlIgnoreCase(arg, "DELETE")) return "DELETE";
    if (std.ascii.eqlIgnoreCase(arg, "PATCH")) return "PATCH";
    if (std.ascii.eqlIgnoreCase(arg, "HEAD")) return "HEAD";
    if (std.ascii.eqlIgnoreCase(arg, "OPTIONS")) return "OPTIONS";
    return null;
}

fn isPathRouteArg(arg: []const u8) bool {
    if (arg.len < 4 or arg[0] != '/') return false;
    return std.mem.indexOfScalarPos(u8, arg, 1, '/') != null;
}

fn insertResolvedEdge(
    gb: *GraphBuffer,
    source_id: i64,
    target_id: i64,
    edge_type: []const u8,
) PipelineError!void {
    _ = gb.insertEdge(source_id, target_id, edge_type) catch |err| switch (err) {
        GraphBufferError.DuplicateEdge => 0,
        GraphBufferError.OutOfMemory => return PipelineError.OutOfMemory,
    };
}

fn insertResolvedEdgeWithProperties(
    gb: *GraphBuffer,
    source_id: i64,
    target_id: i64,
    edge_type: []const u8,
    properties_json: []const u8,
) PipelineError!void {
    _ = gb.insertEdgeWithProperties(source_id, target_id, edge_type, properties_json) catch |err| switch (err) {
        GraphBufferError.DuplicateEdge => 0,
        GraphBufferError.OutOfMemory => return PipelineError.OutOfMemory,
    };
}

test "route registration emits Route and HANDLES edges" {
    const allocator = std.testing.allocator;

    var gb = GraphBuffer.init(allocator, "routes");
    defer gb.deinit();

    var reg = Registry.init(allocator);
    defer reg.deinit();

    const module_id = try gb.upsertNode("Module", "server.js", "routes:module:server.js:javascript", "server.js", 1, 1);
    const handler_qn = "routes:server.js:javascript:symbol:javascript:listUsers";
    const handler_id = try gb.upsertNode("Function", "listUsers", handler_qn, "server.js", 3, 5);
    try reg.add("listUsers", handler_qn, "Function", "server.js");

    const caller = gb.findNodeById(module_id) orelse return error.TestUnexpectedResult;
    try emitRouteRegistration(&gb, &reg, .{
        .caller_id = module_id,
        .callee_name = "get",
        .full_callee_name = "app.get",
        .file_path = "server.js",
        .route_path = "/users",
        .route_handler_ref = "listUsers",
        .route_method = "GET",
    }, caller);

    const route = gb.findNodeByQualifiedName("__route__GET__/users") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("Route", route.label);

    try std.testing.expect(hasEdge(&gb, module_id, route.id, "CALLS"));
    try std.testing.expect(hasEdge(&gb, handler_id, route.id, "HANDLES"));
}

test "service route call emits HTTP_CALLS to concrete Route" {
    const allocator = std.testing.allocator;

    var gb = GraphBuffer.init(allocator, "routes");
    defer gb.deinit();

    const caller_id = try gb.upsertNode("Function", "fetchUsers", "routes:client.js:fetchUsers", "client.js", 1, 3);
    const emitted = try emitServiceRouteCall(&gb, .{
        .caller_id = caller_id,
        .callee_name = "get",
        .full_callee_name = "requests.get",
        .file_path = "client.py",
        .first_string_arg = "/api/users",
    }, "HTTP_CALLS", "requests.get");

    try std.testing.expect(emitted);
    const route = gb.findNodeByQualifiedName("__route__GET__/api/users") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("Route", route.label);
    try std.testing.expect(hasEdge(&gb, caller_id, route.id, "HTTP_CALLS"));
}

test "generic request call emits HTTP_CALLS using second string arg and explicit method" {
    const allocator = std.testing.allocator;

    var gb = GraphBuffer.init(allocator, "routes");
    defer gb.deinit();

    const caller_id = try gb.upsertNode("Function", "fetchOrders", "routes:client.py:fetchOrders", "client.py", 1, 3);
    const emitted = try emitServiceRouteCall(&gb, .{
        .caller_id = caller_id,
        .callee_name = "request",
        .full_callee_name = "requests.request",
        .file_path = "client.py",
        .first_string_arg = "GET",
        .second_string_arg = "/api/orders",
    }, "HTTP_CALLS", "requests.request");

    try std.testing.expect(emitted);
    const route = gb.findNodeByQualifiedName("__route__GET__/api/orders") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("Route", route.label);
    try std.testing.expect(hasEdge(&gb, caller_id, route.id, "HTTP_CALLS"));
}

test "async service route call emits ASYNC_CALLS to broker topic Route" {
    const allocator = std.testing.allocator;

    var gb = GraphBuffer.init(allocator, "async");
    defer gb.deinit();

    const caller_id = try gb.upsertNode("Function", "enqueue_users", "async:worker.py:enqueue_users", "worker.py", 1, 3);
    const emitted = try emitServiceRouteCall(&gb, .{
        .caller_id = caller_id,
        .callee_name = "delay",
        .full_callee_name = "celery.delay",
        .file_path = "worker.py",
        .first_string_arg = "users.refresh",
    }, "ASYNC_CALLS", "async:celery.py:delay");

    try std.testing.expect(emitted);
    const route = gb.findNodeByQualifiedName("__route__celery__users.refresh") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("Route", route.label);
    try std.testing.expect(hasEdge(&gb, caller_id, route.id, "ASYNC_CALLS"));
}

test "argument URL call emits ANY HTTP_CALLS route edge" {
    const allocator = std.testing.allocator;

    var gb = GraphBuffer.init(allocator, "routes");
    defer gb.deinit();

    const caller_id = try gb.upsertNode("Function", "fetch_users", "routes:app.py:fetch_users", "app.py", 1, 3);
    const emitted = try emitArgUrlRouteCall(&gb, .{
        .caller_id = caller_id,
        .callee_name = "send",
        .full_callee_name = "send",
        .file_path = "app.py",
        .first_string_arg = "/api/users",
    });

    try std.testing.expect(emitted);
    const route = gb.findNodeByQualifiedName("__route__ANY__/api/users") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("Route", route.label);
    try std.testing.expect(hasEdge(&gb, caller_id, route.id, "HTTP_CALLS"));
}

test "route registration suppresses duplicate Route and HANDLES edges" {
    const allocator = std.testing.allocator;

    var gb = GraphBuffer.init(allocator, "routes");
    defer gb.deinit();

    var reg = Registry.init(allocator);
    defer reg.deinit();

    const module_id = try gb.upsertNode("Module", "server.js", "routes:module:server.js:javascript", "server.js", 1, 1);
    const handler_qn = "routes:server.js:javascript:symbol:javascript:listUsers";
    const handler_id = try gb.upsertNode("Function", "listUsers", handler_qn, "server.js", 3, 5);
    try reg.add("listUsers", handler_qn, "Function", "server.js");

    const caller = gb.findNodeById(module_id) orelse return error.TestUnexpectedResult;
    const unresolved: extractor.UnresolvedCall = .{
        .caller_id = module_id,
        .callee_name = "get",
        .full_callee_name = "app.get",
        .file_path = "server.js",
        .route_path = "/users",
        .route_handler_ref = "listUsers",
        .route_method = "GET",
    };

    try emitRouteRegistration(&gb, &reg, unresolved, caller);
    try emitRouteRegistration(&gb, &reg, unresolved, caller);

    const route = gb.findNodeByQualifiedName("__route__GET__/users") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 1), countNodesByQualifiedName(&gb, "__route__GET__/users"));
    try std.testing.expectEqual(@as(usize, 1), countEdges(&gb, module_id, route.id, "CALLS"));
    try std.testing.expectEqual(@as(usize, 1), countEdges(&gb, handler_id, route.id, "HANDLES"));
}

fn hasEdge(gb: *const GraphBuffer, source_id: i64, target_id: i64, edge_type: []const u8) bool {
    for (gb.edgeItems()) |edge| {
        if (edge.source_id == source_id and edge.target_id == target_id and std.mem.eql(u8, edge.edge_type, edge_type)) return true;
    }
    return false;
}

fn countEdges(gb: *const GraphBuffer, source_id: i64, target_id: i64, edge_type: []const u8) usize {
    var count: usize = 0;
    for (gb.edgeItems()) |edge| {
        if (edge.source_id == source_id and edge.target_id == target_id and std.mem.eql(u8, edge.edge_type, edge_type)) {
            count += 1;
        }
    }
    return count;
}

fn countNodesByQualifiedName(gb: *const GraphBuffer, qualified_name: []const u8) usize {
    var count: usize = 0;
    for (gb.nodes()) |node| {
        if (std.mem.eql(u8, node.qualified_name, qualified_name)) {
            count += 1;
        }
    }
    return count;
}

test "pipeline run handles simple extraction pipeline" {
    const allocator = std.testing.allocator;

    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(
        allocator,
        "/tmp/cbm-pipeline-simple-{x}",
        .{project_id},
    );
    defer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    var s = try store.Store.openMemory(allocator);
    defer s.deinit();

    var p = Pipeline.init(allocator, project_dir, .full);
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

test "pipeline prefers hybrid sidecar call targets over ambiguous registry matches" {
    const allocator = std.testing.allocator;
    const project_dir = "testdata/interop/hybrid-resolution/go-sidecar";
    const project_name = std.fs.path.basename(project_dir);

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();

    var pipeline = Pipeline.init(allocator, project_dir, .full);
    defer pipeline.deinit();
    try pipeline.run(&db);

    const run_id = try findSingleNodeByNameInFile(&db, project_name, "Function", "run", "main.go");

    const call_edges = try db.findEdgesBySource(project_name, run_id, "CALLS");
    defer db.freeEdges(call_edges);
    try std.testing.expectEqual(@as(usize, 1), call_edges.len);
    const target = (try db.findNodeById(project_name, call_edges[0].target_id)).?;
    defer db.freeNode(target);
    try std.testing.expect(std.mem.indexOf(u8, target.qualified_name, "Primary.Handle") != null);
    try std.testing.expect(std.mem.indexOf(u8, call_edges[0].properties_json, "\"strategy\":\"hybrid_sidecar\"") != null);
}

test "pipeline falls back cleanly when hybrid sidecar is absent" {
    const allocator = std.testing.allocator;
    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(
        allocator,
        "/tmp/cbm-hybrid-fallback-{x}",
        .{project_id},
    );
    defer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    {
        var dir = try std.fs.cwd().openDir(project_dir, .{});
        defer dir.close();

        var main = try dir.createFile("main.go", .{});
        defer main.close();
        try main.writeAll(
            \\package main
            \\
            \\func run(selected Primary) {
            \\    selected.Handle()
            \\}
            \\
        );

        var workers = try dir.createFile("workers.go", .{});
        defer workers.close();
        try workers.writeAll(
            \\package main
            \\
            \\type Secondary struct{}
            \\
            \\func (Secondary) Handle() {}
            \\
            \\type Primary struct{}
            \\
            \\func (Primary) Handle() {}
            \\
        );
    }

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();

    var pipeline = Pipeline.init(allocator, project_dir, .full);
    defer pipeline.deinit();
    try pipeline.run(&db);

    const project_name = std.fs.path.basename(project_dir);
    const run_id = try findSingleNodeByNameInFile(&db, project_name, "Function", "run", "main.go");

    const call_edges = try db.findEdgesBySource(project_name, run_id, "CALLS");
    defer db.freeEdges(call_edges);
    try std.testing.expectEqual(@as(usize, 1), call_edges.len);
    try std.testing.expectEqualStrings("{}", call_edges[0].properties_json);
}

test "pipeline preserves self call edges" {
    const allocator = std.testing.allocator;

    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(
        allocator,
        "/tmp/cbm-pipeline-self-call-{x}",
        .{project_id},
    );
    defer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    {
        var dir = try std.fs.cwd().openDir(project_dir, .{});
        defer dir.close();

        var app = try dir.createFile("app.py", .{});
        defer app.close();
        try app.writeAll(
            \\def loop():
            \\    return loop()
            \\
        );
    }

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();

    var pipeline = Pipeline.init(allocator, project_dir, .full);
    defer pipeline.deinit();
    try pipeline.run(&db);

    const project_name = std.fs.path.basename(project_dir);
    const loop_id = try findSingleNodeByNameInFile(&db, project_name, "Function", "loop", "app.py");
    const calls = try db.findEdgesBySource(project_name, loop_id, "CALLS");
    defer db.freeEdges(calls);
    try std.testing.expectEqual(@as(usize, 1), calls.len);
    try std.testing.expectEqual(loop_id, calls[0].target_id);
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

    const python_parent = try findSingleNodeByNameInFile(&db, project_name, "Class", "Parent", "python/main.py");
    const python_module = try findSingleNodeByNameInFile(&db, project_name, "Module", "python/main.py", "python/main.py");
    const python_main = try findSingleNodeByNameInFile(&db, project_name, "Function", "main", "python/main.py");
    const py_helper = try findSingleNodeByNameInFile(&db, project_name, "Function", "helper", "python/main.py");
    const py_calls = try db.findEdgesBySource(project_name, python_main, "CALLS");
    defer db.freeEdges(py_calls);
    try std.testing.expectEqual(@as(usize, 1), py_calls.len);
    try std.testing.expectEqual(py_helper, py_calls[0].target_id);
    const py_usages = try db.findEdgesBySource(project_name, python_module, "USAGE");
    defer db.freeEdges(py_usages);
    try std.testing.expect(edgeTargetsContain(py_usages, python_parent));

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
    const zig_main = try findSingleNodeByNameInFile(&db, project_name, "Function", "main", "zig/main.zig");
    const zig_calls = try db.findEdgesBySource(project_name, zig_main, "CALLS");
    defer db.freeEdges(zig_calls);
    try std.testing.expectEqual(@as(usize, 1), zig_calls.len);

    const python_file = try findSingleNodeByNameInFile(&db, project_name, "File", "main.py", "python/main.py");
    const py_defines = try db.findEdgesBySource(project_name, python_file, "DEFINES");
    defer db.freeEdges(py_defines);
    try std.testing.expect(py_defines.len > 0);
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

test "pipeline keeps only shared decorator semantic edges" {
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
    const py_inherits = try db.findEdgesBySource(project_name, worker_py_id, "INHERITS");
    defer db.freeEdges(py_inherits);
    try std.testing.expectEqual(@as(usize, 0), py_inherits.len);

    const worker_ts_id = try findSingleNodeByNameInFile(&db, project_name, "Class", "Worker", "types.ts");
    const worker_port_id = try findSingleNodeByNameInFile(&db, project_name, "Interface", "WorkerPort", "types.ts");

    const ts_implements = try db.findEdgesBySource(project_name, worker_ts_id, "IMPLEMENTS");
    defer db.freeEdges(ts_implements);
    try std.testing.expectEqual(@as(usize, 0), ts_implements.len);

    const worker_port_inherits = try db.findEdgesBySource(project_name, worker_port_id, "INHERITS");
    defer db.freeEdges(worker_port_inherits);
    try std.testing.expectEqual(@as(usize, 0), worker_port_inherits.len);
}

test "pipeline derives test tagging edges for python fixtures" {
    const allocator = std.testing.allocator;

    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(
        allocator,
        "/tmp/cbm-pipeline-test-tagging-{x}",
        .{project_id},
    );
    defer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    {
        var dir = try std.fs.cwd().openDir(project_dir, .{});
        defer dir.close();

        var widget = try dir.createFile("widget.py", .{});
        defer widget.close();
        try widget.writeAll(
            \\def render_widget():
            \\    return "widget"
            \\
        );

        var test_widget = try dir.createFile("test_widget.py", .{});
        defer test_widget.close();
        try test_widget.writeAll(
            \\from widget import render_widget
            \\
            \\def helper_in_test():
            \\    return "ignored"
            \\
            \\def test_widget_renders():
            \\    return render_widget()
            \\
        );
    }

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();

    var pipeline = Pipeline.init(allocator, project_dir, .full);
    defer pipeline.deinit();
    try pipeline.run(&db);

    const project_name = std.fs.path.basename(project_dir);
    const render_id = try findSingleNodeByNameInFile(&db, project_name, "Function", "render_widget", "widget.py");
    const test_id = try findSingleNodeByNameInFile(&db, project_name, "Function", "test_widget_renders", "test_widget.py");
    const helper_in_test_id = try findSingleNodeByNameInFile(&db, project_name, "Function", "helper_in_test", "test_widget.py");
    const test_file_id = try findExactFileNodeByPath(&db, project_name, "test_widget.py");
    const prod_file_id = try findExactFileNodeByPath(&db, project_name, "widget.py");

    const tests_edges = try db.findEdgesBySource(project_name, test_id, "TESTS");
    defer db.freeEdges(tests_edges);
    try std.testing.expectEqual(@as(usize, 1), tests_edges.len);
    try std.testing.expectEqual(render_id, tests_edges[0].target_id);

    const helper_edges = try db.findEdgesBySource(project_name, helper_in_test_id, "TESTS");
    defer db.freeEdges(helper_edges);
    try std.testing.expectEqual(@as(usize, 0), helper_edges.len);

    const tests_file_edges = try db.findEdgesBySource(project_name, test_file_id, "TESTS_FILE");
    defer db.freeEdges(tests_file_edges);
    try std.testing.expectEqual(@as(usize, 1), tests_file_edges.len);
    try std.testing.expectEqual(prod_file_id, tests_file_edges[0].target_id);

    const test_file_nodes = try db.searchNodes(.{
        .project = project_name,
        .label_pattern = "File",
        .name_pattern = "test_widget.py",
        .limit = 5,
    });
    defer db.freeNodes(test_file_nodes);
    try std.testing.expectEqual(@as(usize, 1), test_file_nodes.len);
    try std.testing.expect(std.mem.indexOf(u8, test_file_nodes[0].properties_json, "\"is_test\":true") != null);
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

    const py_module_id = try findSingleNodeByNameInFile(&db, project_name, "Module", "python_semantics.py", "python_semantics.py");
    const trace_id = try findSingleNodeByNameInFile(&db, project_name, "Function", "trace", "python_semantics.py");
    const base_id = try findSingleNodeByNameInFile(&db, project_name, "Class", "Base", "python_semantics.py");
    const py_usages = try db.findEdgesBySource(project_name, py_module_id, "USAGE");
    defer db.freeEdges(py_usages);
    try std.testing.expect(edgeTargetsContain(py_usages, trace_id));
    try std.testing.expect(edgeTargetsContain(py_usages, base_id));

    const js_module_id = try findSingleNodeByNameInFile(&db, project_name, "Module", "logger.js", "logger.js");
    const js_base_id = try findSingleNodeByNameInFile(&db, project_name, "Class", "BaseLogger", "logger.js");
    const js_usages = try db.findEdgesBySource(project_name, js_module_id, "USAGE");
    defer db.freeEdges(js_usages);
    try std.testing.expect(edgeTargetsContain(js_usages, js_base_id));

    const rust_module_id = try findSingleNodeByNameInFile(&db, project_name, "Module", "src/lib.rs", "src/lib.rs");
    const rust_worker_id = try findSingleNodeByNameInFile(&db, project_name, "Class", "Worker", "src/lib.rs");
    const rust_config_id = try findSingleNodeByNameInFile(&db, project_name, "Class", "Config", "src/lib.rs");
    const rust_runner_id = try findSingleNodeByNameInFile(&db, project_name, "Interface", "Runner", "src/lib.rs");
    const rust_usages = try db.findEdgesBySource(project_name, rust_module_id, "USAGE");
    defer db.freeEdges(rust_usages);
    try std.testing.expect(edgeTargetsContain(rust_usages, rust_worker_id));
    try std.testing.expect(edgeTargetsContain(rust_usages, rust_config_id));
    try std.testing.expect(!edgeTargetsContain(rust_usages, rust_runner_id));
}

test "pipeline preserves scoped rust methods and defines-method edges" {
    const allocator = std.testing.allocator;

    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(
        allocator,
        "/tmp/cbm-pipeline-rust-methods-{x}",
        .{project_id},
    );
    defer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    {
        var dir = try std.fs.cwd().openDir(project_dir, .{});
        defer dir.close();

        try dir.makePath("src");

        var cargo = try dir.createFile("Cargo.toml", .{});
        defer cargo.close();
        try cargo.writeAll(
            \\[package]
            \\name = "rust-methods"
            \\version = "0.1.0"
            \\edition = "2021"
            \\
        );

        var rs = try dir.createFile("src/lib.rs", .{});
        defer rs.close();
        try rs.writeAll(
            \\pub trait Runner {
            \\    fn run(&self) -> String;
            \\}
            \\
            \\pub struct Worker;
            \\
            \\impl Runner for Worker {
            \\    fn run(&self) -> String {
            \\        "ok".to_string()
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
    const runner_id = try findSingleNodeByNameInFile(&db, project_name, "Interface", "Runner", "src/lib.rs");
    const worker_id = try findSingleNodeByNameInFile(&db, project_name, "Class", "Worker", "src/lib.rs");

    const run_methods = try db.searchNodes(.{
        .project = project_name,
        .label_pattern = "Method",
        .name_pattern = "run",
        .file_pattern = "src/lib.rs",
        .limit = 10,
    });
    defer db.freeNodes(run_methods);
    try std.testing.expectEqual(@as(usize, 2), run_methods.len);

    const runner_run_id = findNodeIdByQualifiedNameFragment(run_methods, "Runner.run") orelse return error.TestUnexpectedResult;
    const worker_run_id = findNodeIdByQualifiedNameFragment(run_methods, "Worker.run") orelse return error.TestUnexpectedResult;

    const runner_edges = try db.findEdgesBySource(project_name, runner_id, "DEFINES_METHOD");
    defer db.freeEdges(runner_edges);
    try std.testing.expect(edgeTargetsContain(runner_edges, runner_run_id));

    const worker_edges = try db.findEdgesBySource(project_name, worker_id, "DEFINES_METHOD");
    defer db.freeEdges(worker_edges);
    try std.testing.expect(edgeTargetsContain(worker_edges, worker_run_id));
}

test "pipeline creates shared project and folder structure edges" {
    const allocator = std.testing.allocator;

    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(
        allocator,
        "/tmp/cbm-pipeline-structure-{x}",
        .{project_id},
    );
    defer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    {
        var dir = try std.fs.cwd().openDir(project_dir, .{});
        defer dir.close();

        try dir.makePath("src");

        var rs = try dir.createFile("src/lib.rs", .{});
        defer rs.close();
        try rs.writeAll(
            \\pub fn run() {}
            \\
        );
    }

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();

    var pipeline = Pipeline.init(allocator, project_dir, .full);
    defer pipeline.deinit();
    try pipeline.run(&db);

    const project_name = std.fs.path.basename(project_dir);
    const project_nodes = try db.searchNodes(.{
        .project = project_name,
        .label_pattern = "Project",
        .name_pattern = project_name,
        .limit = 4,
    });
    defer db.freeNodes(project_nodes);
    try std.testing.expectEqual(@as(usize, 1), project_nodes.len);

    const folder_nodes = try db.searchNodes(.{
        .project = project_name,
        .label_pattern = "Folder",
        .name_pattern = "src",
        .limit = 4,
    });
    defer db.freeNodes(folder_nodes);
    try std.testing.expectEqual(@as(usize, 1), folder_nodes.len);

    const file_id = try findSingleNodeByNameInFile(&db, project_name, "File", "lib.rs", "src/lib.rs");

    const project_contains = try db.findEdgesBySource(project_name, project_nodes[0].id, "CONTAINS_FOLDER");
    defer db.freeEdges(project_contains);
    try std.testing.expect(edgeTargetsContain(project_contains, folder_nodes[0].id));

    const folder_contains = try db.findEdgesBySource(project_name, folder_nodes[0].id, "CONTAINS_FILE");
    defer db.freeEdges(folder_contains);
    try std.testing.expect(edgeTargetsContain(folder_contains, file_id));
}

test "pipeline indexes python module variables without promoting local assignments" {
    const allocator = std.testing.allocator;

    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(
        allocator,
        "/tmp/cbm-pipeline-python-vars-{x}",
        .{project_id},
    );
    defer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    {
        var dir = try std.fs.cwd().openDir(project_dir, .{});
        defer dir.close();

        var py = try dir.createFile("main.py", .{});
        defer py.close();
        try py.writeAll(
            \\default_mode = "batch"
            \\if __name__ == "__main__":
            \\    result = bootstrap()
            \\
            \\def bootstrap():
            \\    local_mode = default_mode
            \\    return local_mode
            \\
        );
    }

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();

    var pipeline = Pipeline.init(allocator, project_dir, .full);
    defer pipeline.deinit();
    try pipeline.run(&db);

    const project_name = std.fs.path.basename(project_dir);
    _ = try findSingleNodeByNameInFile(&db, project_name, "Variable", "default_mode", "main.py");

    const local_nodes = try db.searchNodes(.{
        .project = project_name,
        .name_pattern = "local_mode",
        .label_pattern = "Variable",
        .limit = 10,
    });
    defer db.freeNodes(local_nodes);
    try std.testing.expectEqual(@as(usize, 0), local_nodes.len);

    const guarded_nodes = try db.searchNodes(.{
        .project = project_name,
        .name_pattern = "result",
        .label_pattern = "Variable",
        .limit = 10,
    });
    defer db.freeNodes(guarded_nodes);
    try std.testing.expectEqual(@as(usize, 0), guarded_nodes.len);
}

test "pipeline keeps python import edges file-scoped while preserving alias resolution" {
    const allocator = std.testing.allocator;

    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(
        allocator,
        "/tmp/cbm-pipeline-python-imports-{x}",
        .{project_id},
    );
    defer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    {
        var dir = try std.fs.cwd().openDir(project_dir, .{});
        defer dir.close();

        var main_py = try dir.createFile("main.py", .{});
        defer main_py.close();
        try main_py.writeAll(
            \\from models import Worker as ActiveWorker
            \\from models import trace
            \\
            \\@trace
            \\def bootstrap() -> ActiveWorker:
            \\    worker = ActiveWorker("primary")
            \\    worker.run()
            \\    return worker
            \\
        );

        var models_py = try dir.createFile("models.py", .{});
        defer models_py.close();
        try models_py.writeAll(
            \\class Worker:
            \\    def run(self):
            \\        return None
            \\
            \\def trace(fn):
            \\    return fn
            \\
        );
    }

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();

    var pipeline = Pipeline.init(allocator, project_dir, .full);
    defer pipeline.deinit();
    try pipeline.run(&db);

    const project_name = std.fs.path.basename(project_dir);
    const main_file_id = try findSingleNodeByNameInFile(&db, project_name, "File", "main.py", "main.py");
    const main_module_id = try findSingleNodeByNameInFile(&db, project_name, "Module", "main.py", "main.py");
    const models_module_id = try findSingleNodeByNameInFile(&db, project_name, "Module", "models.py", "models.py");
    const trace_id = try findSingleNodeByNameInFile(&db, project_name, "Function", "trace", "models.py");
    const bootstrap_id = try findSingleNodeByNameInFile(&db, project_name, "Function", "bootstrap", "main.py");
    const run_id = try findSingleNodeByNameInFile(&db, project_name, "Method", "run", "models.py");

    const import_edges = try db.findEdgesBySource(project_name, main_file_id, "IMPORTS");
    defer db.freeEdges(import_edges);
    try std.testing.expectEqual(@as(usize, 1), import_edges.len);
    try std.testing.expectEqual(models_module_id, import_edges[0].target_id);

    const call_edges = try db.findEdgesBySource(project_name, bootstrap_id, "CALLS");
    defer db.freeEdges(call_edges);
    try std.testing.expect(edgeTargetsContain(call_edges, run_id));

    const usage_edges = try db.findEdgesBySource(project_name, main_module_id, "USAGE");
    defer db.freeEdges(usage_edges);
    try std.testing.expect(edgeTargetsContain(usage_edges, trace_id));
}

test "pipeline links matching config keys to code symbols" {
    const allocator = std.testing.allocator;

    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(
        allocator,
        "/tmp/cbm-pipeline-configlink-{x}",
        .{project_id},
    );
    defer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    {
        var dir = try std.fs.cwd().openDir(project_dir, .{});
        defer dir.close();

        var cfg = try dir.createFile("settings.yaml", .{});
        defer cfg.close();
        try cfg.writeAll(
            \\mode: batch
            \\max_connections: 10
            \\
        );

        var py = try dir.createFile("main.py", .{});
        defer py.close();
        try py.writeAll(
            \\def get_max_connections():
            \\    return 10
            \\
        );
    }

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();

    var pipeline = Pipeline.init(allocator, project_dir, .full);
    defer pipeline.deinit();
    try pipeline.run(&db);

    const project_name = std.fs.path.basename(project_dir);
    const getter_id = try findSingleNodeByNameInFile(&db, project_name, "Function", "get_max_connections", "main.py");
    const config_id = try findSingleNodeByNameInFile(&db, project_name, "Variable", "max_connections", "settings.yaml");
    const configures = try db.findEdgesBySource(project_name, getter_id, "CONFIGURES");
    defer db.freeEdges(configures);
    try std.testing.expect(edgeTargetsContain(configures, config_id));
}

test "pipeline links env-style config keys to matching code symbols" {
    const allocator = std.testing.allocator;

    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(
        allocator,
        "/tmp/cbm-pipeline-configlink-env-{x}",
        .{project_id},
    );
    defer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    {
        var dir = try std.fs.cwd().openDir(project_dir, .{});
        defer dir.close();

        var cfg = try dir.createFile("config.toml", .{});
        defer cfg.close();
        try cfg.writeAll(
            \\DATABASE_URL = "postgresql://localhost/db"
            \\
        );

        var py = try dir.createFile("main.py", .{});
        defer py.close();
        try py.writeAll(
            \\import os
            \\
            \\def load_database_url():
            \\    return os.getenv("DATABASE_URL")
            \\
        );
    }

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();

    var pipeline = Pipeline.init(allocator, project_dir, .full);
    defer pipeline.deinit();
    try pipeline.run(&db);

    const project_name = std.fs.path.basename(project_dir);
    const getter_id = try findSingleNodeByNameInFile(&db, project_name, "Function", "load_database_url", "main.py");
    const config_id = try findSingleNodeByNameInFile(&db, project_name, "Variable", "DATABASE_URL", "config.toml");
    const configures = try db.findEdgesBySource(project_name, getter_id, "CONFIGURES");
    defer db.freeEdges(configures);
    try std.testing.expect(edgeTargetsContain(configures, config_id));
}

test "normalizeConfigName keeps env-style uppercase runs intact" {
    const allocator = std.testing.allocator;

    const env_style = normalizeConfigName(allocator, "DATABASE_URL", true) orelse return error.TestUnexpectedResult;
    defer allocator.free(env_style);
    try std.testing.expectEqualStrings("database url", env_style);

    const snake_case = normalizeConfigName(allocator, "database_url", true) orelse return error.TestUnexpectedResult;
    defer allocator.free(snake_case);
    try std.testing.expectEqualStrings("database url", snake_case);

    try std.testing.expect(normalizeConfigName(allocator, "PORT", true) == null);
}

test "pipeline links manifest dependencies to resolved imports once" {
    const allocator = std.testing.allocator;

    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(
        allocator,
        "/tmp/cbm-pipeline-dep-import-{x}",
        .{project_id},
    );
    defer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    {
        var dir = try std.fs.cwd().openDir(project_dir, .{});
        defer dir.close();

        try dir.makePath("src");

        var cargo = try dir.createFile("Cargo.toml", .{});
        defer cargo.close();
        try cargo.writeAll(
            \\[package]
            \\name = "dep-import"
            \\version = "0.1.0"
            \\
            \\[dependencies]
            \\serde = "1"
            \\
        );

        var lib = try dir.createFile("src/lib.rs", .{});
        defer lib.close();
        try lib.writeAll(
            \\use serde::Serialize;
            \\use serde::Serialize;
            \\
            \\pub fn encode(value: Serialize) -> Serialize {
            \\    value
            \\}
            \\
        );

        var serde = try dir.createFile("src/serde.rs", .{});
        defer serde.close();
        try serde.writeAll(
            \\pub struct Serialize;
            \\
        );
    }

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();

    var pipeline = Pipeline.init(allocator, project_dir, .full);
    defer pipeline.deinit();
    try pipeline.run(&db);

    const project_name = std.fs.path.basename(project_dir);
    const lib_id = try findExactFileNodeByPath(&db, project_name, "src/lib.rs");
    const serde_dep_id = try findSingleNodeByNameInFile(&db, project_name, "Variable", "serde", "Cargo.toml");
    const configures = try db.findEdgesBySource(project_name, lib_id, "CONFIGURES");
    defer db.freeEdges(configures);

    var matches: usize = 0;
    for (configures) |edge| {
        if (edge.target_id == serde_dep_id) matches += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), matches);
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

fn findExactFileNodeByPath(db: *store.Store, project_name: []const u8, file_path: []const u8) !i64 {
    const nodes = try db.searchNodes(.{
        .project = project_name,
        .label_pattern = "File",
        .file_pattern = file_path,
        .limit = 25,
    });
    defer db.freeNodes(nodes);
    for (nodes) |node| {
        if (std.mem.eql(u8, node.label, "File") and
            std.mem.eql(u8, node.name, std.fs.path.basename(file_path)) and
            std.mem.eql(u8, node.file_path, file_path))
        {
            return node.id;
        }
    }
    return error.TestUnexpectedResult;
}

fn edgeTargetsContain(edges: []const store.Edge, target_id: i64) bool {
    for (edges) |edge| {
        if (edge.target_id == target_id) return true;
    }
    return false;
}

fn findNodeIdByQualifiedNameFragment(nodes: []const store.Node, fragment: []const u8) ?i64 {
    for (nodes) |node| {
        if (std.mem.indexOf(u8, node.qualified_name, fragment) != null) return node.id;
    }
    return null;
}

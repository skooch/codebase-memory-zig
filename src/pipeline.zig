// pipeline — Indexing pipeline orchestrator.
//
// Orchestrates discovery, extraction, symbol registry, resolution passes, and
// persistence to the store.

const std = @import("std");
const discover = @import("discover.zig");
const GraphBuffer = @import("graph_buffer.zig").GraphBuffer;
const extractor = @import("extractor.zig");
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
                error.SqlError => return PipelineError.SqlError,
                error.OpenFailed => return PipelineError.OpenFailed,
                error.NotFound => return PipelineError.NotFound,
                else => return PipelineError.DiscoveryFailed,
            };
            if (used_incremental) {
                return;
            }
        }

        try db.deleteProject(self.project_name);
        try db.upsertProject(self.project_name, self.repo_path);

        var gb = GraphBuffer.init(self.allocator, self.project_name);
        defer gb.deinit();

        var reg = Registry.init(self.allocator);
        defer reg.deinit();

        var extractions = std.ArrayList(extractor.FileExtraction).empty;
        defer {
            for (extractions.items) |extraction| {
                extractor.freeFileExtraction(self.allocator, extraction);
            }
            extractions.deinit(self.allocator);
        }

        for (discovered_files) |file| {
            if (self.cancelled.load(.acquire)) return PipelineError.Cancelled;

            const extraction = extractFile(self.allocator, self.project_name, file, &gb) catch |err| {
                std.log.warn("extractor failed for {s}: {}", .{ file.rel_path, err });
                continue;
            };

            for (extraction.symbols) |sym| {
                try reg.add(
                    sym.name,
                    sym.qualified_name,
                    sym.label,
                    sym.file_path,
                );
            }
            for (extraction.unresolved_imports) |imp| {
                const alias = if (imp.binding_alias.len > 0)
                    imp.binding_alias
                else
                    normalizeImportAlias(imp.import_name);
                if (alias.len == 0) continue;
                try reg.addImportBinding(imp.importer_id, alias, imp.import_name, imp.file_path);
            }

            const unresolved_import_count = extraction.unresolved_imports.len;
            const unresolved_call_count = extraction.unresolved_calls.len;
            const unresolved_usage_count = extraction.unresolved_usages.len;
            const semantic_hint_count = extraction.semantic_hints.len;
            std.log.debug(
                "file {s} extracted {d} symbols, {d} imports, {d} calls, {d} usages, {d} semantic hints",
                .{
                    extraction.file_path,
                    extraction.symbols.len,
                    unresolved_import_count,
                    unresolved_call_count,
                    unresolved_usage_count,
                    semantic_hint_count,
                },
            );

            try extractions.append(self.allocator, extraction);
        }

        for (extractions.items) |extraction| {
            if (self.cancelled.load(.acquire)) return PipelineError.Cancelled;
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
                if (resolveSemanticTarget(&reg, hint, child_node.file_path)) |res| {
                    if (gb.findNodeByQualifiedName(res.qualified_name)) |target| {
                        _ = gb.insertEdge(hint.child_id, target.id, hint.relation) catch {};
                    }
                }
            }
        }

        try gb.dumpToStore(db);
        try persistFileHashes(db, self.project_name, discovered_files);
        std.log.info(
            "pipeline graph buffer: {} nodes, {} edges",
            .{ gb.nodeCount(), gb.edgeCount() },
        );
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

        var extractions = std.ArrayList(extractor.FileExtraction).empty;
        defer {
            for (extractions.items) |extraction| {
                extractor.freeFileExtraction(self.allocator, extraction);
            }
            extractions.deinit(self.allocator);
        }

        for (classification.changed_files) |file| {
            if (self.cancelled.load(.acquire)) return PipelineError.Cancelled;

            const extraction = extractFile(self.allocator, self.project_name, file, &gb) catch |err| {
                std.log.warn("incremental extractor failed for {s}: {}", .{ file.rel_path, err });
                continue;
            };

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
            try extractions.append(self.allocator, extraction);
        }

        try resolveExtractions(&gb, &reg, extractions.items, &self.cancelled);

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

fn seedRegistryFromGraphBuffer(gb: *const GraphBuffer, reg: *Registry) !void {
    for (gb.nodes()) |node| {
        try reg.add(node.name, node.qualified_name, node.label, node.file_path);
    }
}

fn resolveExtractions(
    gb: *GraphBuffer,
    reg: *Registry,
    extractions: []const extractor.FileExtraction,
    cancelled: *const std.atomic.Value(bool),
) !void {
    for (extractions) |extraction| {
        if (cancelled.load(.acquire)) return PipelineError.Cancelled;

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
    const rust_trait = try findSingleNodeByNameInFile(&db, project_name, "Trait", "Speaker", "rust/lib.rs");
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

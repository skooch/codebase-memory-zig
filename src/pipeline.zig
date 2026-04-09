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
                const alias = normalizeImportAlias(imp.import_name);
                if (alias.len == 0) continue;
                try reg.addImportBinding(imp.importer_id, alias, imp.import_name);
            }

            const unresolved_import_count = extraction.unresolved_imports.len;
            const unresolved_call_count = extraction.unresolved_calls.len;
            const semantic_hint_count = extraction.semantic_hints.len;
            std.log.debug(
                "file {s} extracted {d} symbols, {d} imports, {d} calls, {d} semantic hints",
                .{
                    extraction.file_path,
                    extraction.symbols.len,
                    unresolved_import_count,
                    unresolved_call_count,
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

            for (extraction.semantic_hints) |hint| {
                const child_node = gb.findNodeById(hint.child_id) orelse continue;
                if (reg.resolve(hint.parent_name, hint.child_id, child_node.file_path, null)) |res| {
                    if (gb.findNodeByQualifiedName(res.qualified_name)) |target| {
                        _ = gb.insertEdge(hint.child_id, target.id, hint.relation) catch {};
                    }
                }
            }
        }

        try gb.dumpToStore(db);
        std.log.info(
            "pipeline graph buffer: {} nodes, {} edges",
            .{ gb.nodeCount(), gb.edgeCount() },
        );
    }

    pub fn cancel(self: *Pipeline) void {
        self.cancelled.store(true, .release);
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
    if (std.mem.lastIndexOfAny(u8, trimmed, "/\\")) |idx| {
        return trimmed[idx + 1 ..];
    }
    if (std.mem.lastIndexOf(u8, trimmed, ".")) |dot| {
        if (dot + 1 < trimmed.len) return trimmed[dot + 1 ..];
    }
    return trimmed;
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

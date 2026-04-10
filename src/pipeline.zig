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
                const alias = if (imp.binding_alias.len > 0)
                    imp.binding_alias
                else
                    normalizeImportAlias(imp.import_name);
                if (alias.len == 0) continue;
                try reg.addImportBinding(imp.importer_id, alias, imp.import_name, imp.file_path);
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

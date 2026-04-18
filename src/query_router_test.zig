// query_router_test.zig — Integration tests for the QueryRouter payload functions.

const std = @import("std");
const store = @import("store.zig");
const pipeline = @import("pipeline.zig");
const query_router = @import("query_router.zig");

const QueryRouter = query_router.QueryRouter;

/// Create a temp directory, write a Python file with a known function,
/// index it with the pipeline, and return the project name (basename of the dir).
/// Caller must free `project_dir` and delete the tree via defer.
fn setupIndexedProject(allocator: std.mem.Allocator, db: *store.Store) ![]const u8 {
    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(
        allocator,
        "/tmp/cbm-qr-test-{x}",
        .{project_id},
    );
    errdefer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);

    {
        var dir = try std.fs.cwd().openDir(project_dir, .{});
        defer dir.close();

        var file = try dir.createFile("calc.py", .{});
        defer file.close();
        try file.writeAll(
            \\def compute_total(items):
            \\    total = 0
            \\    for item in items:
            \\        total += item.price
            \\    return total
            \\
            \\def format_result(value):
            \\    return f"Total: {value}"
            \\
        );
    }

    var p = pipeline.Pipeline.init(allocator, project_dir, .full);
    defer p.deinit();
    try p.run(db);

    return project_dir;
}

fn setupIndexedRouteProject(allocator: std.mem.Allocator, db: *store.Store) ![]const u8 {
    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(
        allocator,
        "/tmp/cbm-qr-route-test-{x}",
        .{project_id},
    );
    errdefer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);

    {
        var dir = try std.fs.cwd().openDir(project_dir, .{});
        defer dir.close();

        var app = try dir.createFile("app.py", .{});
        defer app.close();
        try app.writeAll(
            \\import requests
            \\
            \\class App:
            \\    def get(self, path):
            \\        def wrapper(fn):
            \\            return fn
            \\        return wrapper
            \\
            \\app = App()
            \\
            \\@app.get("/api/users")
            \\def list_users():
            \\    return []
            \\
            \\def fetch_users():
            \\    return requests.get("/api/users")
            \\
        );

        var requests = try dir.createFile("requests.py", .{});
        defer requests.close();
        try requests.writeAll(
            \\def get(path):
            \\    return path
            \\
        );
    }

    var p = pipeline.Pipeline.init(allocator, project_dir, .full);
    defer p.deinit();
    try p.run(db);

    return project_dir;
}

test "searchCodePayload returns matching results" {
    const allocator = std.testing.allocator;

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();

    const project_dir = try setupIndexedProject(allocator, &db);
    defer allocator.free(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    const project_name = std.fs.path.basename(project_dir);

    var router = QueryRouter.init(allocator, &db);
    const payload = try router.searchCodePayload(.{
        .project = project_name,
        .pattern = "compute_total",
    });
    defer allocator.free(payload);

    // The returned JSON must contain the function name and file path.
    try std.testing.expect(std.mem.indexOf(u8, payload, "compute_total") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "calc.py") != null);

    // It must be valid JSON (opening/closing braces, "results" key).
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"results\"") != null);
    try std.testing.expect(payload.len > 0 and payload[0] == '{');
}

test "searchCodePayload only searches indexed project files" {
    const allocator = std.testing.allocator;

    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(
        allocator,
        "/tmp/cbm-qr-scope-test-{x}",
        .{project_id},
    );
    defer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    {
        var dir = try std.fs.cwd().openDir(project_dir, .{});
        defer dir.close();

        var indexed = try dir.createFile("main.py", .{});
        defer indexed.close();
        try indexed.writeAll("def indexed_symbol():\n    return 1\n");

        var extra = try dir.createFile("extra.py", .{});
        defer extra.close();
        try extra.writeAll("def unindexed_scope_hit():\n    return 2\n");
    }

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();
    const project_name = std.fs.path.basename(project_dir);
    try db.upsertProject(project_name, project_dir);
    _ = try db.upsertNode(.{
        .project = project_name,
        .label = "File",
        .name = "main.py",
        .qualified_name = "scope-test:file:main.py",
        .file_path = "main.py",
    });

    var router = QueryRouter.init(allocator, &db);
    const payload = try router.searchCodePayload(.{
        .project = project_name,
        .pattern = "unindexed_scope_hit",
        .mode = .files,
    });
    defer allocator.free(payload);

    try std.testing.expect(std.mem.indexOf(u8, payload, "\"total\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "extra.py") == null);
}

test "getCodeSnippetPayload returns source for known function" {
    const allocator = std.testing.allocator;

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();

    const project_dir = try setupIndexedProject(allocator, &db);
    defer allocator.free(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    const project_name = std.fs.path.basename(project_dir);

    // Look up the qualified_name that the pipeline assigned to compute_total.
    const nodes = try db.searchNodes(.{
        .project = project_name,
        .label_pattern = "Function",
        .name_pattern = "compute_total",
        .limit = 1,
    });
    defer db.freeNodes(nodes);
    try std.testing.expect(nodes.len > 0);

    var router = QueryRouter.init(allocator, &db);
    const payload = try router.getCodeSnippetPayload(.{
        .project = project_name,
        .qualified_name = nodes[0].qualified_name,
    });
    defer allocator.free(payload);

    // The payload must contain the function name and be valid JSON.
    try std.testing.expect(std.mem.indexOf(u8, payload, "compute_total") != null);
    try std.testing.expect(payload.len > 0 and payload[0] == '{');
    // It should include a "source" field with at least part of the function body.
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"source\"") != null);
}

test "getArchitecturePayload returns project structure" {
    const allocator = std.testing.allocator;

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();

    const project_dir = try setupIndexedProject(allocator, &db);
    defer allocator.free(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    const project_name = std.fs.path.basename(project_dir);

    var router = QueryRouter.init(allocator, &db);
    const payload = try router.getArchitecturePayload(.{
        .project = project_name,
    });
    defer allocator.free(payload);

    // Must be valid JSON with expected top-level fields.
    try std.testing.expect(payload.len > 0 and payload[0] == '{');
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"project\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"total_nodes\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"total_edges\"") != null);
    // Default flags include structure (node_labels) and dependencies (edge_types).
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"node_labels\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"edge_types\"") != null);
}

test "getArchitecturePayload includes route summaries" {
    const allocator = std.testing.allocator;

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();

    const project_dir = try setupIndexedRouteProject(allocator, &db);
    defer allocator.free(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    const project_name = std.fs.path.basename(project_dir);

    var router = QueryRouter.init(allocator, &db);
    const payload = try router.getArchitecturePayload(.{
        .project = project_name,
        .include_routes = true,
    });
    defer allocator.free(payload);

    try std.testing.expect(payload.len > 0 and payload[0] == '{');
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"routes\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "/api/users") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "HTTP_CALLS") != null);
}

test "detectChangesPayload handles non-git gracefully" {
    const allocator = std.testing.allocator;

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();

    const project_dir = try setupIndexedProject(allocator, &db);
    defer allocator.free(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    const project_name = std.fs.path.basename(project_dir);

    var router = QueryRouter.init(allocator, &db);
    const payload = try router.detectChangesPayload(.{
        .project = project_name,
    });
    defer allocator.free(payload);

    // The temp dir is not a git repo, so changed_files should be empty,
    // but the function must still return valid JSON without crashing.
    try std.testing.expect(payload.len > 0 and payload[0] == '{');
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"project\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"changed_files\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"changed_count\":0") != null);
}

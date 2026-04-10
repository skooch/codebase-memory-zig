// store_test.zig — Integration tests for the SQLite store.

const std = @import("std");
const store = @import("store.zig");
const pipeline = @import("pipeline.zig");

test "open in-memory store" {
    var s = try store.Store.openMemory(std.testing.allocator);
    defer s.deinit();
    // If we get here, SQLite opened and schema was created successfully.
}

test "open and close multiple times" {
    {
        var s = try store.Store.openMemory(std.testing.allocator);
        defer s.deinit();
    }
    {
        var s = try store.Store.openMemory(std.testing.allocator);
        defer s.deinit();
    }
}

test "store persists parser-backed extraction and call/inherit edges" {
    const allocator = std.testing.allocator;

    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(
        allocator,
        "/tmp/cbm-store-parser-regression-{x}",
        .{project_id},
    );
    defer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    {
        var dir = try std.fs.cwd().openDir(project_dir, .{});
        defer dir.close();

        var file = try dir.createFile("main.py", .{});
        defer file.close();
        try file.writeAll(
            \\class Base:
            \\    pass
            \\
            \\class Child(Base):
            \\    pass
            \\
            \\def helper(x):
            \\    return x
            \\
            \\def main():
            \\    return helper(1)
            \\
        );
    }

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();

    var p = pipeline.Pipeline.init(allocator, project_dir, .full);
    defer p.deinit();
    try p.run(&db);

    const project_name = std.fs.path.basename(project_dir);
    const base_node = findSingleNodeInStore(&db, project_name, "Class", "Base", "main.py") catch |err| {
        std.debug.print("missing Base node in store-backed parse regression\n", .{});
        return err;
    };
    const child_node = try findSingleNodeInStore(&db, project_name, "Class", "Child", "main.py");
    const helper_node = try findSingleNodeInStore(&db, project_name, "Function", "helper", "main.py");
    const main_node = try findSingleNodeInStore(&db, project_name, "Function", "main", "main.py");

    const helper_nodes = try db.searchNodes(.{
        .project = project_name,
        .label_pattern = "Function",
        .name_pattern = "helper",
        .limit = 1,
    });
    defer db.freeNodes(helper_nodes);
    try std.testing.expectEqual(@as(usize, 1), helper_nodes.len);
    try std.testing.expectEqual(@as(i32, 7), helper_nodes[0].start_line);

    const calls = try db.findEdgesBySource(project_name, main_node, "CALLS");
    defer db.freeEdges(calls);
    try std.testing.expectEqual(@as(usize, 1), calls.len);
    try std.testing.expectEqual(helper_node, calls[0].target_id);

    const inherits = try db.findEdgesBySource(project_name, child_node, "INHERITS");
    defer db.freeEdges(inherits);
    try std.testing.expectEqual(@as(usize, 1), inherits.len);
    try std.testing.expectEqual(base_node, inherits[0].target_id);
}

fn findSingleNodeInStore(
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

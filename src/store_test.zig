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

test "store persists parser-backed extraction and call/usage edges" {
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
    const module_node = try findSingleNodeInStore(&db, project_name, "Module", "main", "main.py");
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

    const usages = try db.findEdgesBySource(project_name, module_node, "USAGE");
    defer db.freeEdges(usages);
    try std.testing.expect(edgeTargetsContain(usages, base_node));
    try std.testing.expect(!edgeTargetsContain(usages, child_node));
}

test "store persists derived TESTS and TESTS_FILE edges with test metadata" {
    const allocator = std.testing.allocator;

    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(
        allocator,
        "/tmp/cbm-store-test-tagging-{x}",
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
            \\def test_widget_renders():
            \\    return render_widget()
            \\
        );
    }

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();

    var p = pipeline.Pipeline.init(allocator, project_dir, .full);
    defer p.deinit();
    try p.run(&db);

    const project_name = std.fs.path.basename(project_dir);
    const render_id = try findSingleNodeInStore(&db, project_name, "Function", "render_widget", "widget.py");
    const test_id = try findSingleNodeInStore(&db, project_name, "Function", "test_widget_renders", "test_widget.py");
    const test_file_id = try findExactFileNodeInStore(&db, project_name, "test_widget.py");
    const prod_file_id = try findExactFileNodeInStore(&db, project_name, "widget.py");

    const tests_edges = try db.findEdgesBySource(project_name, test_id, "TESTS");
    defer db.freeEdges(tests_edges);
    try std.testing.expectEqual(@as(usize, 1), tests_edges.len);
    try std.testing.expectEqual(render_id, tests_edges[0].target_id);

    const file_edges = try db.findEdgesBySource(project_name, test_file_id, "TESTS_FILE");
    defer db.freeEdges(file_edges);
    try std.testing.expectEqual(@as(usize, 1), file_edges.len);
    try std.testing.expectEqual(prod_file_id, file_edges[0].target_id);

    const file_nodes = try db.searchNodes(.{
        .project = project_name,
        .label_pattern = "File",
        .name_pattern = "test_widget.py",
        .limit = 5,
    });
    defer db.freeNodes(file_nodes);
    try std.testing.expectEqual(@as(usize, 1), file_nodes.len);
    try std.testing.expect(std.mem.indexOf(u8, file_nodes[0].properties_json, "\"is_test\":true") != null);
}

fn edgeTargetsContain(edges: []const store.Edge, target_id: i64) bool {
    for (edges) |edge| {
        if (edge.target_id == target_id) return true;
    }
    return false;
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

fn findExactFileNodeInStore(db: *store.Store, project_name: []const u8, file_path: []const u8) !i64 {
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

// --- Error-path and edge-case tests ---

test "deleteProject is idempotent on non-existent project" {
    var db = try store.Store.openMemory(std.testing.allocator);
    defer db.deinit();

    // DELETE WHERE name = ? on an empty projects table should be a no-op
    try db.deleteProject("nonexistent_project_xyz");
}

test "searchNodes returns empty for unknown project" {
    var db = try store.Store.openMemory(std.testing.allocator);
    defer db.deinit();

    const nodes = try db.searchNodes(.{
        .project = "ghost_project",
        .limit = 10,
    });
    defer db.freeNodes(nodes);

    try std.testing.expectEqual(@as(usize, 0), nodes.len);
}

test "findNodeById returns null for invalid ID" {
    var db = try store.Store.openMemory(std.testing.allocator);
    defer db.deinit();

    const result = try db.findNodeById("test", 99999);
    try std.testing.expectEqual(@as(?store.Node, null), result);
}

test "searchGraph returns empty page for unknown project" {
    var db = try store.Store.openMemory(std.testing.allocator);
    defer db.deinit();

    const page = try db.searchGraph(.{ .project = "nonexistent" });
    defer db.freeGraphSearchPage(page);

    try std.testing.expectEqual(@as(usize, 0), page.total);
    try std.testing.expectEqual(@as(usize, 0), page.hits.len);
}

test "getProjectStatus returns not_found for missing project" {
    var db = try store.Store.openMemory(std.testing.allocator);
    defer db.deinit();

    const status = try db.getProjectStatus("absent_project_xyz");
    defer db.freeProjectStatus(status);

    try std.testing.expectEqual(store.ProjectStatus.Status.not_found, status.status);
    try std.testing.expectEqualStrings("absent_project_xyz", status.project);
}

test "traverseEdgesBreadthFirst returns empty for nonexistent node" {
    var db = try store.Store.openMemory(std.testing.allocator);
    defer db.deinit();

    const result = try db.traverseEdgesBreadthFirst("test", 99999, .both, 3, null, null);
    defer db.freeTraversalEdges(result);

    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "traverseEdgesBreadthFirst multi-edge-type filtering" {
    var db = try store.Store.openMemory(std.testing.allocator);
    defer db.deinit();

    try db.upsertProject("mt", "/tmp/mt");
    const a_id = try db.upsertNode(.{
        .project = "mt",
        .label = "Function",
        .name = "a",
        .qualified_name = "mt:a",
        .file_path = "main.py",
    });
    const b_id = try db.upsertNode(.{
        .project = "mt",
        .label = "Function",
        .name = "b",
        .qualified_name = "mt:b",
        .file_path = "main.py",
    });
    const c_id = try db.upsertNode(.{
        .project = "mt",
        .label = "Function",
        .name = "c",
        .qualified_name = "mt:c",
        .file_path = "main.py",
    });
    const d_id = try db.upsertNode(.{
        .project = "mt",
        .label = "Function",
        .name = "d",
        .qualified_name = "mt:d",
        .file_path = "main.py",
    });

    // a -> b via CALLS
    _ = try db.upsertEdge(.{ .project = "mt", .source_id = a_id, .target_id = b_id, .edge_type = "CALLS" });
    // a -> c via DATA_FLOWS
    _ = try db.upsertEdge(.{ .project = "mt", .source_id = a_id, .target_id = c_id, .edge_type = "DATA_FLOWS" });
    // a -> d via HTTP_CALLS
    _ = try db.upsertEdge(.{ .project = "mt", .source_id = a_id, .target_id = d_id, .edge_type = "HTTP_CALLS" });

    // Single type: only CALLS
    {
        const result = try db.traverseEdgesBreadthFirst("mt", a_id, .outbound, 1, &.{"CALLS"}, null);
        defer db.freeTraversalEdges(result);
        try std.testing.expectEqual(@as(usize, 1), result.len);
        try std.testing.expectEqual(b_id, result[0].target_id);
    }

    // Two types: CALLS + DATA_FLOWS
    {
        const result = try db.traverseEdgesBreadthFirst("mt", a_id, .outbound, 1, &.{ "CALLS", "DATA_FLOWS" }, null);
        defer db.freeTraversalEdges(result);
        try std.testing.expectEqual(@as(usize, 2), result.len);
    }

    // Three types: all edges
    {
        const result = try db.traverseEdgesBreadthFirst("mt", a_id, .outbound, 1, &.{ "CALLS", "DATA_FLOWS", "HTTP_CALLS" }, null);
        defer db.freeTraversalEdges(result);
        try std.testing.expectEqual(@as(usize, 3), result.len);
    }

    // Null types: all edges (no filter)
    {
        const result = try db.traverseEdgesBreadthFirst("mt", a_id, .outbound, 1, null, null);
        defer db.freeTraversalEdges(result);
        try std.testing.expectEqual(@as(usize, 3), result.len);
    }
}

test "traverseEdgesBreadthFirst max_results cap" {
    var db = try store.Store.openMemory(std.testing.allocator);
    defer db.deinit();

    try db.upsertProject("mr", "/tmp/mr");
    const root_id = try db.upsertNode(.{
        .project = "mr",
        .label = "Function",
        .name = "root",
        .qualified_name = "mr:root",
        .file_path = "main.py",
    });
    // Create a chain: root -> n1 -> n2 -> n3 -> n4
    var prev_id = root_id;
    var node_ids: [4]i64 = undefined;
    for (0..4) |i| {
        const name = switch (i) {
            0 => "n1",
            1 => "n2",
            2 => "n3",
            3 => "n4",
            else => unreachable,
        };
        const qn = switch (i) {
            0 => "mr:n1",
            1 => "mr:n2",
            2 => "mr:n3",
            3 => "mr:n4",
            else => unreachable,
        };
        const nid = try db.upsertNode(.{
            .project = "mr",
            .label = "Function",
            .name = name,
            .qualified_name = qn,
            .file_path = "main.py",
        });
        node_ids[i] = nid;
        _ = try db.upsertEdge(.{ .project = "mr", .source_id = prev_id, .target_id = nid, .edge_type = "CALLS" });
        prev_id = nid;
    }

    // Without cap: 4 edges
    {
        const result = try db.traverseEdgesBreadthFirst("mr", root_id, .outbound, 10, null, null);
        defer db.freeTraversalEdges(result);
        try std.testing.expectEqual(@as(usize, 4), result.len);
    }

    // With max_results=2: caps visited nodes, so BFS stops after visiting ~2 neighbors
    {
        const result = try db.traverseEdgesBreadthFirst("mr", root_id, .outbound, 10, null, 2);
        defer db.freeTraversalEdges(result);
        // With max_results=2 the BFS should stop before visiting all 4 targets
        try std.testing.expect(result.len < 4);
        try std.testing.expect(result.len >= 1);
    }
}

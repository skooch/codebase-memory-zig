// route_nodes — Creates Route nodes from HTTP_CALLS and ASYNC_CALLS edges.
//
// This is a minimal first pass: it creates Route nodes as rendezvous points
// for cross-service communication, keyed by the call target's resolved name
// and inferred HTTP method. Future work will add HANDLES edges from decorator-
// detected route handlers and DATA_FLOWS edges linking callers to handlers.

const std = @import("std");
const graph_buffer = @import("graph_buffer.zig");
const GraphBufferError = graph_buffer.GraphBufferError;
const service_patterns = @import("service_patterns.zig");

/// Create Route nodes from HTTP_CALLS and ASYNC_CALLS edges.
/// Returns the number of Route nodes created.
pub fn runPass(
    allocator: std.mem.Allocator,
    gb: *graph_buffer.GraphBuffer,
) error{OutOfMemory}!usize {
    var routes_created: usize = 0;

    // Snapshot the current edge count so we only scan pre-existing edges.
    const edge_count = gb.edgeItems().len;
    var i: usize = 0;
    while (i < edge_count) : (i += 1) {
        const edge = gb.edgeItems()[i];
        const is_http = std.mem.eql(u8, edge.edge_type, "HTTP_CALLS");
        const is_async = std.mem.eql(u8, edge.edge_type, "ASYNC_CALLS");
        if (!is_http and !is_async) continue;

        const target = gb.findNodeById(edge.target_id) orelse continue;

        // Infer HTTP method from the target QN, or default.
        const method: []const u8 = if (is_http)
            (service_patterns.httpMethod(target.qualified_name) orelse "UNKNOWN")
        else
            "ASYNC";

        const source_label: []const u8 = if (is_http) "http_call" else "async_call";

        // Build a deterministic Route QN: __route__METHOD__<target_qualified_name>
        const route_qn = std.fmt.allocPrint(
            allocator,
            "__route__{s}__{s}",
            .{ method, target.qualified_name },
        ) catch return error.OutOfMemory;
        defer allocator.free(route_qn);

        // Build display name.
        const route_name = std.fmt.allocPrint(
            allocator,
            "{s} {s}",
            .{ method, target.name },
        ) catch return error.OutOfMemory;
        defer allocator.free(route_name);

        // Build properties JSON.
        const props = std.fmt.allocPrint(
            allocator,
            "{{\"method\":\"{s}\",\"source\":\"{s}\"}}",
            .{ method, source_label },
        ) catch return error.OutOfMemory;
        defer allocator.free(props);

        const existing = gb.findNodeByQualifiedName(route_qn);
        if (existing == null) {
            _ = gb.upsertNodeWithProperties(
                "Route",
                route_name,
                route_qn,
                target.file_path,
                0,
                0,
                props,
            ) catch return error.OutOfMemory;
            routes_created += 1;
        }
    }

    return routes_created;
}

test "runPass creates Route nodes from HTTP_CALLS edges" {
    const allocator = std.testing.allocator;

    var gb = graph_buffer.GraphBuffer.init(allocator, "test-project");
    defer gb.deinit();

    // Create caller and target nodes.
    const caller_id = try gb.upsertNode("Function", "make_request", "test:main.py:make_request", "main.py", 1, 5);
    const target_id = try gb.upsertNode("Function", "get", "test:requests.get", "requests/__init__.py", 1, 10);

    // Create an HTTP_CALLS edge.
    _ = try gb.insertEdge(caller_id, target_id, "HTTP_CALLS");

    const routes = try runPass(allocator, &gb);
    try std.testing.expectEqual(@as(usize, 1), routes);

    // Verify Route node exists.
    const route = gb.findNodeByQualifiedName("__route__GET__test:requests.get");
    try std.testing.expect(route != null);
    try std.testing.expectEqualStrings("Route", route.?.label);
}

test "runPass creates Route nodes from ASYNC_CALLS edges" {
    const allocator = std.testing.allocator;

    var gb = graph_buffer.GraphBuffer.init(allocator, "test-project");
    defer gb.deinit();

    const caller_id = try gb.upsertNode("Function", "publish_event", "test:main.py:publish_event", "main.py", 1, 5);
    const target_id = try gb.upsertNode("Function", "publish", "test:pubsub.publish", "pubsub.py", 1, 10);

    _ = try gb.insertEdge(caller_id, target_id, "ASYNC_CALLS");

    const routes = try runPass(allocator, &gb);
    try std.testing.expectEqual(@as(usize, 1), routes);

    const route = gb.findNodeByQualifiedName("__route__ASYNC__test:pubsub.publish");
    try std.testing.expect(route != null);
    try std.testing.expectEqualStrings("Route", route.?.label);
}

test "runPass deduplicates Route nodes" {
    const allocator = std.testing.allocator;

    var gb = graph_buffer.GraphBuffer.init(allocator, "test-project");
    defer gb.deinit();

    const caller1 = try gb.upsertNode("Function", "f1", "test:a.py:f1", "a.py", 1, 3);
    const caller2 = try gb.upsertNode("Function", "f2", "test:b.py:f2", "b.py", 1, 3);
    const target = try gb.upsertNode("Function", "get", "test:requests.get", "requests/__init__.py", 1, 10);

    _ = try gb.insertEdge(caller1, target, "HTTP_CALLS");
    _ = try gb.insertEdge(caller2, target, "HTTP_CALLS");

    const routes = try runPass(allocator, &gb);
    // Only one Route node should be created despite two HTTP_CALLS edges
    // targeting the same function.
    try std.testing.expectEqual(@as(usize, 1), routes);
}

test "runPass ignores regular CALLS edges" {
    const allocator = std.testing.allocator;

    var gb = graph_buffer.GraphBuffer.init(allocator, "test-project");
    defer gb.deinit();

    const caller = try gb.upsertNode("Function", "main", "test:main.py:main", "main.py", 1, 5);
    const target = try gb.upsertNode("Function", "helper", "test:utils.py:helper", "utils.py", 1, 10);

    _ = try gb.insertEdge(caller, target, "CALLS");

    const routes = try runPass(allocator, &gb);
    try std.testing.expectEqual(@as(usize, 0), routes);
}

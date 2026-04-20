// routes — Shared helpers for Route-node identity plus route graph synthesis.

const std = @import("std");
const graph_buffer = @import("graph_buffer.zig");
const GraphBufferError = graph_buffer.GraphBufferError;
const service_patterns = @import("service_patterns.zig");

pub const RouteKind = enum {
    http,
    @"async",
};

pub const ParsedRoute = struct {
    kind: RouteKind,
    token: []const u8,
    name: []const u8,
};

pub const AsyncRouteInfo = struct {
    broker: []const u8,
    topic: []const u8,
};

pub fn parseQualifiedName(qualified_name: []const u8) ?ParsedRoute {
    if (!std.mem.startsWith(u8, qualified_name, "__route__")) return null;
    const rest = qualified_name["__route__".len..];
    const sep = std.mem.indexOf(u8, rest, "__") orelse return null;
    if (sep == 0 or sep + 2 >= rest.len) return null;
    const token = rest[0..sep];
    const name = rest[sep + 2 ..];
    return .{
        .kind = if (isHttpRouteToken(token)) .http else .@"async",
        .token = token,
        .name = name,
    };
}

pub fn asyncInfo(node: *const graph_buffer.BufferNode) ?AsyncRouteInfo {
    if (!std.mem.eql(u8, node.label, "Route")) return null;
    const parsed = parseQualifiedName(node.qualified_name) orelse return null;
    if (parsed.kind != .@"async") return null;
    return .{
        .broker = parsed.token,
        .topic = parsed.name,
    };
}

pub fn upsertHttpRoute(
    allocator: std.mem.Allocator,
    gb: *graph_buffer.GraphBuffer,
    file_path: []const u8,
    method: []const u8,
    route_path: []const u8,
    source: []const u8,
) error{OutOfMemory}!i64 {
    const props = std.fmt.allocPrint(
        allocator,
        "{{\"method\":\"{s}\",\"source\":\"{s}\"}}",
        .{ method, source },
    ) catch return error.OutOfMemory;
    defer allocator.free(props);
    return upsertRoute(gb, route_path, method, route_path, file_path, props);
}

pub fn upsertAsyncRoute(
    allocator: std.mem.Allocator,
    gb: *graph_buffer.GraphBuffer,
    file_path: []const u8,
    broker: []const u8,
    topic: []const u8,
    source: []const u8,
) error{OutOfMemory}!i64 {
    const props = std.fmt.allocPrint(
        allocator,
        "{{\"broker\":\"{s}\",\"source\":\"{s}\"}}",
        .{ broker, source },
    ) catch return error.OutOfMemory;
    defer allocator.free(props);
    return upsertRoute(gb, topic, broker, topic, file_path, props);
}

pub fn runPass(
    allocator: std.mem.Allocator,
    gb: *graph_buffer.GraphBuffer,
) error{OutOfMemory}!usize {
    var routes_created: usize = 0;
    const edge_count = gb.edgeItems().len;
    var i: usize = 0;
    while (i < edge_count) : (i += 1) {
        const edge = gb.edgeItems()[i];
        const is_http = std.mem.eql(u8, edge.edge_type, "HTTP_CALLS");
        const is_async = std.mem.eql(u8, edge.edge_type, "ASYNC_CALLS");
        if (!is_http and !is_async) continue;

        const target = gb.findNodeById(edge.target_id) orelse continue;
        if (std.mem.eql(u8, target.label, "Route")) continue;

        const route_qn = if (is_http)
            routeQualifiedName(
                allocator,
                service_patterns.httpMethod(target.qualified_name) orelse "UNKNOWN",
                target.name,
            ) catch return error.OutOfMemory
        else
            routeQualifiedName(
                allocator,
                service_patterns.asyncBroker(target.qualified_name) orelse "async",
                target.name,
            ) catch return error.OutOfMemory;
        defer allocator.free(route_qn);
        const existing = gb.findNodeByQualifiedName(route_qn);

        _ = if (is_http)
            upsertHttpRoute(
                allocator,
                gb,
                target.file_path,
                service_patterns.httpMethod(target.qualified_name) orelse "UNKNOWN",
                target.name,
                "http_call",
            ) catch return error.OutOfMemory
        else
            upsertAsyncRoute(
                allocator,
                gb,
                target.file_path,
                service_patterns.asyncBroker(target.qualified_name) orelse "async",
                target.name,
                "async_call",
            ) catch return error.OutOfMemory;

        if (existing == null) routes_created += 1;
    }

    _ = try createRouteDataFlows(allocator, gb);
    return routes_created;
}

fn upsertRoute(
    gb: *graph_buffer.GraphBuffer,
    display_name: []const u8,
    token: []const u8,
    logical_name: []const u8,
    file_path: []const u8,
    properties_json: []const u8,
) error{OutOfMemory}!i64 {
    const route_qn = routeQualifiedName(gb.allocator, token, logical_name) catch return error.OutOfMemory;
    defer gb.allocator.free(route_qn);
    return gb.upsertNodeWithProperties(
        "Route",
        display_name,
        route_qn,
        file_path,
        0,
        0,
        properties_json,
    ) catch return error.OutOfMemory;
}

fn routeQualifiedName(
    allocator: std.mem.Allocator,
    token: []const u8,
    logical_name: []const u8,
) error{OutOfMemory}![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "__route__{s}__{s}",
        .{ token, logical_name },
    ) catch return error.OutOfMemory;
}

fn isHttpRouteToken(token: []const u8) bool {
    const tokens = [_][]const u8{ "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS", "ANY", "UNKNOWN" };
    for (tokens) |candidate| {
        if (std.mem.eql(u8, token, candidate)) return true;
    }
    return false;
}

fn createRouteDataFlows(
    allocator: std.mem.Allocator,
    gb: *graph_buffer.GraphBuffer,
) error{OutOfMemory}!usize {
    var flows_created: usize = 0;
    const edge_count = gb.edgeItems().len;

    for (gb.nodes()) |route| {
        if (!std.mem.eql(u8, route.label, "Route")) continue;

        var caller_index: usize = 0;
        while (caller_index < edge_count) : (caller_index += 1) {
            const caller_edge = gb.edgeItems()[caller_index];
            if (caller_edge.target_id != route.id) continue;
            const is_http = std.mem.eql(u8, caller_edge.edge_type, "HTTP_CALLS");
            const is_async = std.mem.eql(u8, caller_edge.edge_type, "ASYNC_CALLS");
            if (!is_http and !is_async) continue;

            var handler_index: usize = 0;
            while (handler_index < edge_count) : (handler_index += 1) {
                const handler_edge = gb.edgeItems()[handler_index];
                if (handler_edge.target_id != route.id) continue;
                if (!std.mem.eql(u8, handler_edge.edge_type, "HANDLES")) continue;
                if (caller_edge.source_id == handler_edge.source_id) continue;
                if (hasDirectCall(gb, caller_edge.source_id, handler_edge.source_id)) continue;

                const props = std.fmt.allocPrint(
                    allocator,
                    "{{\"via\":\"{s}\",\"route\":\"{s}\",\"edge_type\":\"{s}\"}}",
                    .{ route.name, route.qualified_name, caller_edge.edge_type },
                ) catch return error.OutOfMemory;
                defer allocator.free(props);

                _ = gb.insertEdgeWithProperties(caller_edge.source_id, handler_edge.source_id, "DATA_FLOWS", props) catch |err| switch (err) {
                    GraphBufferError.DuplicateEdge => 0,
                    GraphBufferError.OutOfMemory => return error.OutOfMemory,
                };
                flows_created += 1;
            }
        }
    }

    return flows_created;
}

fn hasDirectCall(gb: *const graph_buffer.GraphBuffer, caller_id: i64, handler_id: i64) bool {
    for (gb.edgeItems()) |edge| {
        if (edge.source_id == caller_id and edge.target_id == handler_id and std.mem.eql(u8, edge.edge_type, "CALLS")) return true;
    }
    return false;
}

test "runPass creates Route nodes from HTTP_CALLS edges" {
    const allocator = std.testing.allocator;

    var gb = graph_buffer.GraphBuffer.init(allocator, "test-project");
    defer gb.deinit();

    const caller_id = try gb.upsertNode("Function", "make_request", "test:main.py:make_request", "main.py", 1, 5);
    const target_id = try gb.upsertNode("Function", "get", "test:requests.get", "requests/__init__.py", 1, 10);

    _ = try gb.insertEdge(caller_id, target_id, "HTTP_CALLS");

    const routes_created = try runPass(allocator, &gb);
    try std.testing.expectEqual(@as(usize, 1), routes_created);

    const route = gb.findNodeByQualifiedName("__route__GET__get");
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

    const routes_created = try runPass(allocator, &gb);
    try std.testing.expectEqual(@as(usize, 1), routes_created);

    const route = gb.findNodeByQualifiedName("__route__pubsub__publish");
    try std.testing.expect(route != null);
    try std.testing.expectEqualStrings("Route", route.?.label);
}

test "upsertAsyncRoute exposes async info" {
    const allocator = std.testing.allocator;

    var gb = graph_buffer.GraphBuffer.init(allocator, "async-project");
    defer gb.deinit();

    const route_id = try upsertAsyncRoute(allocator, &gb, "worker.py", "celery", "users.refresh", "decorator");
    const route = gb.findNodeById(route_id) orelse return error.TestUnexpectedResult;
    const info = asyncInfo(route) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("celery", info.broker);
    try std.testing.expectEqualStrings("users.refresh", info.topic);
}

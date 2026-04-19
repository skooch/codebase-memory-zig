// semantic_links — Builds explicit topic nodes and message edges from route facts.

const std = @import("std");
const graph_buffer = @import("graph_buffer.zig");
const GraphBufferError = graph_buffer.GraphBufferError;
const routes = @import("routes.zig");

pub const Counts = struct {
    topics_created: usize = 0,
    emits_created: usize = 0,
    subscribes_created: usize = 0,
};

pub fn runPass(
    allocator: std.mem.Allocator,
    gb: *graph_buffer.GraphBuffer,
) error{OutOfMemory}!Counts {
    var counts = Counts{};
    const edge_count = gb.edgeItems().len;

    for (gb.nodes()) |*route| {
        const info = routes.asyncInfo(route) orelse continue;
        const topic_qn = std.fmt.allocPrint(
            allocator,
            "__event__{s}__{s}",
            .{ info.broker, info.topic },
        ) catch return error.OutOfMemory;
        defer allocator.free(topic_qn);

        var topic_id: i64 = 0;
        if (gb.findNodeByQualifiedName(topic_qn)) |existing| {
            topic_id = existing.id;
        } else {
            const props = std.fmt.allocPrint(
                allocator,
                "{{\"broker\":\"{s}\",\"route\":\"{s}\"}}",
                .{ info.broker, route.qualified_name },
            ) catch return error.OutOfMemory;
            defer allocator.free(props);

            topic_id = gb.upsertNodeWithProperties(
                "EventTopic",
                info.topic,
                topic_qn,
                route.file_path,
                0,
                0,
                props,
            ) catch return error.OutOfMemory;
            counts.topics_created += 1;
        }

        var i: usize = 0;
        while (i < edge_count) : (i += 1) {
            const edge = gb.edgeItems()[i];
            if (edge.target_id != route.id) continue;

            if (std.mem.eql(u8, edge.edge_type, "ASYNC_CALLS")) {
                if (try insertSemanticEdge(allocator, gb, edge.source_id, topic_id, "EMITS", info, route.qualified_name)) {
                    counts.emits_created += 1;
                }
                continue;
            }
            if (std.mem.eql(u8, edge.edge_type, "HANDLES")) {
                if (try insertSemanticEdge(allocator, gb, edge.source_id, topic_id, "SUBSCRIBES", info, route.qualified_name)) {
                    counts.subscribes_created += 1;
                }
            }
        }
    }

    return counts;
}

fn insertSemanticEdge(
    allocator: std.mem.Allocator,
    gb: *graph_buffer.GraphBuffer,
    source_id: i64,
    target_id: i64,
    edge_type: []const u8,
    info: routes.AsyncRouteInfo,
    route_qn: []const u8,
) error{OutOfMemory}!bool {
    const props = std.fmt.allocPrint(
        allocator,
        "{{\"broker\":\"{s}\",\"topic\":\"{s}\",\"route\":\"{s}\"}}",
        .{ info.broker, info.topic, route_qn },
    ) catch return error.OutOfMemory;
    defer allocator.free(props);

    _ = gb.insertEdgeWithProperties(source_id, target_id, edge_type, props) catch |err| switch (err) {
        GraphBufferError.DuplicateEdge => return false,
        GraphBufferError.OutOfMemory => return error.OutOfMemory,
    };
    return true;
}

fn hasEdge(gb: *const graph_buffer.GraphBuffer, source_id: i64, target_id: i64, edge_type: []const u8) bool {
    for (gb.edgeItems()) |edge| {
        if (edge.source_id == source_id and edge.target_id == target_id and std.mem.eql(u8, edge.edge_type, edge_type)) return true;
    }
    return false;
}

test "runPass creates EventTopic nodes and pubsub links" {
    const allocator = std.testing.allocator;

    var gb = graph_buffer.GraphBuffer.init(allocator, "async-project");
    defer gb.deinit();

    const publisher_id = try gb.upsertNode("Function", "enqueue_users", "async:worker.py:enqueue_users", "worker.py", 1, 3);
    const subscriber_id = try gb.upsertNode("Function", "refresh_users", "async:worker.py:refresh_users", "worker.py", 5, 7);
    const route_id = try routes.upsertAsyncRoute(allocator, &gb, "worker.py", "celery", "users.refresh", "decorator");

    _ = try gb.insertEdge(publisher_id, route_id, "ASYNC_CALLS");
    _ = try gb.insertEdge(subscriber_id, route_id, "HANDLES");

    const counts = try runPass(allocator, &gb);
    try std.testing.expectEqual(@as(usize, 1), counts.topics_created);
    try std.testing.expectEqual(@as(usize, 1), counts.emits_created);
    try std.testing.expectEqual(@as(usize, 1), counts.subscribes_created);

    const topic = gb.findNodeByQualifiedName("__event__celery__users.refresh") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("EventTopic", topic.label);
    try std.testing.expect(hasEdge(&gb, publisher_id, topic.id, "EMITS"));
    try std.testing.expect(hasEdge(&gb, subscriber_id, topic.id, "SUBSCRIBES"));
}

test "runPass ignores HTTP routes" {
    const allocator = std.testing.allocator;

    var gb = graph_buffer.GraphBuffer.init(allocator, "http-project");
    defer gb.deinit();

    _ = try routes.upsertHttpRoute(allocator, &gb, "app.py", "GET", "/users", "decorator");

    const counts = try runPass(allocator, &gb);
    try std.testing.expectEqual(@as(usize, 0), counts.topics_created);
    try std.testing.expect(gb.findNodeByQualifiedName("__event__GET__/users") == null);
}

// graph_buffer.zig — In-memory graph buffer for pipeline indexing.
//
// Holds all nodes and edges in RAM during indexing, then dumps to SQLite.
// Provides O(1) node lookup by qualified name and edge dedup by key.

const std = @import("std");
const store = @import("store.zig");

pub const BufferNode = struct {
    id: i64,
    label: []const u8,
    name: []const u8,
    qualified_name: []const u8,
    file_path: []const u8,
    start_line: i32 = 0,
    end_line: i32 = 0,
    properties_json: []const u8 = "{}",
};

pub const BufferEdge = struct {
    id: i64,
    source_id: i64,
    target_id: i64,
    edge_type: []const u8,
    properties_json: []const u8 = "{}",
};

pub const GraphBuffer = struct {
    allocator: std.mem.Allocator,
    project: []const u8,
    nodes_by_qn: std.StringHashMap(BufferNode),
    edges: std.ArrayList(BufferEdge),
    next_id: i64 = 1,

    pub fn init(allocator: std.mem.Allocator, project: []const u8) GraphBuffer {
        return .{
            .allocator = allocator,
            .project = project,
            .nodes_by_qn = std.StringHashMap(BufferNode).init(allocator),
            .edges = .empty,
        };
    }

    pub fn deinit(self: *GraphBuffer) void {
        self.nodes_by_qn.deinit();
        self.edges.deinit(self.allocator);
    }

    pub fn upsertNode(
        self: *GraphBuffer,
        label: []const u8,
        name: []const u8,
        qualified_name: []const u8,
        file_path: []const u8,
        start_line: i32,
        end_line: i32,
    ) i64 {
        if (self.nodes_by_qn.get(qualified_name)) |existing| {
            return existing.id;
        }
        const id = self.next_id;
        self.next_id += 1;
        self.nodes_by_qn.put(qualified_name, .{
            .id = id,
            .label = label,
            .name = name,
            .qualified_name = qualified_name,
            .file_path = file_path,
            .start_line = start_line,
            .end_line = end_line,
        }) catch return 0;
        return id;
    }

    pub fn insertEdge(
        self: *GraphBuffer,
        source_id: i64,
        target_id: i64,
        edge_type: []const u8,
    ) i64 {
        const id = self.next_id;
        self.next_id += 1;
        self.edges.append(self.allocator, .{
            .id = id,
            .source_id = source_id,
            .target_id = target_id,
            .edge_type = edge_type,
        }) catch return 0;
        return id;
    }

    pub fn nodeCount(self: *const GraphBuffer) usize {
        return self.nodes_by_qn.count();
    }

    pub fn edgeCount(self: *const GraphBuffer) usize {
        return self.edges.items.len;
    }
};

test "graph buffer basic ops" {
    var gb = GraphBuffer.init(std.testing.allocator, "test-project");
    defer gb.deinit();

    const id1 = gb.upsertNode("Function", "foo", "test.foo", "src/main.zig", 1, 10);
    const id2 = gb.upsertNode("Function", "bar", "test.bar", "src/main.zig", 12, 20);
    try std.testing.expect(id1 > 0);
    try std.testing.expect(id2 > 0);
    try std.testing.expect(id1 != id2);
    try std.testing.expectEqual(@as(usize, 2), gb.nodeCount());

    // Upsert same QN returns existing ID.
    const id1_dup = gb.upsertNode("Function", "foo", "test.foo", "src/main.zig", 1, 10);
    try std.testing.expectEqual(id1, id1_dup);
    try std.testing.expectEqual(@as(usize, 2), gb.nodeCount());

    const eid = gb.insertEdge(id1, id2, "CALLS");
    try std.testing.expect(eid > 0);
    try std.testing.expectEqual(@as(usize, 1), gb.edgeCount());
}

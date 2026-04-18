// graph_buffer.zig — In-memory graph buffer for pipeline indexing.
//
// Holds discovered nodes and edges in RAM, then persists them into SQLite.

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

pub const GraphBufferError = error{
    OutOfMemory,
    DuplicateEdge,
};

pub const GraphLimitError = error{
    GraphTooLarge,
};

pub const GraphSizeLimit = struct {
    max_nodes: usize = 1_000_000,
    max_edges: usize = 4_000_000,
};

pub const default_graph_size_limit = GraphSizeLimit{};

fn ownedNodeFromSlices(
    allocator: std.mem.Allocator,
    label: []const u8,
    name: []const u8,
    qualified_name: []const u8,
    file_path: []const u8,
    start_line: i32,
    end_line: i32,
    properties_json: []const u8,
) !BufferNode {
    const label_copy = try allocator.dupe(u8, label);
    errdefer allocator.free(label_copy);
    const name_copy = try allocator.dupe(u8, name);
    errdefer allocator.free(name_copy);
    const qn_copy = try allocator.dupe(u8, qualified_name);
    errdefer allocator.free(qn_copy);
    const file_path_copy = try allocator.dupe(u8, file_path);
    errdefer allocator.free(file_path_copy);
    const properties_copy = try allocator.dupe(u8, properties_json);

    return .{
        .id = 0,
        .label = label_copy,
        .name = name_copy,
        .qualified_name = qn_copy,
        .file_path = file_path_copy,
        .start_line = start_line,
        .end_line = end_line,
        .properties_json = properties_copy,
    };
}

pub const GraphBuffer = struct {
    allocator: std.mem.Allocator,
    project: []const u8,
    nodes_by_qn: std.StringHashMap(i64),
    nodes_by_id: std.ArrayList(BufferNode),
    edges: std.ArrayList(BufferEdge),
    edge_keys: std.StringHashMap(void),
    next_node_id: i64 = 1,
    next_edge_id: i64 = 1,

    pub fn init(allocator: std.mem.Allocator, project: []const u8) GraphBuffer {
        return .{
            .allocator = allocator,
            .project = project,
            .nodes_by_qn = std.StringHashMap(i64).init(allocator),
            .nodes_by_id = .empty,
            .edges = .empty,
            .edge_keys = std.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *GraphBuffer) void {
        for (self.nodes_by_id.items) |node| {
            self.allocator.free(node.label);
            self.allocator.free(node.name);
            self.allocator.free(node.qualified_name);
            self.allocator.free(node.file_path);
            self.allocator.free(node.properties_json);
        }
        for (self.edges.items) |edge| {
            self.allocator.free(edge.edge_type);
            self.allocator.free(edge.properties_json);
        }
        var node_key_it = self.nodes_by_qn.iterator();
        while (node_key_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        var edge_key_it = self.edge_keys.iterator();
        while (edge_key_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.nodes_by_id.deinit(self.allocator);
        self.edges.deinit(self.allocator);
        self.nodes_by_qn.deinit();
        self.edge_keys.deinit();
    }

    pub fn upsertNode(
        self: *GraphBuffer,
        label: []const u8,
        name: []const u8,
        qualified_name: []const u8,
        file_path: []const u8,
        start_line: i32,
        end_line: i32,
    ) !i64 {
        if (self.nodes_by_qn.get(qualified_name)) |id| {
            if (self.findNodeByIdMut(id)) |node| mergeNodeSpan(node, start_line, end_line);
            return id;
        }

        const id = self.next_node_id;
        const qn_copy = try self.allocator.dupe(u8, qualified_name);
        errdefer self.allocator.free(qn_copy);
        const node = try ownedNodeFromSlices(
            self.allocator,
            label,
            name,
            qualified_name,
            file_path,
            start_line,
            end_line,
            "{}",
        );
        errdefer self.freeNode(node);

        var inserted = node;
        inserted.id = id;
        self.nodes_by_id.append(self.allocator, inserted) catch {
            return GraphBufferError.OutOfMemory;
        };
        self.nodes_by_qn.put(qn_copy, id) catch {
            _ = self.nodes_by_id.pop();
            return GraphBufferError.OutOfMemory;
        };

        self.next_node_id += 1;
        return id;
    }

    pub fn upsertNodeWithProperties(
        self: *GraphBuffer,
        label: []const u8,
        name: []const u8,
        qualified_name: []const u8,
        file_path: []const u8,
        start_line: i32,
        end_line: i32,
        properties_json: []const u8,
    ) !i64 {
        if (self.nodes_by_qn.get(qualified_name)) |id| {
            if (self.findNodeByIdMut(id)) |node| mergeNodeSpan(node, start_line, end_line);
            return id;
        }

        const id = self.next_node_id;
        const qn_copy = try self.allocator.dupe(u8, qualified_name);
        errdefer self.allocator.free(qn_copy);
        const node = try ownedNodeFromSlices(
            self.allocator,
            label,
            name,
            qualified_name,
            file_path,
            start_line,
            end_line,
            properties_json,
        );
        errdefer self.freeNode(node);

        var inserted = node;
        inserted.id = id;
        self.nodes_by_id.append(self.allocator, inserted) catch {
            return GraphBufferError.OutOfMemory;
        };
        self.nodes_by_qn.put(qn_copy, id) catch {
            _ = self.nodes_by_id.pop();
            return GraphBufferError.OutOfMemory;
        };
        self.next_node_id += 1;
        return id;
    }

    pub fn insertEdge(
        self: *GraphBuffer,
        source_id: i64,
        target_id: i64,
        edge_type: []const u8,
    ) !i64 {
        return self.insertEdgeWithProperties(source_id, target_id, edge_type, "{}");
    }

    pub fn insertEdgeWithProperties(
        self: *GraphBuffer,
        source_id: i64,
        target_id: i64,
        edge_type: []const u8,
        properties_json: []const u8,
    ) !i64 {
        if (source_id <= 0 or target_id <= 0) return 0;
        if (self.findNodeById(source_id) == null or self.findNodeById(target_id) == null) {
            return 0;
        }

        const key = try self.makeEdgeKey(source_id, target_id, edge_type);
        const key_taken = self.edge_keys.contains(key);
        if (key_taken) {
            self.allocator.free(key);
            return GraphBufferError.DuplicateEdge;
        }

        const edge_type_copy = try self.allocator.dupe(u8, edge_type);
        const props_copy = try self.allocator.dupe(u8, properties_json);
        self.edge_keys.putNoClobber(key, {}) catch {
            self.allocator.free(key);
            self.allocator.free(edge_type_copy);
            self.allocator.free(props_copy);
            return GraphBufferError.OutOfMemory;
        };

        const id = self.next_edge_id;
        self.edges.append(self.allocator, .{
            .id = id,
            .source_id = source_id,
            .target_id = target_id,
            .edge_type = edge_type_copy,
            .properties_json = props_copy,
        }) catch {
            _ = self.edge_keys.remove(key);
            self.allocator.free(key);
            self.allocator.free(edge_type_copy);
            self.allocator.free(props_copy);
            return GraphBufferError.OutOfMemory;
        };
        self.next_edge_id += 1;
        return id;
    }

    pub fn findNodeId(self: *const GraphBuffer, qualified_name: []const u8) ?i64 {
        return self.nodes_by_qn.get(qualified_name);
    }

    pub fn findNodeByQualifiedName(self: *const GraphBuffer, qualified_name: []const u8) ?*const BufferNode {
        const id = self.nodes_by_qn.get(qualified_name) orelse return null;
        return self.findNodeById(id);
    }

    pub fn findNodeById(self: *const GraphBuffer, id: i64) ?*const BufferNode {
        return @ptrCast(@constCast(findNodeSlot(self.nodes_by_id.items, id) orelse return null));
    }

    fn findNodeByIdMut(self: *GraphBuffer, id: i64) ?*BufferNode {
        return findNodeSlot(self.nodes_by_id.items, id);
    }

    fn findNodeSlot(items: []BufferNode, id: i64) ?*BufferNode {
        if (id <= 0) return null;
        const idx = @as(usize, @intCast(id - 1));
        if (idx < items.len and items[idx].id == id) {
            return &items[idx];
        }
        for (items) |*node| {
            if (node.id == id) return node;
        }
        return null;
    }

    fn mergeNodeSpan(node: *BufferNode, start_line: i32, end_line: i32) void {
        if (start_line > 0 and (node.start_line <= 0 or start_line < node.start_line)) {
            node.start_line = start_line;
        }
        if (end_line > node.end_line) {
            node.end_line = end_line;
        }
    }

    pub fn nodes(self: *const GraphBuffer) []const BufferNode {
        return self.nodes_by_id.items;
    }

    pub fn edgeItems(self: *const GraphBuffer) []const BufferEdge {
        return self.edges.items;
    }

    pub fn loadFromStore(self: *GraphBuffer, db: *store.Store) !void {
        return self.loadFromStoreWithLimits(db, default_graph_size_limit);
    }

    pub fn loadFromStoreWithLimits(
        self: *GraphBuffer,
        db: *store.Store,
        limit: GraphSizeLimit,
    ) !void {
        const size = try db.getProjectGraphSize(self.project);
        try ensureGraphWithinLimits(self.project, size.nodes, size.edges, limit);

        try self.nodes_by_id.ensureTotalCapacity(self.allocator, size.nodes);
        try self.edges.ensureTotalCapacity(self.allocator, size.edges);

        const stored_nodes = try db.searchNodes(.{
            .project = self.project,
            .limit = @max(size.nodes, 1),
        });
        defer db.freeNodes(stored_nodes);

        const edges = try db.listEdges(self.project, null);
        defer db.freeEdges(edges);

        for (stored_nodes) |node| {
            const qn_copy = try self.allocator.dupe(u8, node.qualified_name);
            errdefer self.allocator.free(qn_copy);
            const owned = try ownedNodeFromSlices(
                self.allocator,
                node.label,
                node.name,
                node.qualified_name,
                node.file_path,
                node.start_line,
                node.end_line,
                node.properties_json,
            );
            errdefer self.freeNode(owned);

            var inserted = owned;
            inserted.id = node.id;
            try self.nodes_by_id.append(self.allocator, inserted);
            try self.nodes_by_qn.put(qn_copy, node.id);
            if (node.id >= self.next_node_id) {
                self.next_node_id = node.id + 1;
            }
        }

        for (edges) |edge| {
            const edge_type_copy = try self.allocator.dupe(u8, edge.edge_type);
            errdefer self.allocator.free(edge_type_copy);
            const props_copy = try self.allocator.dupe(u8, edge.properties_json);
            errdefer self.allocator.free(props_copy);
            const key = try self.makeEdgeKey(edge.source_id, edge.target_id, edge.edge_type);
            errdefer self.allocator.free(key);

            try self.edge_keys.put(key, {});
            try self.edges.append(self.allocator, .{
                .id = edge.id,
                .source_id = edge.source_id,
                .target_id = edge.target_id,
                .edge_type = edge_type_copy,
                .properties_json = props_copy,
            });
            if (edge.id >= self.next_edge_id) {
                self.next_edge_id = edge.id + 1;
            }
        }
    }

    pub fn deleteByFile(self: *GraphBuffer, file_path: []const u8) void {
        var removed = std.AutoHashMap(i64, void).init(self.allocator);
        defer removed.deinit();

        for (self.nodes_by_id.items) |node| {
            if (std.mem.eql(u8, node.file_path, file_path)) {
                removed.put(node.id, {}) catch {};
            }
        }

        self.removeNodes(&removed);
        self.pruneOrphanFolders();
    }

    fn pruneOrphanFolders(self: *GraphBuffer) void {
        while (true) {
            var removed = std.AutoHashMap(i64, void).init(self.allocator);
            defer removed.deinit();

            for (self.nodes_by_id.items) |node| {
                if (!std.mem.eql(u8, node.label, "Folder")) continue;
                if (self.nodeHasStructureChildren(node.id)) continue;
                removed.put(node.id, {}) catch {};
            }

            if (removed.count() == 0) return;
            self.removeNodes(&removed);
        }
    }

    fn nodeHasStructureChildren(self: *const GraphBuffer, node_id: i64) bool {
        for (self.edges.items) |edge| {
            if (edge.source_id != node_id) continue;
            if (std.mem.eql(u8, edge.edge_type, "CONTAINS_FILE") or
                std.mem.eql(u8, edge.edge_type, "CONTAINS_FOLDER"))
            {
                return true;
            }
        }
        return false;
    }

    fn removeNodes(self: *GraphBuffer, removed: *const std.AutoHashMap(i64, void)) void {
        var keep_nodes = std.ArrayList(BufferNode).empty;
        defer keep_nodes.deinit(self.allocator);

        for (self.nodes_by_id.items) |node| {
            if (removed.contains(node.id)) {
                if (self.nodes_by_qn.fetchRemove(node.qualified_name)) |entry| {
                    self.allocator.free(entry.key);
                }
                self.freeNode(node);
                continue;
            }
            keep_nodes.append(self.allocator, node) catch unreachable;
        }

        self.nodes_by_id.clearRetainingCapacity();
        self.nodes_by_id.appendSlice(self.allocator, keep_nodes.items) catch unreachable;

        var keep_edges = std.ArrayList(BufferEdge).empty;
        defer keep_edges.deinit(self.allocator);

        var old_edge_keys = self.edge_keys;
        self.edge_keys = std.StringHashMap(void).init(self.allocator);
        defer old_edge_keys.deinit();

        var edge_key_it = old_edge_keys.iterator();
        while (edge_key_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }

        for (self.edges.items) |edge| {
            if (removed.contains(edge.source_id) or removed.contains(edge.target_id)) {
                self.allocator.free(edge.edge_type);
                self.allocator.free(edge.properties_json);
                continue;
            }

            keep_edges.append(self.allocator, edge) catch unreachable;
            const key = self.makeEdgeKey(edge.source_id, edge.target_id, edge.edge_type) catch unreachable;
            self.edge_keys.put(key, {}) catch unreachable;
        }

        self.edges.clearRetainingCapacity();
        self.edges.appendSlice(self.allocator, keep_edges.items) catch unreachable;
    }

    pub fn edgesForSource(self: *const GraphBuffer, source_id: i64, out: *std.ArrayList(BufferEdge)) void {
        for (self.edges.items) |edge| {
            if (edge.source_id == source_id) {
                out.appendAssumeCapacity(edge);
            }
        }
    }

    pub fn edgesBySourceAndType(self: *const GraphBuffer, source_id: i64, edge_type: []const u8, out: *std.ArrayList(BufferEdge)) void {
        for (self.edges.items) |edge| {
            if (edge.source_id == source_id and std.mem.eql(u8, edge.edge_type, edge_type)) {
                out.appendAssumeCapacity(edge);
            }
        }
    }

    pub fn nodeCount(self: *const GraphBuffer) usize {
        return self.nodes_by_id.items.len;
    }

    pub fn edgeCount(self: *const GraphBuffer) usize {
        return self.edges.items.len;
    }

    fn makeEdgeKey(self: *GraphBuffer, source_id: i64, target_id: i64, edge_type: []const u8) ![]u8 {
        return try std.fmt.allocPrint(
            self.allocator,
            "{d}:{d}:{s}",
            .{ source_id, target_id, edge_type },
        );
    }

    pub fn ensureWithinLimits(self: *const GraphBuffer, limit: GraphSizeLimit) GraphLimitError!void {
        try ensureGraphWithinLimits(
            self.project,
            self.nodeCount(),
            self.edgeCount(),
            limit,
        );
    }

    pub fn dumpToStore(self: *const GraphBuffer, db: *store.Store) !void {
        return self.dumpToStoreWithLimits(db, default_graph_size_limit);
    }

    pub fn dumpToStoreWithLimits(
        self: *const GraphBuffer,
        db: *store.Store,
        limit: GraphSizeLimit,
    ) !void {
        try self.ensureWithinLimits(limit);

        var existing_nodes = std.AutoHashMap(i64, i64).init(self.allocator);
        defer existing_nodes.deinit();
        try existing_nodes.ensureTotalCapacity(@as(u32, @intCast(self.nodeCount())));

        for (self.nodes_by_id.items) |node| {
            const node_for_db = store.Node{
                .id = 0,
                .project = self.project,
                .label = node.label,
                .name = node.name,
                .qualified_name = node.qualified_name,
                .file_path = node.file_path,
                .start_line = node.start_line,
                .end_line = node.end_line,
                .properties_json = node.properties_json,
            };
            const new_id = try db.upsertNode(node_for_db);
            if (new_id > 0) {
                try existing_nodes.put(node.id, new_id);
            }
        }

        for (self.edges.items) |edge| {
            const source_db_id = existing_nodes.get(edge.source_id) orelse edge.source_id;
            const target_db_id = existing_nodes.get(edge.target_id) orelse edge.target_id;
            if (source_db_id == 0 or target_db_id == 0) continue;

            const db_edge = store.Edge{
                .project = self.project,
                .source_id = source_db_id,
                .target_id = target_db_id,
                .edge_type = edge.edge_type,
                .properties_json = edge.properties_json,
            };
            _ = try db.upsertEdge(db_edge);
        }
    }

    fn freeNode(self: *GraphBuffer, node: BufferNode) void {
        self.allocator.free(node.label);
        self.allocator.free(node.name);
        self.allocator.free(node.qualified_name);
        self.allocator.free(node.file_path);
        self.allocator.free(node.properties_json);
    }
};

fn ensureGraphWithinLimits(
    project: []const u8,
    node_count: usize,
    edge_count: usize,
    limit: GraphSizeLimit,
) GraphLimitError!void {
    if (node_count > limit.max_nodes) {
        std.log.warn(
            "graph for {s} exceeds node limit: {} > {}",
            .{ project, node_count, limit.max_nodes },
        );
        return GraphLimitError.GraphTooLarge;
    }
    if (edge_count > limit.max_edges) {
        std.log.warn(
            "graph for {s} exceeds edge limit: {} > {}",
            .{ project, edge_count, limit.max_edges },
        );
        return GraphLimitError.GraphTooLarge;
    }
}

test "graph buffer basic ops" {
    var gb = GraphBuffer.init(std.testing.allocator, "test-project");
    defer gb.deinit();

    const id1 = try gb.upsertNode("Function", "foo", "test.foo", "src/main.zig", 1, 10);
    const id2 = try gb.upsertNode("Function", "bar", "test.bar", "src/main.zig", 12, 20);
    try std.testing.expect(id1 > 0);
    try std.testing.expect(id2 > 0);
    try std.testing.expect(id1 != id2);
    try std.testing.expectEqual(@as(usize, 2), gb.nodeCount());

    const id1_dup = try gb.upsertNode("Function", "foo", "test.foo", "src/main.zig", 1, 10);
    try std.testing.expectEqual(id1, id1_dup);
    try std.testing.expectEqual(@as(usize, 2), gb.nodeCount());
    if (gb.findNodeByQualifiedName("test.foo")) |n| {
        try std.testing.expectEqualStrings("foo", n.name);
    } else {
        return error.TestExpectedEqual;
    }

    const eid = try gb.insertEdge(id1, id2, "CALLS");
    try std.testing.expect(eid > 0);
    try std.testing.expectEqual(@as(usize, 1), gb.edgeCount());

    const dedup = gb.insertEdge(id1, id2, "CALLS") catch |err| blk: {
        try std.testing.expectEqual(GraphBufferError.DuplicateEdge, err);
        break :blk 0;
    };
    try std.testing.expectEqual(@as(i64, 0), dedup);
    try std.testing.expectEqual(@as(usize, 1), gb.edgeCount());

    const self_edge = try gb.insertEdge(id1, id1, "CALLS");
    try std.testing.expect(self_edge > 0);
    try std.testing.expectEqual(@as(usize, 2), gb.edgeCount());
}

test "graph buffer rejects oversized store loads before allocating" {
    var db = try store.Store.openMemory(std.testing.allocator);
    defer db.deinit();

    try db.upsertProject("test-project", "/tmp/test-project");
    _ = try db.upsertNode(.{
        .project = "test-project",
        .label = "Function",
        .name = "foo",
        .qualified_name = "test.foo",
        .file_path = "src/main.zig",
        .start_line = 1,
        .end_line = 2,
    });

    var gb = GraphBuffer.init(std.testing.allocator, "test-project");
    defer gb.deinit();

    try std.testing.expectError(
        error.GraphTooLarge,
        gb.loadFromStoreWithLimits(&db, .{
            .max_nodes = 0,
            .max_edges = 10,
        }),
    );
}

test "graph buffer rejects oversized dumps before writing" {
    var db = try store.Store.openMemory(std.testing.allocator);
    defer db.deinit();

    var gb = GraphBuffer.init(std.testing.allocator, "test-project");
    defer gb.deinit();

    _ = try gb.upsertNode("Function", "foo", "test.foo", "src/main.zig", 1, 2);
    _ = try gb.upsertNode("Function", "bar", "test.bar", "src/main.zig", 3, 4);

    try std.testing.expectError(
        error.GraphTooLarge,
        gb.dumpToStoreWithLimits(&db, .{
            .max_nodes = 1,
            .max_edges = 10,
        }),
    );
    try std.testing.expectEqual(@as(i32, 0), try db.countNodes("test-project"));
}

fn graphBufferNodeInsertAllocationFailureImpl(allocator: std.mem.Allocator) !void {
    var gb = GraphBuffer.init(allocator, "test-project");
    defer gb.deinit();

    const id = gb.upsertNode("Function", "foo", "test.foo", "src/main.zig", 1, 10) catch |err| {
        try std.testing.expectEqual(GraphBufferError.OutOfMemory, err);
        try std.testing.expectEqual(@as(i64, 1), gb.next_node_id);
        try std.testing.expectEqual(@as(usize, 0), gb.nodeCount());
        try std.testing.expect(gb.findNodeById(1) == null);
        return err;
    };

    try std.testing.expectEqual(@as(i64, 1), id);
    try std.testing.expectEqual(@as(i64, 2), gb.next_node_id);
    try std.testing.expectEqual(@as(usize, 1), gb.nodeCount());
}

test "graph buffer keeps node ids stable across allocation failures" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        graphBufferNodeInsertAllocationFailureImpl,
        .{},
    );
}

test "graph buffer findNodeById tolerates sparse ids" {
    var gb = GraphBuffer.init(std.testing.allocator, "test-project");
    defer gb.deinit();

    const id1 = try gb.upsertNode("Function", "foo", "test.foo", "src/main.zig", 1, 10);
    try std.testing.expectEqual(@as(i64, 1), id1);

    gb.next_node_id = 3;
    const id3 = try gb.upsertNode("Function", "bar", "test.bar", "src/main.zig", 12, 20);
    try std.testing.expectEqual(@as(i64, 3), id3);

    if (gb.findNodeById(id3)) |node| {
        try std.testing.expectEqualStrings("bar", node.name);
    } else {
        return error.TestExpectedEqual;
    }
}

test "graph buffer can load from store and purge a file slice" {
    var db = try store.Store.openMemory(std.testing.allocator);
    defer db.deinit();
    try db.upsertProject("demo", "/tmp/demo");

    const keep_id = try db.upsertNode(.{
        .project = "demo",
        .label = "Function",
        .name = "keep",
        .qualified_name = "demo.keep",
        .file_path = "keep.py",
    });
    const drop_id = try db.upsertNode(.{
        .project = "demo",
        .label = "Function",
        .name = "drop",
        .qualified_name = "demo.drop",
        .file_path = "drop.py",
    });
    _ = try db.upsertEdge(.{
        .project = "demo",
        .source_id = keep_id,
        .target_id = drop_id,
        .edge_type = "CALLS",
    });

    var gb = GraphBuffer.init(std.testing.allocator, "demo");
    defer gb.deinit();
    try gb.loadFromStore(&db);

    try std.testing.expectEqual(@as(usize, 2), gb.nodeCount());
    try std.testing.expectEqual(@as(usize, 1), gb.edgeCount());

    gb.deleteByFile("drop.py");

    try std.testing.expectEqual(@as(usize, 1), gb.nodeCount());
    try std.testing.expectEqual(@as(usize, 0), gb.edgeCount());
    try std.testing.expect(gb.findNodeByQualifiedName("demo.drop") == null);
    try std.testing.expect(gb.findNodeByQualifiedName("demo.keep") != null);
}

test "graph buffer prunes orphan folders after removing their last file" {
    var gb = GraphBuffer.init(std.testing.allocator, "demo");
    defer gb.deinit();

    const project_id = try gb.upsertNode("Project", "demo", "demo", "", 0, 0);
    const folder_id = try gb.upsertNode("Folder", "src", "demo:folder:src", "", 0, 0);
    const file_id = try gb.upsertNode("File", "lib.rs", "demo:file:src/lib.rs:rust", "src/lib.rs", 1, 1);

    _ = try gb.insertEdge(project_id, folder_id, "CONTAINS_FOLDER");
    _ = try gb.insertEdge(folder_id, file_id, "CONTAINS_FILE");

    gb.deleteByFile("src/lib.rs");

    try std.testing.expect(gb.findNodeByQualifiedName("demo") != null);
    try std.testing.expect(gb.findNodeByQualifiedName("demo:folder:src") == null);
    try std.testing.expect(gb.findNodeByQualifiedName("demo:file:src/lib.rs:rust") == null);
    try std.testing.expectEqual(@as(usize, 1), gb.nodeCount());
    try std.testing.expectEqual(@as(usize, 0), gb.edgeCount());
}

// mcp.zig — MCP (Model Context Protocol) JSON-RPC server.
//
// Implements a compact protocol surface sufficient for readiness checks:
//  * initialize
//  * tools/list
//  * tools/call
//
// Supported tools:
//  * index_repository
//  * search_graph
//  * query_graph
//  * trace_call_path
//  * list_projects

const std = @import("std");
const store = @import("store.zig");
const pipeline = @import("pipeline.zig");
const cypher = @import("cypher.zig");

const Store = store.Store;

const SupportedTool = enum {
    index_repository,
    search_graph,
    query_graph,
    trace_call_path,
    list_projects,
};

const RpcRequest = struct {
    jsonrpc: []const u8 = "2.0",
    id: ?std.json.Value = null,
    method: []const u8 = "",
    params: ?std.json.Value = null,
};

const RpcError = struct {
    code: i64,
    message: []const u8,
};

const ToolCallRequest = struct {
    name: []const u8 = "",
    arguments: ?std.json.Value = null,
};

const RpcErrorEnvelope = struct {
    code: i64,
    message: []const u8,
};

pub const Tool = enum {
    index_repository,
    search_graph,
    query_graph,
    trace_call_path,
    get_code_snippet,
    get_graph_schema,
    get_architecture,
    search_code,
    list_projects,
    delete_project,
    index_status,
    detect_changes,
    manage_adr,
    ingest_traces,
};

pub const McpServer = struct {
    allocator: std.mem.Allocator,
    db: *Store,

    pub fn init(allocator: std.mem.Allocator, db: *Store) McpServer {
        return .{ .allocator = allocator, .db = db };
    }

    pub fn deinit(self: *McpServer) void {
        _ = self;
    }

    pub fn handleRequest(self: *McpServer, request: []const u8) !?[]const u8 {
        return self.handleLine(request);
    }

    /// Run MCP over stdio line-delimited JSON.
    pub fn runFiles(self: *McpServer, stdin_file: std.fs.File, stdout_file: std.fs.File) !void {
        var line_buf: [64 * 1024]u8 = undefined;
        var out_buf: [64 * 1024]u8 = undefined;
        var reader = stdin_file.reader(&line_buf);
        var writer = stdout_file.writer(&out_buf);
        try self.run(&reader.interface, &writer.interface);
        try writer.interface.flush();
    }

    /// Test helper: line-delimited reader loop.
    pub fn run(self: *McpServer, reader: *std.Io.Reader, writer: *std.Io.Writer) !void {
        while (true) {
            const line = reader.takeDelimiterExclusive('\n') catch |err| {
                if (err == error.EndOfStream) return;
                return err;
            };
            const line_text = std.mem.trim(u8, line, " \r\n\t ");
            if (line_text.len == 0) continue;

            const response = try self.handleLine(line_text);
            if (response) |resp| {
                try writer.writeAll(resp);
                try writer.writeByte('\n');
            }
        }
    }

    fn handleLine(self: *McpServer, line: []const u8) !?[]const u8 {
        const request = std.json.parseFromSlice(RpcRequest, self.allocator, line, .{}) catch {
            return self.errorResponse(null, -32700, "Parse error");
        };
        defer request.deinit();

        if (!std.mem.eql(u8, request.value.jsonrpc, "2.0")) {
            return self.errorResponse(request.value.id, -32600, "Invalid JSON-RPC version");
        }
        if (request.value.method.len == 0) {
            return self.errorResponse(request.value.id, -32600, "Missing method");
        }

        if (std.mem.eql(u8, request.value.method, "initialize")) {
            return self.successResponse(
                request.value.id,
                "{\"protocolVersion\":\"2025-06-18\",\"capabilities\":{\"tools\":{}},\"serverInfo\":{\"name\":\"codebase-memory-zig\",\"version\":\"0.0.0\"}}",
            );
        }
        if (std.mem.eql(u8, request.value.method, "tools/list")) {
            const payload =
                \\{"tools":[
                \\{"name":"index_repository","description":"Index a repository into the graph store","inputSchema":{"type":"object","properties":{"project_path":{"type":"string"},"mode":{"type":"string","enum":["full","fast"]}}}},
                \\{"name":"search_graph","description":"Search nodes in the graph store","inputSchema":{"type":"object","properties":{"project":{"type":"string"},"label_pattern":{"type":"string"},"name_pattern":{"type":"string"},"qn_pattern":{"type":"string"},"file_pattern":{"type":"string"},"limit":{"type":"number"}}}},
                \\{"name":"query_graph","description":"Run a read-only Cypher-like query","inputSchema":{"type":"object","properties":{"project":{"type":"string"},"query":{"type":"string"},"max_rows":{"type":"number"}}}},
                \\{"name":"trace_call_path","description":"Trace CALLS edges between nodes","inputSchema":{"type":"object","properties":{"project":{"type":"string"},"start_node_qn":{"type":"string"},"direction":{"type":"string","enum":["in","out","both"]},"depth":{"type":"number"}}}},
                \\{"name":"list_projects","description":"List indexed projects","inputSchema":{"type":"object","properties":{}}}
                \\]}
            ;
            return self.successResponse(request.value.id, payload);
        }
        if (std.mem.eql(u8, request.value.method, "tools/call")) {
            if (request.value.params == null) {
                return self.errorResponse(request.value.id, -32602, "Missing params");
            }
            const call_request = try extractToolCall(self.allocator, request.value.params.?);
            return self.dispatchToolCall(request.value.id, call_request);
        }

        return self.errorResponse(request.value.id, -32601, "Method not found");
    }

    fn dispatchToolCall(self: *McpServer, request_id: ?std.json.Value, call: ToolCallRequest) !?[]const u8 {
        const tool = SupportedToolFromString(call.name) catch |err| {
            return switch (err) {
                error.UnsupportedTool => self.errorResponse(request_id, -32601, "Unknown tool"),
            };
        };

        return switch (tool) {
            .index_repository => self.handleIndexRepository(request_id, call.arguments orelse .null),
            .search_graph => self.handleSearchGraph(request_id, call.arguments orelse .null),
            .query_graph => self.handleQueryGraph(request_id, call.arguments orelse .null),
            .trace_call_path => self.handleTraceCallPath(request_id, call.arguments orelse .null),
            .list_projects => self.handleListProjects(request_id),
        };
    }

    fn handleIndexRepository(self: *McpServer, request_id: ?std.json.Value, args: std.json.Value) !?[]const u8 {
        const project_path = stringArg(args, "project_path") orelse return self.errorResponse(request_id, -32602, "Missing project_path");
        const mode_raw = stringArg(args, "mode") orelse "full";
        const mode = if (std.mem.eql(u8, mode_raw, "fast")) pipeline.IndexMode.fast else pipeline.IndexMode.full;

        const project_name = std.fs.path.basename(project_path);
        var p = pipeline.Pipeline.init(self.allocator, project_path, mode);
        defer p.deinit();
        try p.run(self.db);

        const node_count = try self.db.countNodes(project_name);
        const edge_count = try self.db.countEdges(project_name);
        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"project\":\"{s}\",\"mode\":\"{s}\",\"nodes\":{d},\"edges\":{d}}}",
            .{ project_name, if (mode == .fast) "fast" else "full", node_count, edge_count },
        );
        return self.successResponse(request_id, payload);
    }

    fn handleSearchGraph(self: *McpServer, request_id: ?std.json.Value, args: std.json.Value) !?[]const u8 {
        const project = stringArg(args, "project");
        const label_pattern = stringArg(args, "label_pattern");
        const name_pattern = stringArg(args, "name_pattern");
        const qn_pattern = stringArg(args, "qn_pattern");
        const file_pattern = stringArg(args, "file_pattern");
        const limit = intArg(args, "limit") orelse 100;

        const results = try self.db.searchNodes(.{
            .project = project orelse "",
            .label_pattern = label_pattern,
            .name_pattern = name_pattern,
            .qn_pattern = qn_pattern,
            .file_pattern = file_pattern,
            .limit = @intCast(limit),
        });
        defer self.db.freeNodes(results);

        var payload = std.ArrayList(u8).empty;
        try payload.appendSlice(self.allocator, "{\"nodes\":[");
        for (results, 0..) |node, idx| {
            if (idx > 0) try payload.append(self.allocator, ',');
            try payload.writer(self.allocator).print(
                "{{\"id\":{d},\"label\":\"{s}\",\"name\":\"{s}\",\"qualified_name\":\"{s}\",\"file_path\":\"{s}\"}}",
                .{
                    node.id,
                    node.label,
                    node.name,
                    node.qualified_name,
                    node.file_path,
                },
            );
        }
        try payload.appendSlice(self.allocator, "]}");
        return self.successResponse(request_id, try payload.toOwnedSlice(self.allocator));
    }

    fn handleQueryGraph(self: *McpServer, request_id: ?std.json.Value, args: std.json.Value) !?[]const u8 {
        const project = stringArg(args, "project");
        const query = stringArg(args, "query") orelse return self.errorResponse(request_id, -32602, "Missing query");
        const max_rows = if (intArg(args, "max_rows")) |v| v else 50;

        const result = try cypher.execute(self.allocator, self.db, query, project, @intCast(max_rows));
        defer {
            for (result.columns) |col| self.allocator.free(col);
            self.allocator.free(result.columns);
            for (result.rows) |row| {
                for (row) |cell| self.allocator.free(cell);
                self.allocator.free(row);
            }
            self.allocator.free(result.rows);
            if (result.err) |e| self.allocator.free(e);
        }

        var payload = std.ArrayList(u8).empty;
        try payload.appendSlice(self.allocator, "{\"columns\":[");
        for (result.columns, 0..) |col, idx| {
            if (idx > 0) try payload.append(self.allocator, ',');
            try payload.appendSlice(self.allocator, "\"");
            try payload.appendSlice(self.allocator, col);
            try payload.appendSlice(self.allocator, "\"");
        }
        try payload.appendSlice(self.allocator, "],\"rows\":[");
        for (result.rows, 0..) |row, row_idx| {
            if (row_idx > 0) try payload.append(self.allocator, ',');
            try payload.appendSlice(self.allocator, "[");
            for (row, 0..) |cell, cell_idx| {
                if (cell_idx > 0) try payload.append(self.allocator, ',');
                try payload.appendSlice(self.allocator, "\"");
                try payload.appendSlice(self.allocator, cell);
                try payload.appendSlice(self.allocator, "\"");
            }
            try payload.appendSlice(self.allocator, "]");
        }
        try payload.appendSlice(self.allocator, "]}");
        return self.successResponse(request_id, try payload.toOwnedSlice(self.allocator));
    }

    fn handleTraceCallPath(self: *McpServer, request_id: ?std.json.Value, args: std.json.Value) !?[]const u8 {
        const project = stringArg(args, "project") orelse return self.errorResponse(request_id, -32602, "Missing project");
        const start_node_qn = stringArg(args, "start_node_qn") orelse return self.errorResponse(request_id, -32602, "Missing start_node_qn");
        const direction = stringArg(args, "direction") orelse "out";
        const max_depth = if (intArg(args, "depth")) |d| d else 6;

        const start = try self.db.findNodeByQualifiedName(project, start_node_qn) orelse
            return self.errorResponse(request_id, -32602, "Unknown start_node_qn");
        defer self.db.allocator.free(start.project);
        defer self.db.allocator.free(start.label);
        defer self.db.allocator.free(start.name);
        defer self.db.allocator.free(start.qualified_name);
        defer self.db.allocator.free(start.file_path);
        defer self.db.allocator.free(start.properties_json);

        var frontier = std.ArrayList(struct { id: i64, depth: u32 }).empty;
        defer frontier.deinit(self.allocator);
        var visited = std.AutoHashMap(i64, void).init(self.allocator);
        defer visited.deinit();
        var edges = std.ArrayList(store.Edge).empty;
        defer self.db.freeEdges(edges.items);
        defer edges.deinit(self.allocator);

        try frontier.append(self.allocator, .{ .id = start.id, .depth = 0 });
        try visited.put(start.id, {});

        while (frontier.items.len > 0) {
            const next = frontier.orderedRemove(0);
            const next_depth = next.depth + 1;
            if (next_depth > max_depth) break;

            if (std.mem.eql(u8, direction, "out") or std.mem.eql(u8, direction, "both")) {
                const outgoing = try self.db.findEdgesBySource(project, next.id, null);
                defer self.db.freeEdges(outgoing);
                for (outgoing) |edge| {
                    if (!visited.contains(edge.target_id)) {
                        try visited.put(edge.target_id, {});
                        try frontier.append(self.allocator, .{ .id = edge.target_id, .depth = next_depth });
                        try edges.append(self.allocator, edge);
                    }
                }
            }

            if (std.mem.eql(u8, direction, "in") or std.mem.eql(u8, direction, "both")) {
                const incoming = try self.db.findEdgesByTarget(project, next.id, null);
                defer self.db.freeEdges(incoming);
                for (incoming) |edge| {
                    if (!visited.contains(edge.source_id)) {
                        try visited.put(edge.source_id, {});
                        try frontier.append(self.allocator, .{ .id = edge.source_id, .depth = next_depth });
                        try edges.append(self.allocator, edge);
                    }
                }
            }
        }

        var payload = std.ArrayList(u8).empty;
        try payload.appendSlice(self.allocator, "{\"edges\":[");
        for (edges.items, 0..) |edge, idx| {
            if (idx > 0) try payload.append(self.allocator, ',');
            try payload.writer(self.allocator).print(
                "{{\"source\":{d},\"target\":{d},\"type\":\"{s}\"}}",
                .{ edge.source_id, edge.target_id, edge.edge_type },
            );
        }
        try payload.appendSlice(self.allocator, "]}");
        return self.successResponse(request_id, try payload.toOwnedSlice(self.allocator));
    }

    fn handleListProjects(self: *McpServer, request_id: ?std.json.Value) !?[]const u8 {
        const projects = try self.db.listProjects();
        defer self.db.freeProjects(projects);

        var payload = std.ArrayList(u8).empty;
        try payload.appendSlice(self.allocator, "[");
        for (projects, 0..) |p, idx| {
            if (idx > 0) try payload.append(self.allocator, ',');
            const node_count = try self.db.countNodes(p.name);
            const edge_count = try self.db.countEdges(p.name);
            const row = try std.fmt.allocPrint(
                self.allocator,
                "{{\"name\":\"{s}\",\"indexed_at\":\"{s}\",\"root_path\":\"{s}\",\"nodes\":{d},\"edges\":{d}}}",
                .{ p.name, p.indexed_at, p.root_path, node_count, edge_count },
            );
            defer self.allocator.free(row);
            try payload.appendSlice(self.allocator, row);
        }
        try payload.appendSlice(self.allocator, "]");
        return self.successResponse(request_id, try payload.toOwnedSlice(self.allocator));
    }

    fn successResponse(self: *McpServer, request_id: ?std.json.Value, payload: []const u8) !?[]const u8 {
        if (request_id == null) return null;
        const id = try jsonValueToString(self.allocator, request_id.?);
        var response = std.ArrayList(u8).empty;
        try response.appendSlice(self.allocator, "{\"jsonrpc\":\"2.0\",\"id\":");
        try response.appendSlice(self.allocator, id);
        try response.appendSlice(self.allocator, ",\"result\":");
        try response.appendSlice(self.allocator, payload);
        try response.appendSlice(self.allocator, "}");
        return try response.toOwnedSlice(self.allocator);
    }

    fn errorResponse(self: *McpServer, request_id: ?std.json.Value, code: i64, message: []const u8) !?[]const u8 {
        const request_id_text = if (request_id) |idv| try jsonValueToString(self.allocator, idv) else "null";
        const message_text = try jsonValueToString(self.allocator, .{ .string = message });
        defer self.allocator.free(message_text);
        var response = std.ArrayList(u8).empty;
        try response.appendSlice(self.allocator, "{\"jsonrpc\":\"2.0\",\"id\":");
        try response.appendSlice(self.allocator, request_id_text);
        try response.appendSlice(self.allocator, ",\"error\":{\"code\":");
        try response.writer(self.allocator).print("{d}", .{code});
        try response.appendSlice(self.allocator, ",\"message\":");
        try response.appendSlice(self.allocator, message_text);
        try response.appendSlice(self.allocator, "}}");
        return try response.toOwnedSlice(self.allocator);
    }
};

fn SupportedToolFromString(name: []const u8) error{UnsupportedTool}!SupportedTool {
    if (std.mem.eql(u8, name, "index_repository")) return .index_repository;
    if (std.mem.eql(u8, name, "search_graph")) return .search_graph;
    if (std.mem.eql(u8, name, "query_graph")) return .query_graph;
    if (std.mem.eql(u8, name, "trace_call_path")) return .trace_call_path;
    if (std.mem.eql(u8, name, "list_projects")) return .list_projects;
    return error.UnsupportedTool;
}

fn extractToolCall(allocator: std.mem.Allocator, value: std.json.Value) !ToolCallRequest {
    _ = allocator;
    if (value != .object) return error.UnexpectedType;
    const name = value.object.get("name") orelse return error.MissingName;
    const args = if (value.object.get("arguments")) |arguments| arguments else null;
    return .{
        .name = switch (name) {
            .string => |v| v,
            else => return error.InvalidName,
        },
        .arguments = args,
    };
}

fn stringArg(value: std.json.Value, key: []const u8) ?[]const u8 {
    if (value != .object) return null;
    const child = value.object.get(key) orelse return null;
    return switch (child) {
        .string => |s| s,
        else => null,
    };
}

fn intArg(value: std.json.Value, key: []const u8) ?u32 {
    if (value != .object) return null;
    const child = value.object.get(key) orelse return null;
    return switch (child) {
        .integer => |v| @as(u32, @intCast(v)),
        else => null,
    };
}

fn jsonValueToString(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    if (value == .string) return try std.fmt.allocPrint(allocator, "\"{s}\"", .{value.string});
    if (value == .null) return try allocator.dupe(u8, "null");
    if (value == .integer) return try std.fmt.allocPrint(allocator, "{d}", .{value.integer});
    if (value == .bool) return try allocator.dupe(u8, if (value.bool) "true" else "false");

    var out = std.ArrayList(u8).empty;
    try out.writer(allocator).print("{f}", .{std.json.fmt(value, .{})});
    return out.toOwnedSlice(allocator);
}

test "mcp init/deinit" {
    var s = try store.Store.openMemory(std.testing.allocator);
    defer s.deinit();
    var srv = McpServer.init(std.testing.allocator, &s);
    defer srv.deinit();
}

test "tool enum coverage" {
    try std.testing.expectEqual(SupportedTool.index_repository, try SupportedToolFromString("index_repository"));
    try std.testing.expectError(error.UnsupportedTool, SupportedToolFromString("missing"));
}

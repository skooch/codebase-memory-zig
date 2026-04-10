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
    get_code_snippet,
    get_graph_schema,
    list_projects,
    delete_project,
    index_status,
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
                defer self.allocator.free(resp);
                try writer.writeAll(resp);
                try writer.writeByte('\n');
                try writer.flush();
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
                \\{"name":"get_code_snippet","description":"Read source code for a function/class/symbol. IMPORTANT: First call search_graph to find the exact qualified_name, then pass it here. This is a read tool, not a search tool. Accepts full qualified_name (exact match) or short function name (returns suggestions if ambiguous).","inputSchema":{"type":"object","properties":{"qualified_name":{"type":"string","description":"Full qualified_name from search_graph, or short function name"},"project":{"type":"string"},"include_neighbors":{"type":"boolean","default":false}},"required":["qualified_name","project"]}},
                \\{"name":"get_graph_schema","description":"Get the schema of the knowledge graph (node labels, edge types)","inputSchema":{"type":"object","properties":{"project":{"type":"string"}},"required":["project"]}},
                \\{"name":"list_projects","description":"List indexed projects","inputSchema":{"type":"object","properties":{}}},
                \\{"name":"delete_project","description":"Delete a project from the index","inputSchema":{"type":"object","properties":{"project":{"type":"string"}},"required":["project"]}},
                \\{"name":"index_status","description":"Get the indexing status of a project","inputSchema":{"type":"object","properties":{"project":{"type":"string"}}}}
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
            .get_code_snippet => self.handleGetCodeSnippet(request_id, call.arguments orelse .null),
            .get_graph_schema => self.handleGetGraphSchema(request_id, call.arguments orelse .null),
            .list_projects => self.handleListProjects(request_id),
            .delete_project => self.handleDeleteProject(request_id, call.arguments orelse .null),
            .index_status => self.handleIndexStatus(request_id, call.arguments orelse .null),
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
        defer self.allocator.free(payload);
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
        const owned_payload = try payload.toOwnedSlice(self.allocator);
        defer self.allocator.free(owned_payload);
        return self.successResponse(request_id, owned_payload);
    }

    fn handleQueryGraph(self: *McpServer, request_id: ?std.json.Value, args: std.json.Value) !?[]const u8 {
        const project = stringArg(args, "project");
        const query = stringArg(args, "query") orelse return self.errorResponse(request_id, -32602, "Missing query");
        const max_rows = if (intArg(args, "max_rows")) |v| v else 50;

        const result = try cypher.execute(self.allocator, self.db, query, project, @intCast(max_rows));
        defer cypher.freeResult(self.allocator, result);
        if (result.err) |err_text| {
            return self.errorResponse(request_id, -32602, err_text);
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
        const owned_payload = try payload.toOwnedSlice(self.allocator);
        defer self.allocator.free(owned_payload);
        return self.successResponse(request_id, owned_payload);
    }

    fn handleTraceCallPath(self: *McpServer, request_id: ?std.json.Value, args: std.json.Value) !?[]const u8 {
        const project = stringArg(args, "project") orelse return self.errorResponse(request_id, -32602, "Missing project");
        const start_node_qn = stringArg(args, "start_node_qn") orelse return self.errorResponse(request_id, -32602, "Missing start_node_qn");
        const direction = stringArg(args, "direction") orelse "out";
        const max_depth = if (intArg(args, "depth")) |d| d else 6;

        const start = try self.db.findNodeByQualifiedName(project, start_node_qn) orelse
            return self.errorResponse(request_id, -32602, "Unknown start_node_qn");
        defer freeOwnedNode(self.allocator, start);

        const traversal_direction = parseTraversalDirection(direction) orelse
            return self.errorResponse(request_id, -32602, "Invalid direction");
        const edges = try self.db.traverseEdgesBreadthFirst(project, start.id, traversal_direction, max_depth, null);
        defer self.db.freeTraversalEdges(edges);

        var payload = std.ArrayList(u8).empty;
        try payload.appendSlice(self.allocator, "{\"edges\":[");
        for (edges, 0..) |edge, idx| {
            if (idx > 0) try payload.append(self.allocator, ',');
            const source = (try self.db.findNodeById(project, edge.source_id)) orelse
                return self.errorResponse(request_id, -32603, "Trace edge source missing");
            defer freeOwnedNode(self.allocator, source);
            const target = (try self.db.findNodeById(project, edge.target_id)) orelse
                return self.errorResponse(request_id, -32603, "Trace edge target missing");
            defer freeOwnedNode(self.allocator, target);
            try payload.writer(self.allocator).print(
                "{{\"source\":\"{s}\",\"target\":\"{s}\",\"type\":\"{s}\"}}",
                .{ source.qualified_name, target.qualified_name, edge.edge_type },
            );
        }
        try payload.appendSlice(self.allocator, "]}");
        const owned_payload = try payload.toOwnedSlice(self.allocator);
        defer self.allocator.free(owned_payload);
        return self.successResponse(request_id, owned_payload);
    }

    fn handleListProjects(self: *McpServer, request_id: ?std.json.Value) !?[]const u8 {
        const projects = try self.db.listProjects();
        defer self.db.freeProjects(projects);

        var payload = std.ArrayList(u8).empty;
        try payload.appendSlice(self.allocator, "{\"projects\":[");
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
        try payload.appendSlice(self.allocator, "]}");
        const owned_payload = try payload.toOwnedSlice(self.allocator);
        defer self.allocator.free(owned_payload);
        return self.successResponse(request_id, owned_payload);
    }

    fn handleGetGraphSchema(self: *McpServer, request_id: ?std.json.Value, args: std.json.Value) !?[]const u8 {
        const project = stringArg(args, "project") orelse return self.errorResponse(request_id, -32602, "Missing project");
        const status = try self.db.getProjectStatus(project);
        defer self.db.freeProjectStatus(status);

        var payload = std.ArrayList(u8).empty;
        try payload.writer(self.allocator).print(
            "{{\"project\":\"{s}\",\"status\":\"{s}\",\"nodes\":{d},\"edges\":{d},\"node_labels\":[",
            .{ status.project, projectStatusText(status.status), status.nodes, status.edges },
        );

        if (status.status != .not_found) {
            const schema = try self.db.getSchema(project);
            defer self.db.freeSchema(schema);

            for (schema.labels, 0..) |label, idx| {
                if (idx > 0) try payload.append(self.allocator, ',');
                try payload.writer(self.allocator).print(
                    "{{\"label\":\"{s}\",\"count\":{d}}}",
                    .{ label.label, label.count },
                );
            }
            try payload.appendSlice(self.allocator, "],\"edge_types\":[");
            for (schema.edge_types, 0..) |edge_type, idx| {
                if (idx > 0) try payload.append(self.allocator, ',');
                try payload.writer(self.allocator).print(
                    "{{\"type\":\"{s}\",\"count\":{d}}}",
                    .{ edge_type.edge_type, edge_type.count },
                );
            }
            try payload.appendSlice(self.allocator, "],\"languages\":[");
            for (schema.languages, 0..) |language, idx| {
                if (idx > 0) try payload.append(self.allocator, ',');
                try payload.writer(self.allocator).print(
                    "{{\"language\":\"{s}\",\"count\":{d}}}",
                    .{ language.language, language.count },
                );
            }
        } else {
            try payload.appendSlice(self.allocator, "],\"edge_types\":[],\"languages\":[");
        }
        try payload.appendSlice(self.allocator, "]}");

        const owned_payload = try payload.toOwnedSlice(self.allocator);
        defer self.allocator.free(owned_payload);
        return self.successResponse(request_id, owned_payload);
    }

    fn handleGetCodeSnippet(self: *McpServer, request_id: ?std.json.Value, args: std.json.Value) !?[]const u8 {
        const project = stringArg(args, "project") orelse return self.errorResponse(request_id, -32602, "Missing project");
        const qualified_name = stringArg(args, "qualified_name") orelse return self.errorResponse(request_id, -32602, "Missing qualified_name");
        const include_neighbors = boolArg(args, "include_neighbors") orelse false;

        const project_status = try self.db.getProjectStatus(project);
        defer self.db.freeProjectStatus(project_status);
        if (project_status.status == .not_found) {
            return self.errorResponse(request_id, -32602, "Unknown project");
        }

        if (try self.db.findNodeByQualifiedName(project, qualified_name)) |node| {
            defer self.db.freeNode(node);
            return self.respondWithSnippet(request_id, project, project_status.root_path, node, include_neighbors, null);
        }

        const suffix_matches = try self.db.findNodesByQualifiedNameSuffix(project, qualified_name, 10);
        defer self.db.freeNodes(suffix_matches);
        if (suffix_matches.len == 1) {
            return self.respondWithSnippet(
                request_id,
                project,
                project_status.root_path,
                suffix_matches[0],
                include_neighbors,
                "suffix",
            );
        }
        if (suffix_matches.len > 1) {
            return self.respondWithSnippetSuggestions(request_id, qualified_name, suffix_matches);
        }

        return self.errorResponse(
            request_id,
            -32602,
            "symbol not found. Use search_graph(name_pattern=\"...\") first to discover the exact qualified_name, then pass it to get_code_snippet.",
        );
    }

    fn handleDeleteProject(self: *McpServer, request_id: ?std.json.Value, args: std.json.Value) !?[]const u8 {
        const project = stringArg(args, "project") orelse return self.errorResponse(request_id, -32602, "Missing project");
        const status = try self.db.getProjectStatus(project);
        defer self.db.freeProjectStatus(status);

        if (status.status != .not_found) {
            try self.db.deleteProject(project);
        }

        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"project\":\"{s}\",\"status\":\"{s}\"}}",
            .{ project, if (status.status == .not_found) "not_found" else "deleted" },
        );
        defer self.allocator.free(payload);
        return self.successResponse(request_id, payload);
    }

    fn handleIndexStatus(self: *McpServer, request_id: ?std.json.Value, args: std.json.Value) !?[]const u8 {
        const status = try self.db.getProjectStatus(stringArg(args, "project"));
        defer self.db.freeProjectStatus(status);

        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"project\":\"{s}\",\"status\":\"{s}\",\"nodes\":{d},\"edges\":{d},\"indexed_at\":\"{s}\",\"root_path\":\"{s}\"}}",
            .{
                status.project,
                projectStatusText(status.status),
                status.nodes,
                status.edges,
                status.indexed_at,
                status.root_path,
            },
        );
        defer self.allocator.free(payload);
        return self.successResponse(request_id, payload);
    }

    fn respondWithSnippet(
        self: *McpServer,
        request_id: ?std.json.Value,
        project: []const u8,
        root_path: []const u8,
        node: store.Node,
        include_neighbors: bool,
        match_method: ?[]const u8,
    ) !?[]const u8 {
        const line_range = snippetLineRange(node.start_line, node.end_line);
        const source_path = try resolveSnippetPath(self.allocator, root_path, node.file_path);
        defer if (source_path) |path| self.allocator.free(path);

        const source = if (source_path) |path|
            readFileLines(self.allocator, path, line_range.start_line, line_range.end_line) catch null
        else
            null;
        defer if (source) |snippet| self.allocator.free(snippet);

        const degree = try self.db.getNodeDegree(project, node.id);
        const caller_names = if (include_neighbors) try self.collectNeighborNames(project, node.id, .inbound, 10) else null;
        defer if (caller_names) |names| freeOwnedStrings(self.allocator, names);
        const callee_names = if (include_neighbors) try self.collectNeighborNames(project, node.id, .outbound, 10) else null;
        defer if (callee_names) |names| freeOwnedStrings(self.allocator, names);

        var payload = std.ArrayList(u8).empty;
        try payload.appendSlice(self.allocator, "{");
        try appendJsonStringField(&payload, self.allocator, "name", node.name, true);
        try appendJsonStringField(&payload, self.allocator, "qualified_name", node.qualified_name, false);
        try appendJsonStringField(&payload, self.allocator, "label", node.label, false);
        try appendJsonStringField(
            &payload,
            self.allocator,
            "file_path",
            if (source_path) |path| path else node.file_path,
            false,
        );
        try appendJsonIntField(&payload, self.allocator, "start_line", line_range.start_line, false);
        try appendJsonIntField(&payload, self.allocator, "end_line", line_range.end_line, false);
        try appendJsonStringField(
            &payload,
            self.allocator,
            "source",
            if (source) |snippet| snippet else "(source not available)",
            false,
        );
        if (match_method) |method| {
            try appendJsonStringField(&payload, self.allocator, "match_method", method, false);
        }
        try appendPropertyFields(&payload, self.allocator, node.properties_json);
        try appendJsonIntField(&payload, self.allocator, "callers", degree.callers, false);
        try appendJsonIntField(&payload, self.allocator, "callees", degree.callees, false);
        if (caller_names) |names| {
            try appendJsonStringArrayField(&payload, self.allocator, "caller_names", names, false);
        }
        if (callee_names) |names| {
            try appendJsonStringArrayField(&payload, self.allocator, "callee_names", names, false);
        }
        try payload.appendSlice(self.allocator, "}");

        const owned_payload = try payload.toOwnedSlice(self.allocator);
        defer self.allocator.free(owned_payload);
        return self.successResponse(request_id, owned_payload);
    }

    fn respondWithSnippetSuggestions(
        self: *McpServer,
        request_id: ?std.json.Value,
        input: []const u8,
        suggestions: []const store.Node,
    ) !?[]const u8 {
        var payload = std.ArrayList(u8).empty;
        try payload.appendSlice(self.allocator, "{");
        try appendJsonStringField(&payload, self.allocator, "status", "ambiguous", true);
        const message = try std.fmt.allocPrint(
            self.allocator,
            "{d} matches for \"{s}\". Pick a qualified_name from suggestions below, or use search_graph(name_pattern=\"...\") to narrow results.",
            .{ suggestions.len, input },
        );
        defer self.allocator.free(message);
        try appendJsonStringField(&payload, self.allocator, "message", message, false);
        try payload.appendSlice(self.allocator, ",\"suggestions\":[");
        for (suggestions, 0..) |node, idx| {
            if (idx > 0) try payload.append(self.allocator, ',');
            try payload.appendSlice(self.allocator, "{");
            try appendJsonStringField(&payload, self.allocator, "qualified_name", node.qualified_name, true);
            try appendJsonStringField(&payload, self.allocator, "name", node.name, false);
            try appendJsonStringField(&payload, self.allocator, "label", node.label, false);
            try appendJsonStringField(&payload, self.allocator, "file_path", node.file_path, false);
            try payload.appendSlice(self.allocator, "}");
        }
        try payload.appendSlice(self.allocator, "]}");

        const owned_payload = try payload.toOwnedSlice(self.allocator);
        defer self.allocator.free(owned_payload);
        return self.successResponse(request_id, owned_payload);
    }

    fn collectNeighborNames(
        self: *McpServer,
        project: []const u8,
        node_id: i64,
        direction: store.TraversalDirection,
        limit: usize,
    ) ![][]u8 {
        const edges = switch (direction) {
            .inbound => try self.db.findEdgesByTarget(project, node_id, null),
            .outbound => try self.db.findEdgesBySource(project, node_id, null),
            .both => unreachable,
        };
        defer self.db.freeEdges(edges);

        var names = std.ArrayList([]u8).empty;
        errdefer {
            for (names.items) |name| {
                self.allocator.free(name);
            }
            names.deinit(self.allocator);
        }
        var seen = std.StringHashMap(void).init(self.allocator);
        defer {
            var it = seen.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            seen.deinit();
        }

        for (edges) |edge| {
            if (names.items.len >= limit) break;
            const neighbor_id = switch (direction) {
                .inbound => edge.source_id,
                .outbound => edge.target_id,
                .both => unreachable,
            };
            const neighbor = (try self.db.findNodeById(project, neighbor_id)) orelse continue;
            defer self.db.freeNode(neighbor);

            if (seen.contains(neighbor.name)) continue;
            const key = try self.allocator.dupe(u8, neighbor.name);
            errdefer self.allocator.free(key);
            try seen.put(key, {});
            try names.append(self.allocator, try self.allocator.dupe(u8, neighbor.name));
        }

        return names.toOwnedSlice(self.allocator);
    }

    fn successResponse(self: *McpServer, request_id: ?std.json.Value, payload: []const u8) !?[]const u8 {
        if (request_id == null) return null;
        const id = try jsonValueToString(self.allocator, request_id.?);
        defer self.allocator.free(id);
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
        defer if (request_id != null) self.allocator.free(request_id_text);
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

fn freeOwnedNode(allocator: std.mem.Allocator, node: store.Node) void {
    allocator.free(node.project);
    allocator.free(node.label);
    allocator.free(node.name);
    allocator.free(node.qualified_name);
    allocator.free(node.file_path);
    allocator.free(node.properties_json);
}

fn parseTraversalDirection(direction: []const u8) ?store.TraversalDirection {
    if (std.mem.eql(u8, direction, "out") or std.mem.eql(u8, direction, "outbound")) {
        return .outbound;
    }
    if (std.mem.eql(u8, direction, "in") or std.mem.eql(u8, direction, "inbound")) {
        return .inbound;
    }
    if (std.mem.eql(u8, direction, "both")) {
        return .both;
    }
    return null;
}

fn projectStatusText(status: store.ProjectStatus.Status) []const u8 {
    return switch (status) {
        .ready => "ready",
        .empty => "empty",
        .no_project => "no_project",
        .not_found => "not_found",
    };
}

fn SupportedToolFromString(name: []const u8) error{UnsupportedTool}!SupportedTool {
    if (std.mem.eql(u8, name, "index_repository")) return .index_repository;
    if (std.mem.eql(u8, name, "search_graph")) return .search_graph;
    if (std.mem.eql(u8, name, "query_graph")) return .query_graph;
    if (std.mem.eql(u8, name, "trace_call_path")) return .trace_call_path;
    if (std.mem.eql(u8, name, "get_code_snippet")) return .get_code_snippet;
    if (std.mem.eql(u8, name, "get_graph_schema")) return .get_graph_schema;
    if (std.mem.eql(u8, name, "list_projects")) return .list_projects;
    if (std.mem.eql(u8, name, "delete_project")) return .delete_project;
    if (std.mem.eql(u8, name, "index_status")) return .index_status;
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

fn boolArg(value: std.json.Value, key: []const u8) ?bool {
    if (value != .object) return null;
    const child = value.object.get(key) orelse return null;
    return switch (child) {
        .bool => |v| v,
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

const SnippetLineRange = struct {
    start_line: i32,
    end_line: i32,
};

fn snippetLineRange(start_line: i32, end_line: i32) SnippetLineRange {
    const normalized_start = if (start_line > 0) start_line else 1;
    const normalized_end = if (end_line >= normalized_start) end_line else normalized_start + 20;
    return .{
        .start_line = normalized_start,
        .end_line = normalized_end,
    };
}

fn resolveSnippetPath(allocator: std.mem.Allocator, root_path: []const u8, file_path: []const u8) !?[]u8 {
    if (root_path.len == 0 or file_path.len == 0) return null;

    const resolved = try std.fs.path.resolve(allocator, &.{ root_path, file_path });
    defer allocator.free(resolved);

    const real_root = std.fs.cwd().realpathAlloc(allocator, root_path) catch return null;
    defer allocator.free(real_root);
    const real_file = std.fs.cwd().realpathAlloc(allocator, resolved) catch return null;
    errdefer allocator.free(real_file);

    if (!isContainedPath(real_root, real_file)) {
        allocator.free(real_file);
        return null;
    }
    return real_file;
}

fn isContainedPath(root_path: []const u8, candidate_path: []const u8) bool {
    if (!std.mem.startsWith(u8, candidate_path, root_path)) return false;
    if (candidate_path.len == root_path.len) return true;
    return candidate_path[root_path.len] == std.fs.path.sep;
}

fn readFileLines(
    allocator: std.mem.Allocator,
    absolute_path: []const u8,
    start_line: i32,
    end_line: i32,
) ![]u8 {
    const file = try std.fs.cwd().openFile(absolute_path, .{});
    defer file.close();
    const contents = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(contents);

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    var line_no: i32 = 1;
    var start_idx: usize = 0;
    while (start_idx <= contents.len) {
        const end_idx = std.mem.indexOfScalarPos(u8, contents, start_idx, '\n') orelse contents.len;
        const line = contents[start_idx..end_idx];
        if (line_no >= start_line and line_no <= end_line) {
            try out.appendSlice(allocator, line);
            if (end_idx < contents.len and line_no < end_line) {
                try out.append(allocator, '\n');
            }
        } else if (line_no > end_line) {
            break;
        }
        if (end_idx == contents.len) break;
        start_idx = end_idx + 1;
        line_no += 1;
    }

    return out.toOwnedSlice(allocator);
}

fn appendJsonStringField(
    payload: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    key: []const u8,
    value: []const u8,
    is_first: bool,
) !void {
    if (!is_first) try payload.append(allocator, ',');
    try appendJsonString(payload, allocator, key);
    try payload.append(allocator, ':');
    try appendJsonString(payload, allocator, value);
}

fn appendJsonIntField(
    payload: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    key: []const u8,
    value: i32,
    is_first: bool,
) !void {
    if (!is_first) try payload.append(allocator, ',');
    try appendJsonString(payload, allocator, key);
    try payload.append(allocator, ':');
    try payload.writer(allocator).print("{d}", .{value});
}

fn appendJsonBoolField(
    payload: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    key: []const u8,
    value: bool,
    is_first: bool,
) !void {
    if (!is_first) try payload.append(allocator, ',');
    try appendJsonString(payload, allocator, key);
    try payload.append(allocator, ':');
    try payload.appendSlice(allocator, if (value) "true" else "false");
}

fn appendJsonStringArrayField(
    payload: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    key: []const u8,
    values: [][]u8,
    is_first: bool,
) !void {
    if (!is_first) try payload.append(allocator, ',');
    try appendJsonString(payload, allocator, key);
    try payload.appendSlice(allocator, ":[");
    for (values, 0..) |value, idx| {
        if (idx > 0) try payload.append(allocator, ',');
        try appendJsonString(payload, allocator, value);
    }
    try payload.append(allocator, ']');
}

fn appendPropertyFields(
    payload: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    properties_json: []const u8,
) !void {
    if (properties_json.len == 0 or std.mem.eql(u8, properties_json, "{}")) return;

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, properties_json, .{}) catch return;
    defer parsed.deinit();
    if (parsed.value != .object) return;

    var it = parsed.value.object.iterator();
    while (it.next()) |entry| {
        try payload.append(allocator, ',');
        try appendJsonString(payload, allocator, entry.key_ptr.*);
        try payload.append(allocator, ':');
        try payload.writer(allocator).print("{f}", .{std.json.fmt(entry.value_ptr.*, .{})});
    }
}

fn appendJsonString(payload: *std.ArrayList(u8), allocator: std.mem.Allocator, value: []const u8) !void {
    try payload.writer(allocator).print("{f}", .{std.json.fmt(value, .{})});
}

fn freeOwnedStrings(allocator: std.mem.Allocator, values: [][]u8) void {
    for (values) |value| {
        allocator.free(value);
    }
    allocator.free(values);
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

test "list_projects returns projects wrapper" {
    var s = try store.Store.openMemory(std.testing.allocator);
    defer s.deinit();
    try s.upsertProject("demo", "/tmp/demo");

    var srv = McpServer.init(std.testing.allocator, &s);
    defer srv.deinit();

    const response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_projects","arguments":{}}}
    )).?;
    defer std.testing.allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, response, .{});
    defer parsed.deinit();

    const projects = parsed.value.object.get("result").?.object.get("projects").?.array;
    try std.testing.expectEqual(@as(usize, 1), projects.items.len);
    try std.testing.expectEqualStrings("demo", projects.items[0].object.get("name").?.string);
}

test "trace_call_path returns qualified names" {
    var s = try store.Store.openMemory(std.testing.allocator);
    defer s.deinit();
    try s.upsertProject("demo", "/tmp/demo");
    const source_id = try s.upsertNode(.{
        .project = "demo",
        .label = "Function",
        .name = "start",
        .qualified_name = "demo:start",
        .file_path = "main.py",
    });
    const target_id = try s.upsertNode(.{
        .project = "demo",
        .label = "Function",
        .name = "finish",
        .qualified_name = "demo:finish",
        .file_path = "main.py",
    });
    _ = try s.upsertEdge(.{
        .project = "demo",
        .source_id = source_id,
        .target_id = target_id,
        .edge_type = "CALLS",
    });

    var srv = McpServer.init(std.testing.allocator, &s);
    defer srv.deinit();

    const response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"trace_call_path","arguments":{"project":"demo","start_node_qn":"demo:start","direction":"outbound","depth":2}}}
    )).?;
    defer std.testing.allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, response, .{});
    defer parsed.deinit();

    const edges = parsed.value.object.get("result").?.object.get("edges").?.array;
    try std.testing.expectEqual(@as(usize, 1), edges.items.len);
    try std.testing.expectEqualStrings("demo:start", edges.items[0].object.get("source").?.string);
    try std.testing.expectEqualStrings("demo:finish", edges.items[0].object.get("target").?.string);
}

test "query_graph returns MCP error for unsupported query" {
    var s = try store.Store.openMemory(std.testing.allocator);
    defer s.deinit();

    var srv = McpServer.init(std.testing.allocator, &s);
    defer srv.deinit();

    const response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"query_graph","arguments":{"project":"demo","query":"RETURN 1"}}}
    )).?;
    defer std.testing.allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, response, .{});
    defer parsed.deinit();

    try std.testing.expect(parsed.value.object.get("error") != null);
    const error_obj = parsed.value.object.get("error").?.object;
    try std.testing.expectEqual(@as(i64, -32602), error_obj.get("code").?.integer);
    try std.testing.expectEqualStrings("unsupported query", error_obj.get("message").?.string);
}

test "get_graph_schema returns schema summary for indexed project" {
    var s = try store.Store.openMemory(std.testing.allocator);
    defer s.deinit();
    try s.upsertProject("demo", "/tmp/demo");
    const file_id = try s.upsertNode(.{
        .project = "demo",
        .label = "File",
        .name = "main",
        .qualified_name = "demo:main",
        .file_path = "main.py",
    });
    const fn_id = try s.upsertNode(.{
        .project = "demo",
        .label = "Function",
        .name = "run",
        .qualified_name = "demo:run",
        .file_path = "main.py",
    });
    _ = try s.upsertEdge(.{
        .project = "demo",
        .source_id = file_id,
        .target_id = fn_id,
        .edge_type = "CONTAINS",
    });

    var srv = McpServer.init(std.testing.allocator, &s);
    defer srv.deinit();
    const response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_graph_schema","arguments":{"project":"demo"}}}
    )).?;
    defer std.testing.allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, response, .{});
    defer parsed.deinit();

    const result = parsed.value.object.get("result").?.object;
    try std.testing.expectEqualStrings("demo", result.get("project").?.string);
    try std.testing.expectEqualStrings("ready", result.get("status").?.string);
    try std.testing.expect(result.get("node_labels").?.array.items.len >= 2);
    try std.testing.expect(result.get("edge_types").?.array.items.len >= 1);
}

test "index_status and delete_project expose project lifecycle" {
    var s = try store.Store.openMemory(std.testing.allocator);
    defer s.deinit();
    try s.upsertProject("demo", "/tmp/demo");
    _ = try s.upsertNode(.{
        .project = "demo",
        .label = "Function",
        .name = "run",
        .qualified_name = "demo:run",
        .file_path = "main.py",
    });

    var srv = McpServer.init(std.testing.allocator, &s);
    defer srv.deinit();

    const status_response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"index_status","arguments":{"project":"demo"}}}
    )).?;
    defer std.testing.allocator.free(status_response);

    const status_parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, status_response, .{});
    defer status_parsed.deinit();
    const status_result = status_parsed.value.object.get("result").?.object;
    try std.testing.expectEqualStrings("ready", status_result.get("status").?.string);
    try std.testing.expectEqual(@as(i64, 1), status_result.get("nodes").?.integer);

    const delete_response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"delete_project","arguments":{"project":"demo"}}}
    )).?;
    defer std.testing.allocator.free(delete_response);

    const delete_parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, delete_response, .{});
    defer delete_parsed.deinit();
    const delete_result = delete_parsed.value.object.get("result").?.object;
    try std.testing.expectEqualStrings("deleted", delete_result.get("status").?.string);

    const missing_response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"index_status","arguments":{"project":"demo"}}}
    )).?;
    defer std.testing.allocator.free(missing_response);

    const missing_parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, missing_response, .{});
    defer missing_parsed.deinit();
    const missing_result = missing_parsed.value.object.get("result").?.object;
    try std.testing.expectEqualStrings("not_found", missing_result.get("status").?.string);
}

test "get_code_snippet returns source, match metadata, and suggestions" {
    const allocator = std.testing.allocator;
    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(allocator, "/tmp/cbm-snippet-test-{x}", .{project_id});
    defer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};
    const src_dir = try std.fs.path.join(allocator, &.{ project_dir, "src" });
    defer allocator.free(src_dir);
    try std.fs.cwd().makePath(src_dir);

    {
        const main_path = try std.fs.path.join(allocator, &.{ project_dir, "src", "main.py" });
        defer allocator.free(main_path);
        var main_file = try std.fs.cwd().createFile(main_path, .{});
        defer main_file.close();
        try main_file.writeAll(
            \\def helper(x):
            \\    return x
            \\
            \\def run():
            \\    return helper(1)
            \\
        );

        const worker_path = try std.fs.path.join(allocator, &.{ project_dir, "src", "worker.py" });
        defer allocator.free(worker_path);
        var worker_file = try std.fs.cwd().createFile(worker_path, .{});
        defer worker_file.close();
        try worker_file.writeAll(
            \\def run():
            \\    return 42
            \\
        );
    }

    var s = try store.Store.openMemory(allocator);
    defer s.deinit();
    try s.upsertProject("demo", project_dir);

    const helper_id = try s.upsertNode(.{
        .project = "demo",
        .label = "Function",
        .name = "helper",
        .qualified_name = "demo.src.main.helper",
        .file_path = "src/main.py",
        .start_line = 1,
        .end_line = 2,
        .properties_json = "{\"signature\":\"def helper(x):\",\"is_exported\":true}",
    });
    const run_id = try s.upsertNode(.{
        .project = "demo",
        .label = "Function",
        .name = "run",
        .qualified_name = "demo.src.main.run",
        .file_path = "src/main.py",
        .start_line = 4,
        .end_line = 5,
    });
    _ = try s.upsertNode(.{
        .project = "demo",
        .label = "Function",
        .name = "run",
        .qualified_name = "demo.src.worker.run",
        .file_path = "src/worker.py",
        .start_line = 1,
        .end_line = 2,
    });
    _ = try s.upsertEdge(.{
        .project = "demo",
        .source_id = run_id,
        .target_id = helper_id,
        .edge_type = "CALLS",
    });

    var srv = McpServer.init(allocator, &s);
    defer srv.deinit();

    const exact_response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"get_code_snippet","arguments":{"project":"demo","qualified_name":"demo.src.main.helper","include_neighbors":true}}}
    )).?;
    defer allocator.free(exact_response);

    const exact_parsed = try std.json.parseFromSlice(std.json.Value, allocator, exact_response, .{});
    defer exact_parsed.deinit();
    const exact_result = exact_parsed.value.object.get("result").?.object;
    try std.testing.expectEqualStrings("helper", exact_result.get("name").?.string);
    try std.testing.expect(exact_result.get("source") != null);
    try std.testing.expect(exact_result.get("match_method") == null);
    try std.testing.expectEqual(@as(i64, 1), exact_result.get("callers").?.integer);
    try std.testing.expectEqual(@as(i64, 0), exact_result.get("callees").?.integer);
    try std.testing.expectEqualStrings("def helper(x):", exact_result.get("signature").?.string);
    try std.testing.expectEqual(true, exact_result.get("is_exported").?.bool);
    try std.testing.expect(exact_result.get("caller_names") != null);

    const suffix_response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"get_code_snippet","arguments":{"project":"demo","qualified_name":"main.run"}}}
    )).?;
    defer allocator.free(suffix_response);

    const suffix_parsed = try std.json.parseFromSlice(std.json.Value, allocator, suffix_response, .{});
    defer suffix_parsed.deinit();
    const suffix_result = suffix_parsed.value.object.get("result").?.object;
    try std.testing.expectEqualStrings("suffix", suffix_result.get("match_method").?.string);

    const ambiguous_response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"get_code_snippet","arguments":{"project":"demo","qualified_name":"run"}}}
    )).?;
    defer allocator.free(ambiguous_response);

    const ambiguous_parsed = try std.json.parseFromSlice(std.json.Value, allocator, ambiguous_response, .{});
    defer ambiguous_parsed.deinit();
    const ambiguous_result = ambiguous_parsed.value.object.get("result").?.object;
    try std.testing.expectEqualStrings("ambiguous", ambiguous_result.get("status").?.string);
    try std.testing.expect(ambiguous_result.get("suggestions").?.array.items.len >= 2);
}

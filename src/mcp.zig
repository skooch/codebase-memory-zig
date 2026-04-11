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
//  * get_code_snippet
//  * get_graph_schema
//  * get_architecture
//  * search_code
//  * list_projects
//  * delete_project
//  * index_status
//  * detect_changes

const std = @import("std");
const adr = @import("adr.zig");
const discover = @import("discover.zig");
const store = @import("store.zig");
const pipeline = @import("pipeline.zig");
const runtime_lifecycle = @import("runtime_lifecycle.zig");
const cypher = @import("cypher.zig");
const watcher = @import("watcher.zig");

const Store = store.Store;

const SupportedTool = enum {
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
    watcher_ref: ?*watcher.Watcher = null,
    index_guard: ?*std.atomic.Value(bool) = null,
    lifecycle_ref: ?*runtime_lifecycle.RuntimeLifecycle = null,

    pub fn init(allocator: std.mem.Allocator, db: *Store) McpServer {
        return .{ .allocator = allocator, .db = db };
    }

    pub fn deinit(self: *McpServer) void {
        _ = self;
    }

    pub fn setWatcher(self: *McpServer, watcher_ref: *watcher.Watcher) void {
        self.watcher_ref = watcher_ref;
    }

    pub fn setIndexGuard(self: *McpServer, index_guard: *std.atomic.Value(bool)) void {
        self.index_guard = index_guard;
    }

    pub fn setRuntimeLifecycle(self: *McpServer, lifecycle_ref: *runtime_lifecycle.RuntimeLifecycle) void {
        self.lifecycle_ref = lifecycle_ref;
    }

    pub fn handleRequest(self: *McpServer, request: []const u8) !?[]const u8 {
        return self.handleLine(request);
    }

    /// Run MCP over stdio line-delimited JSON.
    pub fn runFiles(self: *McpServer, stdin_file: std.fs.File, stdout_file: std.fs.File) !void {
        var read_buf: [4096]u8 = undefined;
        var pending = std.ArrayList(u8).empty;
        defer pending.deinit(self.allocator);

        while (true) {
            const read_len = try stdin_file.read(&read_buf);
            if (read_len == 0) {
                try self.handlePendingFileLine(&pending, stdout_file);
                return;
            }

            for (read_buf[0..read_len]) |byte| {
                if (byte == '\n') {
                    try self.handlePendingFileLine(&pending, stdout_file);
                    continue;
                }
                try pending.append(self.allocator, byte);
            }
        }
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

    fn handlePendingFileLine(self: *McpServer, pending: *std.ArrayList(u8), stdout_file: std.fs.File) !void {
        defer pending.clearRetainingCapacity();

        const line_text = std.mem.trim(u8, pending.items, " \r\n\t ");
        if (line_text.len == 0) return;

        const response = try self.handleLine(line_text);
        if (response) |resp| {
            defer self.allocator.free(resp);
            try stdout_file.writeAll(resp);
            try stdout_file.writeAll("\n");
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
            if (self.lifecycle_ref) |lifecycle| lifecycle.startUpdateCheck();
            return self.successResponse(
                request.value.id,
                "{\"protocolVersion\":\"2025-06-18\",\"capabilities\":{\"tools\":{}},\"serverInfo\":{\"name\":\"codebase-memory-zig\",\"version\":\"0.0.0\"}}",
            );
        }
        if (std.mem.eql(u8, request.value.method, "tools/list")) {
            const payload =
                \\{"tools":[
                \\{"name":"index_repository","description":"Index a repository into the graph store","inputSchema":{"type":"object","properties":{"project_path":{"type":"string"},"mode":{"type":"string","enum":["full","fast"]}}}},
                \\{"name":"search_graph","description":"Structured graph search with filtering, degree-aware ranking, pagination, and optional connected-node context","inputSchema":{"type":"object","properties":{"project":{"type":"string"},"label":{"type":"string"},"label_pattern":{"type":"string"},"name_pattern":{"type":"string"},"qn_pattern":{"type":"string"},"file_pattern":{"type":"string"},"relationship":{"type":"string"},"exclude_entry_points":{"type":"boolean"},"include_connected":{"type":"boolean"},"limit":{"type":"number"},"offset":{"type":"number"},"min_degree":{"type":"number"},"max_degree":{"type":"number"},"sort_by":{"type":"string"},"sort_direction":{"type":"string"}}}},
                \\{"name":"query_graph","description":"Run a read-only Cypher-like query","inputSchema":{"type":"object","properties":{"project":{"type":"string"},"query":{"type":"string"},"max_rows":{"type":"number"}}}},
                \\{"name":"trace_call_path","description":"Trace CALLS edges between nodes","inputSchema":{"type":"object","properties":{"project":{"type":"string"},"start_node_qn":{"type":"string"},"direction":{"type":"string","enum":["in","out","both"]},"depth":{"type":"number"}}}},
                \\{"name":"get_code_snippet","description":"Read source code for a function/class/symbol. IMPORTANT: First call search_graph to find the exact qualified_name, then pass it here. This is a read tool, not a search tool. Accepts full qualified_name (exact match) or short function name (returns suggestions if ambiguous).","inputSchema":{"type":"object","properties":{"qualified_name":{"type":"string","description":"Full qualified_name from search_graph, or short function name"},"project":{"type":"string"},"include_neighbors":{"type":"boolean","default":false}},"required":["qualified_name","project"]}},
                \\{"name":"get_graph_schema","description":"Get the schema of the knowledge graph (node labels, edge types)","inputSchema":{"type":"object","properties":{"project":{"type":"string"}},"required":["project"]}},
                \\{"name":"get_architecture","description":"High-level project summary: structure, dependencies, languages, hotspots, entry points, and routes","inputSchema":{"type":"object","properties":{"project":{"type":"string"},"aspects":{"type":"array","items":{"type":"string"}}},"required":["project"]}},
                \\{"name":"search_code","description":"Text search across indexed project files with compact, full, or files-only output","inputSchema":{"type":"object","properties":{"project":{"type":"string"},"pattern":{"type":"string"},"mode":{"type":"string","enum":["compact","full","files"]},"file_pattern":{"type":"string"},"path_filter":{"type":"string"},"limit":{"type":"number"},"context":{"type":"number"},"regex":{"type":"boolean"}},"required":["project","pattern"]}},
                \\{"name":"list_projects","description":"List indexed projects","inputSchema":{"type":"object","properties":{}}},
                \\{"name":"delete_project","description":"Delete a project from the index","inputSchema":{"type":"object","properties":{"project":{"type":"string"}},"required":["project"]}},
                \\{"name":"index_status","description":"Get the indexing status of a project","inputSchema":{"type":"object","properties":{"project":{"type":"string"}}}},
                \\{"name":"detect_changes","description":"Map local git changes to affected symbols and nearby blast radius","inputSchema":{"type":"object","properties":{"project":{"type":"string"},"base_branch":{"type":"string"},"scope":{"type":"string"},"depth":{"type":"number"}},"required":["project"]}},
                \\{"name":"manage_adr","description":"Create or update Architecture Decision Records","inputSchema":{"type":"object","properties":{"project":{"type":"string"},"mode":{"type":"string","enum":["get","update","sections"]},"content":{"type":"string"},"sections":{"type":"array","items":{"type":"string"}}},"required":["project"]}}
                \\]}
            ;
            const response = try self.successResponse(request.value.id, payload);
            if (response) |owned_response| {
                if (self.lifecycle_ref) |lifecycle| {
                    const updated_response = try lifecycle.injectUpdateNotice(owned_response);
                    return updated_response;
                }
                return owned_response;
            }
            return null;
        }
        if (std.mem.eql(u8, request.value.method, "tools/call")) {
            if (request.value.params == null) {
                return self.errorResponse(request.value.id, -32602, "Missing params");
            }
            const call_request = try extractToolCall(self.allocator, request.value.params.?);
            const response = try self.dispatchToolCall(request.value.id, call_request);
            if (response) |owned_response| {
                if (self.lifecycle_ref) |lifecycle| {
                    const updated_response = try lifecycle.injectUpdateNotice(owned_response);
                    return updated_response;
                }
                return owned_response;
            }
            return null;
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
            .get_architecture => self.handleGetArchitecture(request_id, call.arguments orelse .null),
            .search_code => self.handleSearchCode(request_id, call.arguments orelse .null),
            .list_projects => self.handleListProjects(request_id),
            .delete_project => self.handleDeleteProject(request_id, call.arguments orelse .null),
            .index_status => self.handleIndexStatus(request_id, call.arguments orelse .null),
            .detect_changes => self.handleDetectChanges(request_id, call.arguments orelse .null),
            .manage_adr => self.handleManageAdr(request_id, call.arguments orelse .null),
        };
    }

    fn handleIndexRepository(self: *McpServer, request_id: ?std.json.Value, args: std.json.Value) !?[]const u8 {
        const project_path = stringArg(args, "project_path") orelse return self.errorResponse(request_id, -32602, "Missing project_path");
        const mode_raw = stringArg(args, "mode") orelse "full";
        const mode = if (std.mem.eql(u8, mode_raw, "fast")) pipeline.IndexMode.fast else pipeline.IndexMode.full;

        const normalized_path = std.fs.cwd().realpathAlloc(self.allocator, project_path) catch try self.allocator.dupe(u8, project_path);
        defer self.allocator.free(normalized_path);
        const project_name = std.fs.path.basename(normalized_path);
        if (self.index_guard) |index_guard| {
            if (index_guard.cmpxchgStrong(false, true, .acq_rel, .acquire) != null) {
                return self.errorResponse(request_id, -32603, "Indexing already in progress");
            }
        }
        defer if (self.index_guard) |index_guard| {
            index_guard.store(false, .release);
        };

        var p = pipeline.Pipeline.init(self.allocator, normalized_path, mode);
        defer p.deinit();
        try p.run(self.db);
        if (self.watcher_ref) |watcher_ref| {
            try watcher_ref.watch(project_name, normalized_path);
        }

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
        const project = stringArg(args, "project") orelse "";
        const label_pattern = stringArg(args, "label_pattern") orelse stringArg(args, "label");
        const relationship = stringArg(args, "relationship");
        const include_connected = boolArg(args, "include_connected") orelse false;
        const sort_by = stringArg(args, "sort_by");
        const sort_direction = stringArg(args, "sort_direction");

        const page = try self.db.searchGraph(.{
            .project = project,
            .label_pattern = label_pattern,
            .name_pattern = stringArg(args, "name_pattern"),
            .qn_pattern = stringArg(args, "qn_pattern"),
            .file_pattern = stringArg(args, "file_pattern"),
            .relationship = relationship,
            .min_degree = signedIntArg(args, "min_degree"),
            .max_degree = signedIntArg(args, "max_degree"),
            .exclude_entry_points = boolArg(args, "exclude_entry_points") orelse false,
            .limit = intArg(args, "limit") orelse 100,
            .offset = intArg(args, "offset") orelse 0,
            .sort_field = parseGraphSortField(sort_by),
            .descending = sort_direction != null and std.ascii.eqlIgnoreCase(sort_direction.?, "desc"),
        });
        defer self.db.freeGraphSearchPage(page);

        var payload = std.ArrayList(u8).empty;
        try payload.writer(self.allocator).print(
            "{{\"total\":{d},\"results\":[",
            .{page.total},
        );
        for (page.hits, 0..) |hit, idx| {
            if (idx > 0) try payload.append(self.allocator, ',');
            try payload.appendSlice(self.allocator, "{");
            try appendJsonStringField(&payload, self.allocator, "name", hit.node.name, true);
            try appendJsonStringField(&payload, self.allocator, "qualified_name", hit.node.qualified_name, false);
            try appendJsonStringField(&payload, self.allocator, "label", hit.node.label, false);
            try appendJsonStringField(&payload, self.allocator, "file_path", hit.node.file_path, false);
            try appendJsonIntField(&payload, self.allocator, "in_degree", hit.in_degree, false);
            try appendJsonIntField(&payload, self.allocator, "out_degree", hit.out_degree, false);
            if (include_connected) {
                try appendConnectedSummary(&payload, self, project, hit.node.id, relationship);
            }
            try payload.appendSlice(self.allocator, "}");
        }
        try payload.writer(self.allocator).print(
            "],\"has_more\":{s}}}",
            .{if (page.total > page.hits.len + (intArg(args, "offset") orelse 0)) "true" else "false"},
        );
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
        try payload.writer(self.allocator).print("],\"total\":{d}}}", .{result.rows.len});
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
            if (self.watcher_ref) |watcher_ref| {
                watcher_ref.unwatch(project);
            }
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

    fn handleGetArchitecture(self: *McpServer, request_id: ?std.json.Value, args: std.json.Value) !?[]const u8 {
        const project = stringArg(args, "project") orelse return self.errorResponse(request_id, -32602, "Missing project");
        const status = try self.db.getProjectStatus(project);
        defer self.db.freeProjectStatus(status);
        if (status.status == .not_found) {
            return self.errorResponse(request_id, -32602, "Unknown project");
        }

        const schema = try self.db.getSchema(project);
        defer self.db.freeSchema(schema);
        const files = try self.db.listProjectFiles(project);
        defer self.db.freePaths(files);

        var payload = std.ArrayList(u8).empty;
        try payload.appendSlice(self.allocator, "{");
        try appendJsonStringField(&payload, self.allocator, "project", project, true);
        try appendJsonIntField(&payload, self.allocator, "total_nodes", status.nodes, false);
        try appendJsonIntField(&payload, self.allocator, "total_edges", status.edges, false);

        if (aspectWanted(args, "structure")) {
            try appendSchemaCountsField(&payload, self.allocator, "node_labels", schema.labels);
        }
        if (aspectWanted(args, "dependencies")) {
            try appendEdgeTypeCountsField(&payload, self.allocator, "edge_types", schema.edge_types);
        }
        if (explicitArchitectureAspectWanted(args, "languages")) {
            try appendLanguageSummaryField(&payload, self.allocator, files);
        }
        if (explicitArchitectureAspectWanted(args, "packages")) {
            try appendDirectorySummaryField(&payload, self.allocator, files);
        }
        if (explicitArchitectureAspectWanted(args, "hotspots")) {
            try appendHotspotsField(&payload, self, project, 10);
        }
        if (explicitArchitectureAspectWanted(args, "entry_points")) {
            try appendEntryPointsField(&payload, self, project, 15);
        }
        if (explicitArchitectureAspectWanted(args, "route_summaries")) {
            try appendRoutesField(&payload, self, project);
        }

        try payload.appendSlice(self.allocator, "}");
        const owned_payload = try payload.toOwnedSlice(self.allocator);
        defer self.allocator.free(owned_payload);
        return self.successResponse(request_id, owned_payload);
    }

    fn handleSearchCode(self: *McpServer, request_id: ?std.json.Value, args: std.json.Value) !?[]const u8 {
        const project = stringArg(args, "project") orelse return self.errorResponse(request_id, -32602, "Missing project");
        const pattern = stringArg(args, "pattern") orelse return self.errorResponse(request_id, -32602, "Missing pattern");
        const status = try self.db.getProjectStatus(project);
        defer self.db.freeProjectStatus(status);
        if (status.status == .not_found) {
            return self.errorResponse(request_id, -32602, "Unknown project");
        }

        const mode = parseSearchCodeMode(stringArg(args, "mode"));
        const file_pattern = stringArg(args, "file_pattern");
        const path_filter = stringArg(args, "path_filter");
        const regex = boolArg(args, "regex") orelse false;
        const limit = intArg(args, "limit") orelse 25;
        const context = intArg(args, "context") orelse 0;

        const hits = try collectSearchCodeHits(
            self.allocator,
            self.db,
            project,
            status.root_path,
            pattern,
            mode,
            file_pattern,
            path_filter,
            regex,
            limit,
            context,
        );
        defer freeCodeSearchHits(self.allocator, hits);

        var payload = std.ArrayList(u8).empty;
        try payload.appendSlice(self.allocator, "{");
        try appendJsonStringField(&payload, self.allocator, "mode", searchCodeModeText(mode), true);
        try appendJsonIntField(&payload, self.allocator, "total", @intCast(hits.len), false);
        try payload.appendSlice(self.allocator, ",\"results\":[");
        for (hits, 0..) |hit, idx| {
            if (idx > 0) try payload.append(self.allocator, ',');
            try payload.appendSlice(self.allocator, "{");
            try appendJsonStringField(&payload, self.allocator, "file", hit.file_path, true);
            try appendJsonStringField(&payload, self.allocator, "file_path", hit.file_path, false);
            if (mode != .files) {
                try appendJsonIntField(&payload, self.allocator, "line", @intCast(hit.line), false);
                if (hit.start_line > 0) try appendJsonIntField(&payload, self.allocator, "start_line", hit.start_line, false);
                if (hit.end_line > 0) try appendJsonIntField(&payload, self.allocator, "end_line", hit.end_line, false);
                if (mode == .full or hit.name == null) {
                    try appendJsonStringField(&payload, self.allocator, "snippet", hit.snippet, false);
                }
                if (hit.name) |name| {
                    try appendJsonStringField(&payload, self.allocator, "node", name, false);
                    try appendJsonStringField(&payload, self.allocator, "name", name, false);
                }
                if (hit.label) |label| try appendJsonStringField(&payload, self.allocator, "label", label, false);
                if (hit.qualified_name) |qn| try appendJsonStringField(&payload, self.allocator, "qualified_name", qn, false);
                try appendJsonIntField(&payload, self.allocator, "in_degree", hit.in_degree, false);
                try appendJsonIntField(&payload, self.allocator, "out_degree", hit.out_degree, false);
                try payload.appendSlice(self.allocator, ",\"match_lines\":[");
                for (hit.match_lines, 0..) |match_line, match_idx| {
                    if (match_idx > 0) try payload.append(self.allocator, ',');
                    try payload.writer(self.allocator).print("{d}", .{match_line});
                }
                try payload.append(self.allocator, ']');
            }
            try payload.appendSlice(self.allocator, "}");
        }
        const dedup_ratio = try dedupRatioText(self.allocator, hits);
        defer self.allocator.free(dedup_ratio);
        try payload.writer(self.allocator).print(
            "],\"has_more\":false,\"total_results\":{d},\"raw_match_count\":0,\"total_grep_matches\":{d},\"dedup_ratio\":{f}}}",
            .{
                hits.len,
                totalSearchMatchLines(hits),
                std.json.fmt(dedup_ratio, .{}),
            },
        );

        const owned_payload = try payload.toOwnedSlice(self.allocator);
        defer self.allocator.free(owned_payload);
        return self.successResponse(request_id, owned_payload);
    }

    fn handleDetectChanges(self: *McpServer, request_id: ?std.json.Value, args: std.json.Value) !?[]const u8 {
        const project = stringArg(args, "project") orelse return self.errorResponse(request_id, -32602, "Missing project");
        const status = try self.db.getProjectStatus(project);
        defer self.db.freeProjectStatus(status);
        if (status.status == .not_found) {
            return self.errorResponse(request_id, -32602, "Unknown project");
        }

        const base_branch = stringArg(args, "base_branch") orelse "main";
        const scope = stringArg(args, "scope");
        const depth = intArg(args, "depth") orelse 3;

        const want_symbols = scope == null or
            std.mem.eql(u8, scope.?, "symbols") or
            std.mem.eql(u8, scope.?, "impact") or
            std.mem.eql(u8, scope.?, "full");
        const include_blast_radius = scope != null and std.mem.eql(u8, scope.?, "full");

        const changed_files = try collectChangedFiles(self.allocator, status.root_path, base_branch);
        defer freeOwnedStrings(self.allocator, changed_files);
        const impacted = if (want_symbols)
            try collectImpactedSymbols(self.allocator, self.db, project, changed_files)
        else
            &[_]ChangeSymbol{};
        defer if (want_symbols) freeChangeSymbols(self.allocator, impacted);
        const blast_radius = if (include_blast_radius)
            try collectBlastRadius(self.allocator, self.db, project, impacted, depth)
        else
            &[_]BlastItem{};
        defer if (include_blast_radius) freeBlastItems(self.allocator, blast_radius);

        var payload = std.ArrayList(u8).empty;
        try payload.appendSlice(self.allocator, "{");
        try appendJsonStringField(&payload, self.allocator, "project", project, true);
        try appendJsonStringField(&payload, self.allocator, "base_branch", base_branch, false);
        if (scope) |scope_value| try appendJsonStringField(&payload, self.allocator, "scope", scope_value, false);
        try appendJsonIntField(&payload, self.allocator, "depth", @intCast(depth), false);
        try appendJsonStringArrayField(&payload, self.allocator, "changed_files", changed_files, false);
        try appendJsonIntField(&payload, self.allocator, "changed_count", @intCast(changed_files.len), false);
        try payload.appendSlice(self.allocator, ",\"impacted_symbols\":[");
        for (impacted, 0..) |item, idx| {
            if (idx > 0) try payload.append(self.allocator, ',');
            try payload.appendSlice(self.allocator, "{");
            try appendJsonStringField(&payload, self.allocator, "name", item.name, true);
            try appendJsonStringField(&payload, self.allocator, "label", item.label, false);
            try appendJsonStringField(&payload, self.allocator, "file", item.file_path, false);
            try appendJsonStringField(&payload, self.allocator, "file_path", item.file_path, false);
            try appendJsonStringField(&payload, self.allocator, "qualified_name", item.qualified_name, false);
            try payload.appendSlice(self.allocator, "}");
        }
        if (include_blast_radius) {
            try payload.appendSlice(self.allocator, "],\"blast_radius\":[");
            for (blast_radius, 0..) |item, idx| {
                if (idx > 0) try payload.append(self.allocator, ',');
                try payload.appendSlice(self.allocator, "{");
                try appendJsonStringField(&payload, self.allocator, "name", item.name, true);
                try appendJsonStringField(&payload, self.allocator, "qualified_name", item.qualified_name, false);
                try appendJsonStringField(&payload, self.allocator, "file_path", item.file_path, false);
                try appendJsonIntField(&payload, self.allocator, "hop", @intCast(item.hop), false);
                try appendJsonStringField(&payload, self.allocator, "risk", riskLabel(item.hop), false);
                try payload.appendSlice(self.allocator, "}");
            }
        }
        try payload.appendSlice(self.allocator, "]}");

        const owned_payload = try payload.toOwnedSlice(self.allocator);
        defer self.allocator.free(owned_payload);
        return self.successResponse(request_id, owned_payload);
    }

    fn handleManageAdr(self: *McpServer, request_id: ?std.json.Value, args: std.json.Value) !?[]const u8 {
        const project = stringArg(args, "project") orelse return self.errorResponse(request_id, -32602, "Missing project");
        const mode = stringArg(args, "mode") orelse "get";
        const content = stringArg(args, "content");

        const project_entry = try self.db.getProject(project);
        if (project_entry == null) {
            return self.errorResponse(request_id, -32602, "project not found");
        }
        self.db.freeProject(project_entry.?);

        if (std.mem.eql(u8, mode, "update") and content != null) {
            const decoded_content = try decodeEscapedJsonString(self.allocator, content.?);
            defer self.allocator.free(decoded_content);
            try self.db.upsertAdr(project, decoded_content);
            return self.successResponse(request_id, "{\"status\":\"updated\"}");
        }

        if (std.mem.eql(u8, mode, "sections")) {
            const maybe_adr = try self.db.getAdr(project);
            defer if (maybe_adr) |entry| self.db.freeAdr(entry);

            const sections = if (maybe_adr) |entry| try adr.listMarkdownSections(self.allocator, entry.content) else try self.allocator.alloc([]u8, 0);
            defer freeOwnedStrings(self.allocator, sections);

            var payload = std.ArrayList(u8).empty;
            try payload.appendSlice(self.allocator, "{\"sections\":[");
            for (sections, 0..) |section, idx| {
                if (idx > 0) try payload.append(self.allocator, ',');
                try appendJsonString(&payload, self.allocator, section);
            }
            try payload.appendSlice(self.allocator, "]}");

            const owned_payload = try payload.toOwnedSlice(self.allocator);
            defer self.allocator.free(owned_payload);
            return self.successResponse(request_id, owned_payload);
        }

        const maybe_adr = try self.db.getAdr(project);
        defer if (maybe_adr) |entry| self.db.freeAdr(entry);
        if (maybe_adr == null) {
            return self.successResponse(
                request_id,
                "{\"content\":\"\",\"status\":\"no_adr\",\"adr_hint\":\"No ADR yet. Create one with manage_adr(mode='update', content='## PURPOSE\\n...\\n\\n## STACK\\n...\\n\\n## ARCHITECTURE\\n...\\n\\n## PATTERNS\\n...\\n\\n## TRADEOFFS\\n...\\n\\n## PHILOSOPHY\\n...'). Sections: PURPOSE, STACK, ARCHITECTURE, PATTERNS, TRADEOFFS, PHILOSOPHY.\"}",
            );
        }

        const entry = maybe_adr.?;
        var payload = std.ArrayList(u8).empty;
        try payload.appendSlice(self.allocator, "{");
        try appendJsonStringField(&payload, self.allocator, "content", entry.content, true);
        try appendJsonStringField(&payload, self.allocator, "created_at", entry.created_at, false);
        try appendJsonStringField(&payload, self.allocator, "updated_at", entry.updated_at, false);
        try payload.appendSlice(self.allocator, "}");

        const owned_payload = try payload.toOwnedSlice(self.allocator);
        defer self.allocator.free(owned_payload);
        return self.successResponse(request_id, owned_payload);
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

const SearchCodeMode = enum { compact, full, files };

const CodeSearchHit = struct {
    file_path: []u8,
    line: u32 = 0,
    snippet: []u8,
    name: ?[]u8 = null,
    label: ?[]u8 = null,
    qualified_name: ?[]u8 = null,
    start_line: i32 = 0,
    end_line: i32 = 0,
    in_degree: i32 = 0,
    out_degree: i32 = 0,
    match_lines: []u32 = &.{},
};

const ChangeSymbol = struct {
    id: i64,
    name: []u8,
    label: []u8,
    file_path: []u8,
    qualified_name: []u8,
};

const BlastItem = struct {
    name: []u8,
    qualified_name: []u8,
    file_path: []u8,
    hop: u32,
};

fn parseGraphSortField(raw: ?[]const u8) store.GraphSortField {
    const text = raw orelse return .name;
    if (std.ascii.eqlIgnoreCase(text, "label")) return .label;
    if (std.ascii.eqlIgnoreCase(text, "file_path")) return .file_path;
    if (std.ascii.eqlIgnoreCase(text, "in_degree")) return .in_degree;
    if (std.ascii.eqlIgnoreCase(text, "out_degree")) return .out_degree;
    if (std.ascii.eqlIgnoreCase(text, "degree") or std.ascii.eqlIgnoreCase(text, "total_degree")) return .total_degree;
    return .name;
}

fn parseSearchCodeMode(raw: ?[]const u8) SearchCodeMode {
    const text = raw orelse return .compact;
    if (std.ascii.eqlIgnoreCase(text, "full")) return .full;
    if (std.ascii.eqlIgnoreCase(text, "files")) return .files;
    return .compact;
}

fn searchCodeModeText(mode: SearchCodeMode) []const u8 {
    return switch (mode) {
        .compact => "compact",
        .full => "full",
        .files => "files",
    };
}

fn signedIntArg(value: std.json.Value, key: []const u8) ?i32 {
    if (value != .object) return null;
    const child = value.object.get(key) orelse return null;
    return switch (child) {
        .integer => |v| @intCast(v),
        else => null,
    };
}

fn aspectWanted(args: std.json.Value, aspect: []const u8) bool {
    if (args != .object) return true;
    const aspects = args.object.get("aspects") orelse return true;
    if (aspects != .array) return true;
    if (aspects.array.items.len == 0) return true;
    for (aspects.array.items) |item| {
        if (item != .string) continue;
        if (std.ascii.eqlIgnoreCase(item.string, "all") or std.ascii.eqlIgnoreCase(item.string, aspect)) {
            return true;
        }
    }
    return false;
}

fn explicitArchitectureAspectWanted(args: std.json.Value, aspect: []const u8) bool {
    if (args != .object) return false;
    const aspects = args.object.get("aspects") orelse return false;
    if (aspects != .array) return false;
    for (aspects.array.items) |item| {
        if (item != .string) continue;
        if (std.ascii.eqlIgnoreCase(item.string, "all") or std.ascii.eqlIgnoreCase(item.string, aspect)) {
            return true;
        }
    }
    return false;
}

fn appendConnectedSummary(
    payload: *std.ArrayList(u8),
    self: *McpServer,
    project: []const u8,
    node_id: i64,
    relationship: ?[]const u8,
) !void {
    const inbound = try self.collectNeighborNames(project, node_id, .inbound, 5);
    defer freeOwnedStrings(self.allocator, inbound);
    const outbound = try self.collectNeighborNames(project, node_id, .outbound, 5);
    defer freeOwnedStrings(self.allocator, outbound);

    _ = relationship;
    try payload.appendSlice(self.allocator, ",\"connected\":{");
    try appendJsonStringArrayField(payload, self.allocator, "inbound", inbound, true);
    try appendJsonStringArrayField(payload, self.allocator, "outbound", outbound, false);
    try payload.appendSlice(self.allocator, "}");
}

fn appendSchemaCountsField(
    payload: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    key: []const u8,
    counts: []const store.LabelCount,
) !void {
    try payload.append(allocator, ',');
    try appendJsonString(payload, allocator, key);
    try payload.appendSlice(allocator, ":[");
    for (counts, 0..) |count, idx| {
        if (idx > 0) try payload.append(allocator, ',');
        try payload.writer(allocator).print(
            "{{\"label\":{f},\"count\":{d}}}",
            .{ std.json.fmt(count.label, .{}), count.count },
        );
    }
    try payload.append(allocator, ']');
}

fn appendEdgeTypeCountsField(
    payload: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    key: []const u8,
    counts: []const store.EdgeTypeCount,
) !void {
    try payload.append(allocator, ',');
    try appendJsonString(payload, allocator, key);
    try payload.appendSlice(allocator, ":[");
    for (counts, 0..) |count, idx| {
        if (idx > 0) try payload.append(allocator, ',');
        try payload.writer(allocator).print(
            "{{\"type\":{f},\"count\":{d}}}",
            .{ std.json.fmt(count.edge_type, .{}), count.count },
        );
    }
    try payload.append(allocator, ']');
}

fn appendLanguageSummaryField(
    payload: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    files: [][]u8,
) !void {
    var counts = std.StringHashMap(i32).init(allocator);
    defer {
        var it = counts.iterator();
        while (it.next()) |entry| allocator.free(entry.key_ptr.*);
        counts.deinit();
    }

    for (files) |file_path| {
        const language = languageNameForPath(file_path);
        const key = try allocator.dupe(u8, language);
        const entry = try counts.getOrPut(key);
        if (entry.found_existing) {
            allocator.free(key);
        }
        if (!entry.found_existing) entry.value_ptr.* = 0;
        entry.value_ptr.* += 1;
    }

    try payload.appendSlice(allocator, ",\"languages\":[");
    var idx: usize = 0;
    var it = counts.iterator();
    while (it.next()) |entry| : (idx += 1) {
        if (idx > 0) try payload.append(allocator, ',');
        try payload.writer(allocator).print(
            "{{\"language\":{f},\"count\":{d}}}",
            .{ std.json.fmt(entry.key_ptr.*, .{}), entry.value_ptr.* },
        );
    }
    try payload.append(allocator, ']');
}

fn appendDirectorySummaryField(
    payload: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    files: [][]u8,
) !void {
    var counts = std.StringHashMap(i32).init(allocator);
    defer {
        var it = counts.iterator();
        while (it.next()) |entry| allocator.free(entry.key_ptr.*);
        counts.deinit();
    }

    for (files) |file_path| {
        const dir_name = topLevelDirectory(file_path);
        const key = try allocator.dupe(u8, dir_name);
        const entry = try counts.getOrPut(key);
        if (entry.found_existing) {
            allocator.free(key);
        }
        if (!entry.found_existing) entry.value_ptr.* = 0;
        entry.value_ptr.* += 1;
    }

    try payload.appendSlice(allocator, ",\"packages\":[");
    var idx: usize = 0;
    var it = counts.iterator();
    while (it.next()) |entry| : (idx += 1) {
        if (idx > 0) try payload.append(allocator, ',');
        try payload.writer(allocator).print(
            "{{\"name\":{f},\"count\":{d}}}",
            .{ std.json.fmt(entry.key_ptr.*, .{}), entry.value_ptr.* },
        );
    }
    try payload.append(allocator, ']');
}

fn appendHotspotsField(
    payload: *std.ArrayList(u8),
    self: *McpServer,
    project: []const u8,
    limit: usize,
) !void {
    const page = try self.db.searchGraph(.{
        .project = project,
        .sort_field = .total_degree,
        .descending = true,
        .limit = limit,
    });
    defer self.db.freeGraphSearchPage(page);

    try payload.appendSlice(self.allocator, ",\"hotspots\":[");
    for (page.hits, 0..) |hit, idx| {
        if (idx > 0) try payload.append(self.allocator, ',');
        try payload.appendSlice(self.allocator, "{");
        try appendJsonStringField(payload, self.allocator, "name", hit.node.name, true);
        try appendJsonStringField(payload, self.allocator, "label", hit.node.label, false);
        try appendJsonStringField(payload, self.allocator, "file_path", hit.node.file_path, false);
        try appendJsonIntField(payload, self.allocator, "in_degree", hit.in_degree, false);
        try appendJsonIntField(payload, self.allocator, "out_degree", hit.out_degree, false);
        try payload.appendSlice(self.allocator, "}");
    }
    try payload.append(self.allocator, ']');
}

fn appendEntryPointsField(
    payload: *std.ArrayList(u8),
    self: *McpServer,
    project: []const u8,
    limit: usize,
) !void {
    const page = try self.db.searchGraph(.{
        .project = project,
        .label_pattern = "Function",
        .sort_field = .out_degree,
        .descending = true,
        .limit = 100,
    });
    defer self.db.freeGraphSearchPage(page);

    try payload.appendSlice(self.allocator, ",\"entry_points\":[");
    var written: usize = 0;
    for (page.hits) |hit| {
        if (hit.in_degree != 0 or hit.out_degree == 0) continue;
        if (written >= limit) break;
        if (written > 0) try payload.append(self.allocator, ',');
        try payload.appendSlice(self.allocator, "{");
        try appendJsonStringField(payload, self.allocator, "name", hit.node.name, true);
        try appendJsonStringField(payload, self.allocator, "qualified_name", hit.node.qualified_name, false);
        try appendJsonStringField(payload, self.allocator, "file_path", hit.node.file_path, false);
        try appendJsonIntField(payload, self.allocator, "out_degree", hit.out_degree, false);
        try payload.appendSlice(self.allocator, "}");
        written += 1;
    }
    try payload.append(self.allocator, ']');
}

fn appendRoutesField(
    payload: *std.ArrayList(u8),
    self: *McpServer,
    project: []const u8,
) !void {
    const nodes = try self.db.searchNodes(.{
        .project = project,
        .label_pattern = "Route",
        .limit = 500,
    });
    defer self.db.freeNodes(nodes);

    const edges = try self.db.listEdges(project, null);
    defer self.db.freeEdges(edges);

    try payload.appendSlice(self.allocator, ",\"routes\":[");
    var wrote: usize = 0;
    for (nodes) |node| {
        if (wrote > 0) try payload.append(self.allocator, ',');
        try payload.appendSlice(self.allocator, "{");
        try appendJsonStringField(payload, self.allocator, "name", node.name, true);
        try appendJsonStringField(payload, self.allocator, "file_path", node.file_path, false);
        try payload.appendSlice(self.allocator, "}");
        wrote += 1;
    }
    for (edges) |edge| {
        if (!std.mem.containsAtLeast(u8, edge.edge_type, 1, "HTTP") and !std.mem.containsAtLeast(u8, edge.edge_type, 1, "ROUTE")) continue;
        const source = (try self.db.findNodeById(project, edge.source_id)) orelse continue;
        defer self.db.freeNode(source);
        const target = (try self.db.findNodeById(project, edge.target_id)) orelse continue;
        defer self.db.freeNode(target);
        if (wrote > 0) try payload.append(self.allocator, ',');
        try payload.appendSlice(self.allocator, "{");
        try appendJsonStringField(payload, self.allocator, "name", source.name, true);
        try appendJsonStringField(payload, self.allocator, "target", target.name, false);
        try appendJsonStringField(payload, self.allocator, "type", edge.edge_type, false);
        try payload.appendSlice(self.allocator, "}");
        wrote += 1;
    }
    try payload.append(self.allocator, ']');
}

fn languageNameForPath(path: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, path, '.')) |dot| {
        if (discover.languageForExtension(path[dot..])) |language| {
            return language.name();
        }
    }
    return "unknown";
}

fn topLevelDirectory(path: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, path, '/')) |slash| {
        return path[0..slash];
    }
    return ".";
}

fn totalSearchMatchLines(hits: []const CodeSearchHit) usize {
    var total: usize = 0;
    for (hits) |hit| {
        total += @max(@as(usize, 1), hit.match_lines.len);
    }
    return total;
}

fn dedupRatioText(allocator: std.mem.Allocator, hits: []const CodeSearchHit) ![]u8 {
    const raw = totalSearchMatchLines(hits);
    if (raw == 0) return allocator.dupe(u8, "1.0x");
    const scaled = @as(u32, @intFromFloat(@round((@as(f64, @floatFromInt(raw)) / @as(f64, @floatFromInt(hits.len))) * 10.0)));
    return std.fmt.allocPrint(allocator, "{d}.{d}x", .{ scaled / 10, scaled % 10 });
}

fn compatibleNodeDisplayName(node: store.Node) []const u8 {
    if (std.mem.eql(u8, node.label, "Module")) {
        return std.fs.path.basename(node.file_path);
    }
    return node.name;
}

fn searchCodeLabelRank(label: ?[]const u8) u8 {
    const text = label orelse return 3;
    if (std.mem.eql(u8, text, "Function") or std.mem.eql(u8, text, "Method") or std.mem.eql(u8, text, "Class") or std.mem.eql(u8, text, "Interface")) return 0;
    if (std.mem.eql(u8, text, "Variable")) return 1;
    if (std.mem.eql(u8, text, "Module")) return 2;
    return 3;
}

fn searchCodeLessThan(_: void, lhs: CodeSearchHit, rhs: CodeSearchHit) bool {
    const lhs_rank = searchCodeLabelRank(lhs.label);
    const rhs_rank = searchCodeLabelRank(rhs.label);
    if (lhs_rank != rhs_rank) return lhs_rank < rhs_rank;

    const file_order = std.mem.order(u8, lhs.file_path, rhs.file_path);
    if (file_order != .eq) return file_order == .lt;

    const lhs_start = if (lhs.start_line > 0) lhs.start_line else @as(i32, @intCast(lhs.line));
    const rhs_start = if (rhs.start_line > 0) rhs.start_line else @as(i32, @intCast(rhs.line));
    if (lhs_start != rhs_start) return lhs_start < rhs_start;

    const lhs_name = lhs.name orelse lhs.file_path;
    const rhs_name = rhs.name orelse rhs.file_path;
    const name_order = std.mem.order(u8, lhs_name, rhs_name);
    if (name_order != .eq) return name_order == .lt;

    return lhs.line < rhs.line;
}

fn freeCodeSearchHit(allocator: std.mem.Allocator, hit: CodeSearchHit) void {
    allocator.free(hit.file_path);
    allocator.free(hit.snippet);
    if (hit.name) |value| allocator.free(value);
    if (hit.label) |value| allocator.free(value);
    if (hit.qualified_name) |value| allocator.free(value);
    allocator.free(hit.match_lines);
}

fn searchCodeCanContain(candidate: CodeSearchHit, nested: CodeSearchHit) bool {
    const candidate_rank = searchCodeLabelRank(candidate.label);
    const nested_rank = searchCodeLabelRank(nested.label);
    if (candidate_rank >= nested_rank) return false;
    if (!std.mem.eql(u8, candidate.file_path, nested.file_path)) return false;
    if (candidate.start_line <= 0 or candidate.end_line < candidate.start_line) return false;
    for (nested.match_lines) |line_no| {
        if (line_no < @as(u32, @intCast(candidate.start_line)) or line_no > @as(u32, @intCast(candidate.end_line))) {
            return false;
        }
    }
    return true;
}

fn appendUniqueMatchLine(allocator: std.mem.Allocator, hit: *CodeSearchHit, line_no: u32) !void {
    for (hit.match_lines) |existing| {
        if (existing == line_no) return;
    }
    const lines = try allocator.realloc(hit.match_lines, hit.match_lines.len + 1);
    lines[hit.match_lines.len] = line_no;
    hit.match_lines = lines;
}

fn foldContainedSearchHits(allocator: std.mem.Allocator, hits: *std.ArrayList(CodeSearchHit)) !void {
    var idx: usize = 0;
    while (idx < hits.items.len) {
        const current = hits.items[idx];
        if (searchCodeLabelRank(current.label) < searchCodeLabelRank("Variable")) {
            idx += 1;
            continue;
        }

        var best_idx: ?usize = null;
        var best_rank: u8 = std.math.maxInt(u8);
        var best_span: i32 = std.math.maxInt(i32);
        for (hits.items, 0..) |candidate, candidate_idx| {
            if (candidate_idx == idx) continue;
            if (!searchCodeCanContain(candidate, current)) continue;
            const rank = searchCodeLabelRank(candidate.label);
            const span = candidate.end_line - candidate.start_line;
            if (best_idx == null or rank < best_rank or (rank == best_rank and span < best_span)) {
                best_idx = candidate_idx;
                best_rank = rank;
                best_span = span;
            }
        }

        if (best_idx) |candidate_idx| {
            for (current.match_lines) |line_no| {
                try appendUniqueMatchLine(allocator, &hits.items[candidate_idx], line_no);
            }
            freeCodeSearchHit(allocator, hits.orderedRemove(idx));
            continue;
        }

        idx += 1;
    }
}

fn collectSearchCodeHits(
    allocator: std.mem.Allocator,
    db: *Store,
    project: []const u8,
    root_path: []const u8,
    pattern: []const u8,
    mode: SearchCodeMode,
    file_pattern: ?[]const u8,
    path_filter: ?[]const u8,
    regex: bool,
    limit: usize,
    context: usize,
) ![]CodeSearchHit {
    const files = try discover.discoverFiles(allocator, root_path, .{ .mode = .full });
    defer {
        for (files) |file| {
            allocator.free(file.path);
            allocator.free(file.rel_path);
        }
        allocator.free(files);
    }

    var out = std.ArrayList(CodeSearchHit).empty;
    errdefer {
        for (out.items) |hit| freeCodeSearchHit(allocator, hit);
        out.deinit(allocator);
    }
    var seen = std.StringHashMap(usize).init(allocator);
    defer {
        var it = seen.iterator();
        while (it.next()) |entry| allocator.free(entry.key_ptr.*);
        seen.deinit();
    }

    file_loop: for (files) |file| {
        if (path_filter) |filter| {
            if (std.mem.indexOf(u8, file.rel_path, filter) == null) continue;
        }
        if (file_pattern) |pattern_filter| {
            if (!globMatch(file.rel_path, pattern_filter)) continue;
        }

        const bytes = std.fs.cwd().readFileAlloc(allocator, file.path, 8 * 1024 * 1024) catch continue;
        defer allocator.free(bytes);
        const file_nodes = try db.findNodesByFile(project, file.rel_path);
        defer db.freeNodes(file_nodes);

        var line_iter = std.mem.splitAny(u8, bytes, "\n");
        var line_no: u32 = 1;
        while (line_iter.next()) |line| : (line_no += 1) {
            if (!searchPatternMatches(line, pattern, regex)) continue;

            if (mode == .files) {
                const key = try allocator.dupe(u8, file.rel_path);
                if (seen.contains(key)) {
                    allocator.free(key);
                    break;
                }
                try seen.put(key, out.items.len);
                try out.append(allocator, .{
                    .file_path = try allocator.dupe(u8, file.rel_path),
                    .snippet = try allocator.dupe(u8, ""),
                    .match_lines = try allocator.dupe(u32, &[_]u32{}),
                });
                if (out.items.len >= limit) break :file_loop;
                break;
            }

            const snippet = try buildSearchSnippet(allocator, bytes, line_no, if (mode == .full) context else 0);
            const symbol = bestSearchCodeNode(file_nodes, line_no);
            const dedupe_key = if (mode == .compact and symbol != null)
                try allocator.dupe(u8, symbol.?.qualified_name)
            else
                try std.fmt.allocPrint(allocator, "{s}:{d}", .{ file.rel_path, line_no });
            if (seen.get(dedupe_key)) |existing_index| {
                allocator.free(dedupe_key);
                const existing = &out.items[existing_index];
                const lines = try allocator.realloc(existing.match_lines, existing.match_lines.len + 1);
                lines[existing.match_lines.len] = line_no;
                existing.match_lines = lines;
                allocator.free(snippet);
                continue;
            }
            try seen.put(dedupe_key, out.items.len);

            const degree = if (symbol) |node|
                try db.getNodeDegree(project, node.id)
            else
                store.NodeDegree{};
            const match_lines = try allocator.alloc(u32, 1);
            match_lines[0] = line_no;

            try out.append(allocator, .{
                .file_path = try allocator.dupe(u8, file.rel_path),
                .line = line_no,
                .snippet = snippet,
                .name = if (symbol) |node| try allocator.dupe(u8, compatibleNodeDisplayName(node)) else null,
                .label = if (symbol) |node| try allocator.dupe(u8, node.label) else null,
                .qualified_name = if (symbol) |node| try allocator.dupe(u8, node.qualified_name) else null,
                .start_line = if (symbol) |node| node.start_line else 0,
                .end_line = if (symbol) |node| node.end_line else 0,
                .in_degree = degree.callers,
                .out_degree = degree.callees,
                .match_lines = match_lines,
            });
            if (out.items.len >= limit) break :file_loop;
        }
    }

    if (mode != .files and out.items.len > 1) {
        try foldContainedSearchHits(allocator, &out);
        std.sort.pdq(CodeSearchHit, out.items, {}, searchCodeLessThan);
    }

    return out.toOwnedSlice(allocator);
}

fn buildSearchSnippet(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    line_no: u32,
    context: usize,
) ![]u8 {
    if (context == 0) {
        const line = nthLine(bytes, line_no) orelse "";
        return allocator.dupe(u8, std.mem.trimRight(u8, line, "\r"));
    }
    const start_line: i32 = @intCast(@max(@as(i32, 1), @as(i32, @intCast(line_no)) - @as(i32, @intCast(context))));
    const end_line: i32 = @intCast(@as(i32, @intCast(line_no)) + @as(i32, @intCast(context)));
    return readInlineLines(allocator, bytes, start_line, end_line);
}

fn nthLine(bytes: []const u8, line_no: u32) ?[]const u8 {
    var iter = std.mem.splitAny(u8, bytes, "\n");
    var current: u32 = 1;
    while (iter.next()) |line| : (current += 1) {
        if (current == line_no) return line;
    }
    return null;
}

fn readInlineLines(allocator: std.mem.Allocator, bytes: []const u8, start_line: i32, end_line: i32) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var iter = std.mem.splitAny(u8, bytes, "\n");
    var current: i32 = 1;
    while (iter.next()) |line| : (current += 1) {
        if (current < start_line) continue;
        if (current > end_line) break;
        if (out.items.len > 0) try out.append(allocator, '\n');
        try out.appendSlice(allocator, std.mem.trimRight(u8, line, "\r"));
    }
    return out.toOwnedSlice(allocator);
}

fn bestSearchCodeNode(nodes: []const store.Node, line_no: u32) ?store.Node {
    var best: ?store.Node = null;
    var best_span: i32 = std.math.maxInt(i32);
    var module_fallback: ?store.Node = null;
    for (nodes) |node| {
        if (node.label.len == 0 or std.mem.eql(u8, node.label, "File")) continue;
        if (std.mem.eql(u8, node.label, "Module")) {
            module_fallback = node;
            continue;
        }
        const start = if (node.start_line > 0) node.start_line else 1;
        const end = if (node.end_line >= start) node.end_line else start;
        if (line_no < @as(u32, @intCast(start)) or line_no > @as(u32, @intCast(end))) continue;
        const span = end - start;
        if (span <= best_span) {
            best = node;
            best_span = span;
        }
    }
    return best orelse module_fallback;
}

fn searchPatternMatches(line: []const u8, pattern: []const u8, regex: bool) bool {
    if (!regex) return std.mem.indexOf(u8, line, pattern) != null;
    var iter = std.mem.splitSequence(u8, pattern, "|");
    while (iter.next()) |branch| {
        const trimmed = std.mem.trim(u8, branch, " \t");
        if (trimmed.len == 0) continue;
        if (matchRegexishText(line, trimmed)) return true;
    }
    return false;
}

fn matchRegexishText(line: []const u8, pattern: []const u8) bool {
    if (pattern.len >= 2 and pattern[0] == '^' and pattern[pattern.len - 1] == '$') {
        const inner = pattern[1 .. pattern.len - 1];
        if (std.mem.startsWith(u8, inner, ".*") and std.mem.endsWith(u8, inner, ".*") and inner.len >= 4) {
            return std.mem.indexOf(u8, line, inner[2 .. inner.len - 2]) != null;
        }
        return std.mem.eql(u8, line, inner);
    }
    if (std.mem.indexOf(u8, pattern, ".*")) |_| {
        var tmp = std.ArrayList(u8).empty;
        defer tmp.deinit(std.heap.page_allocator);
        var i: usize = 0;
        while (i < pattern.len) : (i += 1) {
            if (pattern[i] == '.' and i + 1 < pattern.len and pattern[i + 1] == '*') {
                i += 1;
                continue;
            }
            tmp.append(std.heap.page_allocator, pattern[i]) catch return false;
        }
        return std.mem.indexOf(u8, line, tmp.items) != null;
    }
    return std.mem.indexOf(u8, line, pattern) != null;
}

fn globMatch(text: []const u8, pattern: []const u8) bool {
    if (std.mem.eql(u8, pattern, "*")) return true;
    if (std.mem.indexOfScalar(u8, pattern, '*') == null) {
        return std.mem.eql(u8, text, pattern);
    }
    if (std.mem.startsWith(u8, pattern, "*") and std.mem.endsWith(u8, pattern, "*") and pattern.len >= 2) {
        return std.mem.indexOf(u8, text, pattern[1 .. pattern.len - 1]) != null;
    }
    if (std.mem.startsWith(u8, pattern, "*")) {
        return std.mem.endsWith(u8, text, pattern[1..]);
    }
    if (std.mem.endsWith(u8, pattern, "*")) {
        return std.mem.startsWith(u8, text, pattern[0 .. pattern.len - 1]);
    }
    const star = std.mem.indexOfScalar(u8, pattern, '*') orelse return false;
    return std.mem.startsWith(u8, text, pattern[0..star]) and std.mem.endsWith(u8, text, pattern[star + 1 ..]);
}

fn collectChangedFiles(
    allocator: std.mem.Allocator,
    root_path: []const u8,
    base_branch: []const u8,
) ![][]u8 {
    const branch_spec = try std.fmt.allocPrint(allocator, "{s}...HEAD", .{base_branch});
    defer allocator.free(branch_spec);
    const diff_base = try runCommandCapture(
        allocator,
        &.{ "git", "-C", root_path, "diff", "--name-only", branch_spec },
    );
    defer freeCommandResult(allocator, diff_base);
    const diff_worktree = try runCommandCapture(
        allocator,
        &.{ "git", "-C", root_path, "diff", "--name-only" },
    );
    defer freeCommandResult(allocator, diff_worktree);

    var out = std.ArrayList([]u8).empty;
    errdefer {
        for (out.items) |value| allocator.free(value);
        out.deinit(allocator);
    }
    var seen = std.StringHashMap(void).init(allocator);
    defer {
        var it = seen.iterator();
        while (it.next()) |entry| allocator.free(entry.key_ptr.*);
        seen.deinit();
    }

    try appendChangedLines(allocator, &out, &seen, diff_base.stdout);
    try appendChangedLines(allocator, &out, &seen, diff_worktree.stdout);
    return out.toOwnedSlice(allocator);
}

fn appendChangedLines(
    allocator: std.mem.Allocator,
    out: *std.ArrayList([]u8),
    seen: *std.StringHashMap(void),
    text: []const u8,
) !void {
    var iter = std.mem.splitAny(u8, text, "\n\r");
    while (iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len == 0) continue;
        const key = try allocator.dupe(u8, trimmed);
        if (seen.contains(key)) {
            allocator.free(key);
            continue;
        }
        try seen.put(key, {});
        try out.append(allocator, try allocator.dupe(u8, trimmed));
    }
}

fn collectImpactedSymbols(
    allocator: std.mem.Allocator,
    db: *Store,
    project: []const u8,
    changed_files: [][]u8,
) ![]ChangeSymbol {
    var out = std.ArrayList(ChangeSymbol).empty;
    errdefer {
        for (out.items) |item| {
            allocator.free(item.name);
            allocator.free(item.label);
            allocator.free(item.file_path);
            allocator.free(item.qualified_name);
        }
        out.deinit(allocator);
    }
    var seen = std.StringHashMap(void).init(allocator);
    defer {
        var it = seen.iterator();
        while (it.next()) |entry| allocator.free(entry.key_ptr.*);
        seen.deinit();
    }

    for (changed_files) |file_path| {
        const nodes = try db.findNodesByFile(project, file_path);
        defer db.freeNodes(nodes);
        for (nodes) |node| {
            if (std.mem.eql(u8, node.label, "File")) continue;
            const key = try allocator.dupe(u8, node.qualified_name);
            if (seen.contains(key)) {
                allocator.free(key);
                continue;
            }
            try seen.put(key, {});
            try out.append(allocator, .{
                .id = node.id,
                .name = try allocator.dupe(u8, compatibleNodeDisplayName(node)),
                .label = try allocator.dupe(u8, node.label),
                .file_path = try allocator.dupe(u8, node.file_path),
                .qualified_name = try allocator.dupe(u8, node.qualified_name),
            });
        }
    }

    return out.toOwnedSlice(allocator);
}

fn collectBlastRadius(
    allocator: std.mem.Allocator,
    db: *Store,
    project: []const u8,
    impacted: []const ChangeSymbol,
    depth: usize,
) ![]BlastItem {
    var out = std.ArrayList(BlastItem).empty;
    errdefer {
        for (out.items) |item| {
            allocator.free(item.name);
            allocator.free(item.qualified_name);
            allocator.free(item.file_path);
        }
        out.deinit(allocator);
    }
    var seen = std.StringHashMap(u32).init(allocator);
    defer {
        var it = seen.iterator();
        while (it.next()) |entry| allocator.free(entry.key_ptr.*);
        seen.deinit();
    }

    for (impacted) |symbol| {
        const traversal = try db.traverseEdgesBreadthFirst(project, symbol.id, .both, @intCast(depth), null);
        defer db.freeTraversalEdges(traversal);

        for (traversal) |edge| {
            const candidates = [_]i64{ edge.source_id, edge.target_id };
            for (candidates) |candidate_id| {
                if (candidate_id == symbol.id) continue;
                const node = (try db.findNodeById(project, candidate_id)) orelse continue;
                defer db.freeNode(node);
                if (std.mem.eql(u8, node.label, "File") or std.mem.eql(u8, node.label, "Module")) continue;
                const key = try allocator.dupe(u8, node.qualified_name);
                if (seen.get(key)) |existing_hop| {
                    allocator.free(key);
                    if (edge.depth >= existing_hop) continue;
                    updateBlastItemHop(out.items, node.qualified_name, edge.depth);
                    continue;
                }
                try seen.put(key, edge.depth);
                try out.append(allocator, .{
                    .name = try allocator.dupe(u8, node.name),
                    .qualified_name = try allocator.dupe(u8, node.qualified_name),
                    .file_path = try allocator.dupe(u8, node.file_path),
                    .hop = edge.depth,
                });
            }
        }
    }

    return out.toOwnedSlice(allocator);
}

fn updateBlastItemHop(items: []BlastItem, qualified_name: []const u8, hop: u32) void {
    for (items) |*item| {
        if (std.mem.eql(u8, item.qualified_name, qualified_name) and hop < item.hop) {
            item.hop = hop;
            return;
        }
    }
}

fn riskLabel(hop: u32) []const u8 {
    return if (hop <= 1) "high" else if (hop == 2) "medium" else "low";
}

const CommandResult = struct {
    stdout: []u8,
    stderr: []u8,
};

fn runCommandCapture(allocator: std.mem.Allocator, argv: []const []const u8) !CommandResult {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .max_output_bytes = 16 * 1024 * 1024,
    });
    return .{
        .stdout = result.stdout,
        .stderr = result.stderr,
    };
}

fn freeCommandResult(allocator: std.mem.Allocator, result: CommandResult) void {
    allocator.free(result.stdout);
    allocator.free(result.stderr);
}

fn freeCodeSearchHits(allocator: std.mem.Allocator, hits: []const CodeSearchHit) void {
    for (hits) |hit| {
        allocator.free(hit.file_path);
        allocator.free(hit.snippet);
        if (hit.name) |value| allocator.free(value);
        if (hit.label) |value| allocator.free(value);
        if (hit.qualified_name) |value| allocator.free(value);
        allocator.free(hit.match_lines);
    }
    allocator.free(hits);
}

fn freeChangeSymbols(allocator: std.mem.Allocator, items: []const ChangeSymbol) void {
    for (items) |item| {
        allocator.free(item.name);
        allocator.free(item.label);
        allocator.free(item.file_path);
        allocator.free(item.qualified_name);
    }
    allocator.free(items);
}

fn freeBlastItems(allocator: std.mem.Allocator, items: []const BlastItem) void {
    for (items) |item| {
        allocator.free(item.name);
        allocator.free(item.qualified_name);
        allocator.free(item.file_path);
    }
    allocator.free(items);
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
    if (std.mem.eql(u8, name, "get_architecture")) return .get_architecture;
    if (std.mem.eql(u8, name, "search_code")) return .search_code;
    if (std.mem.eql(u8, name, "list_projects")) return .list_projects;
    if (std.mem.eql(u8, name, "delete_project")) return .delete_project;
    if (std.mem.eql(u8, name, "index_status")) return .index_status;
    if (std.mem.eql(u8, name, "detect_changes")) return .detect_changes;
    if (std.mem.eql(u8, name, "manage_adr")) return .manage_adr;
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

fn decodeEscapedJsonString(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    var i: usize = 0;
    while (i < raw.len) : (i += 1) {
        if (raw[i] != '\\' or i + 1 >= raw.len) {
            try out.append(allocator, raw[i]);
            continue;
        }

        i += 1;
        switch (raw[i]) {
            '\\' => try out.append(allocator, '\\'),
            '"' => try out.append(allocator, '"'),
            '/' => try out.append(allocator, '/'),
            'b' => try out.append(allocator, '\x08'),
            'f' => try out.append(allocator, '\x0c'),
            'n' => try out.append(allocator, '\n'),
            'r' => try out.append(allocator, '\r'),
            't' => try out.append(allocator, '\t'),
            else => {
                try out.append(allocator, '\\');
                try out.append(allocator, raw[i]);
            },
        }
    }

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
    try std.testing.expectEqual(SupportedTool.get_architecture, try SupportedToolFromString("get_architecture"));
    try std.testing.expectEqual(SupportedTool.search_code, try SupportedToolFromString("search_code"));
    try std.testing.expectEqual(SupportedTool.detect_changes, try SupportedToolFromString("detect_changes"));
    try std.testing.expectEqual(SupportedTool.manage_adr, try SupportedToolFromString("manage_adr"));
    try std.testing.expectError(error.UnsupportedTool, SupportedToolFromString("missing"));
}

test "tools/list advertises manage_adr" {
    var s = try store.Store.openMemory(std.testing.allocator);
    defer s.deinit();
    var srv = McpServer.init(std.testing.allocator, &s);
    defer srv.deinit();

    const response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":42,"method":"tools/list","params":{}}
    )).?;
    defer std.testing.allocator.free(response);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"manage_adr\"") != null);
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

test "manage_adr supports update get and sections" {
    var s = try store.Store.openMemory(std.testing.allocator);
    defer s.deinit();
    try s.upsertProject("demo", "/tmp/demo");

    var srv = McpServer.init(std.testing.allocator, &s);
    defer srv.deinit();

    const missing_response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":70,"method":"tools/call","params":{"name":"manage_adr","arguments":{"project":"demo"}}}
    )).?;
    defer std.testing.allocator.free(missing_response);
    try std.testing.expect(std.mem.indexOf(u8, missing_response, "\"status\":\"no_adr\"") != null);

    const update_response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":71,"method":"tools/call","params":{"name":"manage_adr","arguments":{"project":"demo","mode":"update","content":"## PURPOSE\\nShip ADRs.\\n\\n## STACK\\nZig\\n\\n## ARCHITECTURE\\nSQLite"}}}
    )).?;
    defer std.testing.allocator.free(update_response);
    try std.testing.expect(std.mem.indexOf(u8, update_response, "\"status\":\"updated\"") != null);

    const get_response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":72,"method":"tools/call","params":{"name":"manage_adr","arguments":{"project":"demo","mode":"get"}}}
    )).?;
    defer std.testing.allocator.free(get_response);
    const get_parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, get_response, .{});
    defer get_parsed.deinit();
    const get_result = get_parsed.value.object.get("result").?.object;
    try std.testing.expect(std.mem.indexOf(u8, get_result.get("content").?.string, "## PURPOSE") != null);
    try std.testing.expect(get_result.get("created_at") != null);
    try std.testing.expect(get_result.get("updated_at") != null);

    const sections_response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":73,"method":"tools/call","params":{"name":"manage_adr","arguments":{"project":"demo","mode":"sections"}}}
    )).?;
    defer std.testing.allocator.free(sections_response);
    const sections_parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, sections_response, .{});
    defer sections_parsed.deinit();
    const sections = sections_parsed.value.object.get("result").?.object.get("sections").?.array.items;
    try std.testing.expectEqual(@as(usize, 3), sections.len);
    try std.testing.expectEqualStrings("## PURPOSE", sections[0].string);
}

test "index_repository registers watcher state and delete_project unwatches it" {
    const allocator = std.testing.allocator;
    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(allocator, "/tmp/cbm-mcp-watch-{x}", .{project_id});
    defer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    const main_path = try std.fs.path.join(allocator, &.{ project_dir, "main.py" });
    defer allocator.free(main_path);
    var main_file = try std.fs.cwd().createFile(main_path, .{});
    defer main_file.close();
    try main_file.writeAll(
        \\def run():
        \\    return 1
        \\
    );

    var s = try store.Store.openMemory(allocator);
    defer s.deinit();
    var srv = McpServer.init(allocator, &s);
    defer srv.deinit();

    var watcher_ref = watcher.Watcher.init(allocator, null, null);
    defer watcher_ref.deinit();
    srv.setWatcher(&watcher_ref);

    const index_request = try std.fmt.allocPrint(
        allocator,
        "{{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"tools/call\",\"params\":{{\"name\":\"index_repository\",\"arguments\":{{\"project_path\":\"{s}\"}}}}}}",
        .{project_dir},
    );
    defer allocator.free(index_request);

    const index_response = (try srv.handleRequest(index_request)).?;
    defer allocator.free(index_response);
    try std.testing.expectEqual(@as(usize, 1), watcher_ref.watchCount());

    const delete_request = try std.fmt.allocPrint(
        allocator,
        "{{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"tools/call\",\"params\":{{\"name\":\"delete_project\",\"arguments\":{{\"project\":\"{s}\"}}}}}}",
        .{std.fs.path.basename(project_dir)},
    );
    defer allocator.free(delete_request);

    const delete_response = (try srv.handleRequest(delete_request)).?;
    defer allocator.free(delete_response);
    try std.testing.expectEqual(@as(usize, 0), watcher_ref.watchCount());
}

test "runFiles processes multiple newline-delimited requests" {
    const allocator = std.testing.allocator;
    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(allocator, "/tmp/cbm-mcp-runfiles-{x}", .{project_id});
    defer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    const main_path = try std.fs.path.join(allocator, &.{ project_dir, "main.py" });
    defer allocator.free(main_path);
    var main_file = try std.fs.cwd().createFile(main_path, .{});
    defer main_file.close();
    try main_file.writeAll(
        \\def run():
        \\    return 1
        \\
    );

    var s = try store.Store.openMemory(allocator);
    defer s.deinit();
    var srv = McpServer.init(allocator, &s);
    defer srv.deinit();

    const stdin_pipe = try std.posix.pipe();
    const stdout_pipe = try std.posix.pipe();

    var stdin_reader = std.fs.File{ .handle = stdin_pipe[0] };
    defer stdin_reader.close();
    var stdin_writer = std.fs.File{ .handle = stdin_pipe[1] };

    var stdout_reader = std.fs.File{ .handle = stdout_pipe[0] };
    defer stdout_reader.close();
    var stdout_writer = std.fs.File{ .handle = stdout_pipe[1] };

    const input = try std.fmt.allocPrint(
        allocator,
        "{{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{{}}}}\n" ++
            "{{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{{\"name\":\"index_repository\",\"arguments\":{{\"project_path\":\"{s}\"}}}}}}\n",
        .{project_dir},
    );
    defer allocator.free(input);
    try stdin_writer.writeAll(input);
    stdin_writer.close();

    try srv.runFiles(stdin_reader, stdout_writer);
    stdout_writer.close();

    const output = try stdout_reader.readToEndAlloc(allocator, 64 * 1024);
    defer allocator.free(output);

    var responses = std.mem.splitScalar(u8, output, '\n');
    const initialize_response = responses.next() orelse return error.Unexpected;
    const index_response = responses.next() orelse return error.Unexpected;

    try std.testing.expect(std.mem.indexOf(u8, initialize_response, "\"protocolVersion\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, index_response, "\"project\":\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, index_response, "\"nodes\":") != null);
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

test "search_graph returns totals pagination and connected summaries" {
    var s = try store.Store.openMemory(std.testing.allocator);
    defer s.deinit();
    try s.upsertProject("demo", "/tmp/demo");

    const alpha_id = try s.upsertNode(.{
        .project = "demo",
        .label = "Function",
        .name = "alpha",
        .qualified_name = "demo.alpha",
        .file_path = "src/main.py",
    });
    const beta_id = try s.upsertNode(.{
        .project = "demo",
        .label = "Function",
        .name = "beta",
        .qualified_name = "demo.beta",
        .file_path = "src/main.py",
    });
    const gamma_id = try s.upsertNode(.{
        .project = "demo",
        .label = "Function",
        .name = "gamma",
        .qualified_name = "demo.gamma",
        .file_path = "src/util.py",
    });
    _ = try s.upsertEdge(.{
        .project = "demo",
        .source_id = alpha_id,
        .target_id = beta_id,
        .edge_type = "CALLS",
    });
    _ = try s.upsertEdge(.{
        .project = "demo",
        .source_id = alpha_id,
        .target_id = gamma_id,
        .edge_type = "CALLS",
    });

    var srv = McpServer.init(std.testing.allocator, &s);
    defer srv.deinit();

    const response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"search_graph","arguments":{"project":"demo","label":"Function","relationship":"CALLS","sort_by":"total_degree","sort_direction":"desc","limit":1,"offset":0,"include_connected":true}}}
    )).?;
    defer std.testing.allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, response, .{});
    defer parsed.deinit();

    const result = parsed.value.object.get("result").?.object;
    try std.testing.expectEqual(@as(i64, 3), result.get("total").?.integer);
    try std.testing.expectEqual(true, result.get("has_more").?.bool);
    const results = result.get("results").?.array;
    try std.testing.expectEqual(@as(usize, 1), results.items.len);
    try std.testing.expectEqualStrings("alpha", results.items[0].object.get("name").?.string);
    try std.testing.expect(results.items[0].object.get("connected") != null);
}

test "get_architecture and search_code expose phase 5 summaries" {
    const allocator = std.testing.allocator;
    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(allocator, "/tmp/cbm-phase5-arch-{x}", .{project_id});
    defer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};
    const src_dir = try std.fs.path.join(allocator, &.{ project_dir, "src" });
    defer allocator.free(src_dir);
    try std.fs.cwd().makePath(src_dir);

    const main_path = try std.fs.path.join(allocator, &.{ project_dir, "src", "main.py" });
    defer allocator.free(main_path);
    var main_file = try std.fs.cwd().createFile(main_path, .{});
    defer main_file.close();
    try main_file.writeAll(
        \\def run():
        \\    helper()
        \\
        \\def helper():
        \\    return "phase5"
        \\
    );

    var s = try store.Store.openMemory(allocator);
    defer s.deinit();
    try s.upsertProject("demo", project_dir);
    const run_id = try s.upsertNode(.{
        .project = "demo",
        .label = "Function",
        .name = "run",
        .qualified_name = "demo.src.main.run",
        .file_path = "src/main.py",
        .start_line = 1,
        .end_line = 2,
    });
    const helper_id = try s.upsertNode(.{
        .project = "demo",
        .label = "Function",
        .name = "helper",
        .qualified_name = "demo.src.main.helper",
        .file_path = "src/main.py",
        .start_line = 4,
        .end_line = 5,
    });
    _ = try s.upsertEdge(.{
        .project = "demo",
        .source_id = run_id,
        .target_id = helper_id,
        .edge_type = "CALLS",
    });

    var srv = McpServer.init(allocator, &s);
    defer srv.deinit();

    const arch_response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"get_architecture","arguments":{"project":"demo","aspects":["structure","dependencies","entry_points"]}}}
    )).?;
    defer allocator.free(arch_response);
    const arch_parsed = try std.json.parseFromSlice(std.json.Value, allocator, arch_response, .{});
    defer arch_parsed.deinit();
    const arch_result = arch_parsed.value.object.get("result").?.object;
    try std.testing.expect(arch_result.get("node_labels") != null);
    try std.testing.expect(arch_result.get("edge_types") != null);
    try std.testing.expect(arch_result.get("entry_points") != null);

    const code_response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":13,"method":"tools/call","params":{"name":"search_code","arguments":{"project":"demo","pattern":"helper","mode":"compact","limit":5}}}
    )).?;
    defer allocator.free(code_response);
    const code_parsed = try std.json.parseFromSlice(std.json.Value, allocator, code_response, .{});
    defer code_parsed.deinit();
    const code_result = code_parsed.value.object.get("result").?.object;
    try std.testing.expectEqualStrings("compact", code_result.get("mode").?.string);
    try std.testing.expect(code_result.get("results").?.array.items.len >= 1);
}

test "detect_changes aligns shared impact mode and keeps Zig full mode" {
    const allocator = std.testing.allocator;
    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(allocator, "/tmp/cbm-phase5-changes-{x}", .{project_id});
    defer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};
    const src_dir = try std.fs.path.join(allocator, &.{ project_dir, "src" });
    defer allocator.free(src_dir);
    try std.fs.cwd().makePath(src_dir);

    const main_path = try std.fs.path.join(allocator, &.{ project_dir, "src", "main.py" });
    defer allocator.free(main_path);
    var main_file = try std.fs.cwd().createFile(main_path, .{});
    defer main_file.close();
    try main_file.writeAll(
        \\def run():
        \\    return helper()
        \\
        \\def helper():
        \\    return 1
        \\
    );

    try runTestCommand(allocator, &.{ "git", "-C", project_dir, "init", "-b", "main" });
    try runTestCommand(allocator, &.{ "git", "-C", project_dir, "config", "user.email", "tests@example.com" });
    try runTestCommand(allocator, &.{ "git", "-C", project_dir, "config", "user.name", "Phase Five Tests" });
    try runTestCommand(allocator, &.{ "git", "-C", project_dir, "add", "." });
    try runTestCommand(allocator, &.{ "git", "-C", project_dir, "commit", "-m", "initial" });

    {
        var updated_file = try std.fs.cwd().createFile(main_path, .{ .truncate = true });
        defer updated_file.close();
        try updated_file.writeAll(
            \\def run():
            \\    return helper() + 1
            \\
            \\def helper():
            \\    return 1
            \\
        );
    }

    var s = try store.Store.openMemory(allocator);
    defer s.deinit();
    try s.upsertProject("demo", project_dir);
    const run_id = try s.upsertNode(.{
        .project = "demo",
        .label = "Function",
        .name = "run",
        .qualified_name = "demo.src.main.run",
        .file_path = "src/main.py",
        .start_line = 1,
        .end_line = 2,
    });
    const helper_id = try s.upsertNode(.{
        .project = "demo",
        .label = "Function",
        .name = "helper",
        .qualified_name = "demo.src.main.helper",
        .file_path = "src/main.py",
        .start_line = 4,
        .end_line = 5,
    });
    _ = try s.upsertEdge(.{
        .project = "demo",
        .source_id = run_id,
        .target_id = helper_id,
        .edge_type = "CALLS",
    });

    var srv = McpServer.init(allocator, &s);
    defer srv.deinit();

    const response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":14,"method":"tools/call","params":{"name":"detect_changes","arguments":{"project":"demo","base_branch":"main","depth":2}}}
    )).?;
    defer allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response, .{});
    defer parsed.deinit();
    const result = parsed.value.object.get("result").?.object;
    try std.testing.expectEqual(@as(i64, 1), result.get("changed_count").?.integer);
    try std.testing.expect(result.get("changed_files").?.array.items.len >= 1);
    try std.testing.expect(result.get("impacted_symbols").?.array.items.len >= 2);
    try std.testing.expect(result.get("blast_radius") == null);

    const full_response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":141,"method":"tools/call","params":{"name":"detect_changes","arguments":{"project":"demo","base_branch":"main","scope":"full","depth":2}}}
    )).?;
    defer allocator.free(full_response);

    const full_parsed = try std.json.parseFromSlice(std.json.Value, allocator, full_response, .{});
    defer full_parsed.deinit();
    const full_result = full_parsed.value.object.get("result").?.object;
    try std.testing.expect(full_result.get("blast_radius") != null);
    try std.testing.expect(full_result.get("blast_radius").?.array.items.len >= 1);

    const files_only_response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":15,"method":"tools/call","params":{"name":"detect_changes","arguments":{"project":"demo","base_branch":"main","scope":"files","depth":2}}}
    )).?;
    defer allocator.free(files_only_response);

    const files_only_parsed = try std.json.parseFromSlice(std.json.Value, allocator, files_only_response, .{});
    defer files_only_parsed.deinit();
    const files_only_result = files_only_parsed.value.object.get("result").?.object;
    try std.testing.expectEqual(@as(i64, 1), files_only_result.get("changed_count").?.integer);
    try std.testing.expectEqual(@as(usize, 0), files_only_result.get("impacted_symbols").?.array.items.len);
    try std.testing.expect(files_only_result.get("blast_radius") == null);
}

fn runTestCommand(allocator: std.mem.Allocator, argv: []const []const u8) !void {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .max_output_bytes = 1024 * 1024,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("command failed ({d}): {s}\nstderr:\n{s}\n", .{ code, argv[0], result.stderr });
                return error.TestCommandFailed;
            }
        },
        else => return error.TestCommandFailed,
    }
}

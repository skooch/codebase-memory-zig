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

const builtin = @import("builtin");
const std = @import("std");
const adr = @import("adr.zig");
const store = @import("store.zig");
const pipeline = @import("pipeline.zig");
const query_router = @import("query_router.zig");
const runtime_lifecycle = @import("runtime_lifecycle.zig");
const cypher = @import("cypher.zig");
const search_index = @import("search_index.zig");
const watcher = @import("watcher.zig");

const Store = store.Store;
const max_request_line_bytes = 1024 * 1024;
const max_response_bytes = 4 * 1024 * 1024;
const response_too_large_code: i64 = -32001;
pub const default_idle_store_timeout_ms: u64 = 60_000;
const supported_protocol_versions = [_][]const u8{
    "2025-11-25",
    "2025-06-18",
    "2025-03-26",
    "2024-11-05",
};

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
    ingest_traces,
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
    runtime_db_path: ?[]const u8 = null,
    idle_store_timeout_ms: u64 = 0,
    last_store_activity_ms: ?u64 = null,

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

    pub fn setRuntimeStorePath(self: *McpServer, runtime_db_path: []const u8) void {
        self.runtime_db_path = runtime_db_path;
    }

    pub fn setIdleStoreTimeoutMs(self: *McpServer, timeout_ms: usize) void {
        self.idle_store_timeout_ms = @intCast(timeout_ms);
        if (self.idle_store_timeout_ms == 0) {
            self.last_store_activity_ms = null;
        }
    }

    pub fn handleRequest(self: *McpServer, request: []const u8) !?[]const u8 {
        return self.handleLine(request);
    }

    /// Run MCP over stdio line-delimited JSON.
    pub fn runFiles(self: *McpServer, stdin_file: std.fs.File, stdout_file: std.fs.File) !void {
        var read_buf: [4096]u8 = undefined;
        var pending = std.ArrayList(u8).empty;
        defer pending.deinit(self.allocator);
        var discarding_oversized_line = false;

        while (true) {
            if (!try self.waitForInput(stdin_file)) {
                continue;
            }

            const read_len = try stdin_file.read(&read_buf);
            if (read_len == 0) {
                if (!discarding_oversized_line) {
                    try self.handlePendingFileLine(&pending, stdout_file);
                }
                return;
            }

            for (read_buf[0..read_len]) |byte| {
                if (byte == '\n') {
                    if (discarding_oversized_line) {
                        discarding_oversized_line = false;
                        pending.clearRetainingCapacity();
                        continue;
                    }
                    try self.handlePendingFileLine(&pending, stdout_file);
                    continue;
                }
                if (discarding_oversized_line) continue;
                if (pending.items.len >= max_request_line_bytes) {
                    try self.writeOversizedRequestError(stdout_file);
                    pending.clearRetainingCapacity();
                    discarding_oversized_line = true;
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

    fn writeOversizedRequestError(self: *McpServer, stdout_file: std.fs.File) !void {
        const response = try self.errorResponse(null, -32600, "Request too large");
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
        if (request.value.id == null) {
            return null;
        }

        if (std.mem.eql(u8, request.value.method, "initialize")) {
            if (self.lifecycle_ref) |lifecycle| lifecycle.startUpdateCheck();
            const payload = try std.fmt.allocPrint(
                self.allocator,
                "{{\"protocolVersion\":\"{s}\",\"capabilities\":{{\"tools\":{{}}}},\"serverInfo\":{{\"name\":\"codebase-memory-zig\",\"version\":\"{s}\"}}}}",
                .{ negotiatedProtocolVersion(request.value.params), "0.0.0" },
            );
            defer self.allocator.free(payload);
            return self.successResponse(request.value.id, payload);
        }
        if (std.mem.eql(u8, request.value.method, "tools/list")) {
            const payload =
                \\{"tools":[
                \\{"name":"index_repository","description":"Index a repository into the knowledge graph","inputSchema":{"type":"object","properties":{"repo_path":{"type":"string","description":"Path to the repository"},"mode":{"type":"string","enum":["full","fast"],"default":"full","description":"full: all passes. fast: structure-first discovery."}},"required":["repo_path"]}},
                \\{"name":"search_graph","description":"Structured graph search with filtering, degree-aware ranking, pagination, and optional connected-node context","inputSchema":{"type":"object","properties":{"project":{"type":"string"},"query":{"type":"string","description":"Natural-language or keyword full-text search using BM25 ranking over indexed project files. When this yields usable terms, name_pattern is ignored and the response includes search_mode:\"bm25\"."},"label":{"type":"string"},"label_pattern":{"type":"string"},"name_pattern":{"type":"string"},"qn_pattern":{"type":"string"},"file_pattern":{"type":"string"},"relationship":{"type":"string"},"exclude_entry_points":{"type":"boolean"},"include_connected":{"type":"boolean"},"limit":{"type":"number"},"offset":{"type":"number"},"min_degree":{"type":"number"},"max_degree":{"type":"number"},"sort_by":{"type":"string"},"sort_direction":{"type":"string"}}}},
                \\{"name":"query_graph","description":"Run a read-only Cypher-like query","inputSchema":{"type":"object","properties":{"project":{"type":"string"},"query":{"type":"string"},"max_rows":{"type":"number"}}}},
                \\{"name":"trace_call_path","description":"Trace call paths between nodes with configurable edge types, modes, risk labels, and test filtering","inputSchema":{"type":"object","properties":{"project":{"type":"string"},"start_node_qn":{"type":"string","description":"Qualified name of start node"},"function_name":{"type":"string","description":"Alias for start_node_qn (bare name lookup)"},"direction":{"type":"string","enum":["in","out","both"]},"depth":{"type":"number"},"mode":{"type":"string","enum":["calls","data_flow","cross_service"],"description":"Preset edge type set (default: calls)"},"edge_types":{"type":"array","items":{"type":"string"},"description":"Explicit edge types override (takes priority over mode)"},"risk_labels":{"type":"boolean","description":"Include hop-based risk classification per node"},"include_tests":{"type":"boolean","description":"Include test-file nodes in results (default: false)"}}}},
                \\{"name":"get_code_snippet","description":"Read source code for a function/class/symbol. IMPORTANT: First call search_graph to find the exact qualified_name, then pass it here. This is a read tool, not a search tool. Accepts full qualified_name (exact match) or short function name (returns suggestions if ambiguous).","inputSchema":{"type":"object","properties":{"qualified_name":{"type":"string","description":"Full qualified_name from search_graph, or short function name"},"project":{"type":"string"},"include_neighbors":{"type":"boolean","default":false}},"required":["qualified_name","project"]}},
                \\{"name":"get_graph_schema","description":"Get the schema of the knowledge graph (node labels, edge types)","inputSchema":{"type":"object","properties":{"project":{"type":"string"}},"required":["project"]}},
                \\{"name":"get_architecture","description":"High-level project summary: structure, dependencies, languages, hotspots, entry points, routes, and messaging","inputSchema":{"type":"object","properties":{"project":{"type":"string"},"aspects":{"type":"array","items":{"type":"string"}}},"required":["project"]}},
                \\{"name":"search_code","description":"Text search across indexed project files with compact, full, or files-only output","inputSchema":{"type":"object","properties":{"project":{"type":"string"},"pattern":{"type":"string"},"mode":{"type":"string","enum":["compact","full","files"]},"file_pattern":{"type":"string"},"path_filter":{"type":"string"},"limit":{"type":"number"},"context":{"type":"number"},"regex":{"type":"boolean"}},"required":["project","pattern"]}},
                \\{"name":"list_projects","description":"List indexed projects","inputSchema":{"type":"object","properties":{}}},
                \\{"name":"delete_project","description":"Delete a project from the index","inputSchema":{"type":"object","properties":{"project":{"type":"string"}},"required":["project"]}},
                \\{"name":"index_status","description":"Get the indexing status of a project","inputSchema":{"type":"object","properties":{"project":{"type":"string"}}}},
                \\{"name":"detect_changes","description":"Map local git changes to affected symbols and nearby blast radius","inputSchema":{"type":"object","properties":{"project":{"type":"string"},"base_branch":{"type":"string"},"since":{"type":"string","description":"Git ref or date to compare from (e.g. HEAD~5, v0.5.0, 2026-01-01)"},"scope":{"type":"string"},"depth":{"type":"number"}},"required":["project"]}},
                \\{"name":"manage_adr","description":"Create or update Architecture Decision Records","inputSchema":{"type":"object","properties":{"project":{"type":"string"},"mode":{"type":"string","enum":["get","update","sections"]},"content":{"type":"string"},"sections":{"type":"array","items":{"type":"string"}}},"required":["project"]}},
                \\{"name":"ingest_traces","description":"Ingest runtime traces to enhance the knowledge graph","inputSchema":{"type":"object","properties":{"traces":{"type":"array","items":{"type":"object"}},"project":{"type":"string"}},"required":["traces","project"]}}
                \\]}
            ;
            const response = try self.successResponse(request.value.id, payload);
            if (response) |owned_response| {
                if (self.lifecycle_ref) |lifecycle| {
                    const updated_response = lifecycle.injectUpdateNoticeBounded(owned_response, max_response_bytes) catch |err| switch (err) {
                        error.ResponseTooLarge => return self.errorResponse(request.value.id, response_too_large_code, "Response too large"),
                        else => return err,
                    };
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
            try self.ensureStoreOpen();
            self.noteStoreActivityNow();
            const call_request = extractToolCall(self.allocator, request.value.params.?) catch {
                return self.errorResponse(request.value.id, -32602, "Invalid tool call params");
            };
            const response = try self.dispatchToolCall(request.value.id, call_request);
            if (response) |owned_response| {
                if (self.lifecycle_ref) |lifecycle| {
                    const updated_response = lifecycle.injectUpdateNoticeBounded(owned_response, max_response_bytes) catch |err| switch (err) {
                        error.ResponseTooLarge => return self.errorResponse(request.value.id, response_too_large_code, "Response too large"),
                        else => return err,
                    };
                    return updated_response;
                }
                return owned_response;
            }
            return null;
        }

        return self.errorResponse(request.value.id, -32601, "Method not found");
    }

    fn ensureStoreOpen(self: *McpServer) !void {
        if (self.db.db != null) return;
        const runtime_db_path = self.runtime_db_path orelse return;
        const db_path_z = try self.allocator.dupeZ(u8, runtime_db_path);
        defer self.allocator.free(db_path_z);
        self.db.* = try Store.openPath(self.allocator, db_path_z);
    }

    fn noteStoreActivityNow(self: *McpServer) void {
        self.noteStoreActivityAt(nowMillis());
    }

    fn noteStoreActivityAt(self: *McpServer, now_ms: u64) void {
        if (self.runtime_db_path == null or self.idle_store_timeout_ms == 0) return;
        self.last_store_activity_ms = now_ms;
    }

    fn evictIdleStoreIfNeededAt(self: *McpServer, now_ms: u64) void {
        if (self.runtime_db_path == null or self.idle_store_timeout_ms == 0) return;
        if (self.db.db == null) return;
        const last_activity_ms = self.last_store_activity_ms orelse return;
        if (now_ms < last_activity_ms or now_ms - last_activity_ms < self.idle_store_timeout_ms) return;
        self.db.deinit();
        self.last_store_activity_ms = null;
    }

    fn waitForInput(self: *McpServer, stdin_file: std.fs.File) !bool {
        if (builtin.os.tag == .windows) return true;
        if (self.runtime_db_path == null or self.idle_store_timeout_ms == 0) return true;

        var fds = [_]std.posix.pollfd{.{
            .fd = stdin_file.handle,
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};
        const timeout_ms: i32 = @intCast(@min(self.idle_store_timeout_ms, @as(u64, @intCast(std.math.maxInt(i32)))));
        const ready = try std.posix.poll(&fds, timeout_ms);
        if (ready != 0) return true;

        self.evictIdleStoreIfNeededAt(nowMillis());
        return false;
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
            .ingest_traces => self.handleIngestTraces(request_id, call.arguments orelse .null),
        };
    }

    fn handleIndexRepository(self: *McpServer, request_id: ?std.json.Value, args: std.json.Value) !?[]const u8 {
        const repo_path = indexRepositoryPathArg(args) orelse return self.errorResponse(request_id, -32602, "Missing repo_path");
        const mode_raw = stringArg(args, "mode") orelse "full";
        const mode = if (std.mem.eql(u8, mode_raw, "fast"))
            pipeline.IndexMode.fast
        else if (std.mem.eql(u8, mode_raw, "full"))
            pipeline.IndexMode.full
        else
            return self.errorResponse(request_id, -32602, "Unsupported index_repository mode");

        const normalized_path = std.fs.cwd().realpathAlloc(self.allocator, repo_path) catch try self.allocator.dupe(u8, repo_path);
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
            .{ project_name, indexModeText(mode), node_count, edge_count },
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
        const limit = intArg(args, "limit") orelse 100;
        const offset = intArg(args, "offset") orelse 0;

        if (stringArg(args, "query")) |query| {
            if (query.len > 0) {
                if (try search_index.buildFtsQuery(self.allocator, query, false)) |fts_query| {
                    defer self.allocator.free(fts_query);
                    const page = try self.db.searchGraphQuery(project, fts_query, limit, offset);
                    defer self.db.freeGraphQueryPage(page);

                    var query_payload = std.ArrayList(u8).empty;
                    try query_payload.writer(self.allocator).print(
                        "{{\"total\":{d},\"search_mode\":\"bm25\",\"results\":[",
                        .{page.total},
                    );
                    for (page.hits, 0..) |hit, idx| {
                        if (idx > 0) try query_payload.append(self.allocator, ',');
                        try query_payload.appendSlice(self.allocator, "{");
                        try appendJsonStringField(&query_payload, self.allocator, "name", hit.node.name, true);
                        try appendJsonStringField(&query_payload, self.allocator, "qualified_name", hit.node.qualified_name, false);
                        try appendJsonStringField(&query_payload, self.allocator, "label", hit.node.label, false);
                        try appendJsonStringField(&query_payload, self.allocator, "file_path", hit.node.file_path, false);
                        try appendJsonIntField(&query_payload, self.allocator, "start_line", hit.node.start_line, false);
                        try appendJsonIntField(&query_payload, self.allocator, "end_line", hit.node.end_line, false);
                        try query_payload.appendSlice(self.allocator, ",\"rank\":");
                        try query_payload.writer(self.allocator).print("{f}", .{std.json.fmt(hit.rank, .{})});
                        try query_payload.appendSlice(self.allocator, "}");
                    }
                    try query_payload.writer(self.allocator).print(
                        "],\"has_more\":{s}}}",
                        .{if (page.total > page.hits.len + offset) "true" else "false"},
                    );
                    const owned_query_payload = try query_payload.toOwnedSlice(self.allocator);
                    defer self.allocator.free(owned_query_payload);
                    return self.successResponse(request_id, owned_query_payload);
                }
            }
        }

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
            .limit = limit,
            .offset = offset,
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
            .{if (page.total > page.hits.len + offset) "true" else "false"},
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

        // Accept start_node_qn or function_name (C compat alias)
        const start_node_qn = stringArg(args, "start_node_qn") orelse stringArg(args, "function_name");
        if (start_node_qn == null) return self.errorResponse(request_id, -32602, "Missing start_node_qn or function_name");
        const qn = start_node_qn.?;

        const direction = stringArg(args, "direction") orelse "out";
        const max_depth = if (intArg(args, "depth")) |d| d else 6;
        const explicit_mode = stringArg(args, "mode");
        const mode = explicit_mode orelse "calls";
        const risk_labels = boolArg(args, "risk_labels") orelse false;
        const include_tests = boolArg(args, "include_tests") orelse false;

        // Resolve edge types: explicit edge_types > mode defaults.
        // The public contract treats omitted mode as "calls".
        const explicit_types = stringArrayArg(self.allocator, args, "edge_types");
        defer if (explicit_types) |et| self.allocator.free(et);
        const edge_types: ?[]const []const u8 = if (explicit_types) |et|
            et
        else
            resolveTraceEdgeTypes(mode);

        // Look up start node: try qualified name first, then exact name match
        const start = try self.db.findNodeByQualifiedName(project, qn) orelse
            try self.db.findNodeByName(project, qn) orelse
            return self.errorResponse(request_id, -32602, "Unknown start_node_qn");
        defer freeOwnedNode(self.allocator, start);

        const traversal_direction = parseTraversalDirection(direction) orelse
            return self.errorResponse(request_id, -32602, "Invalid direction");

        var payload = std.ArrayList(u8).empty;
        const w = payload.writer(self.allocator);

        // Top-level fields
        try w.print("{{\"function\":\"{s}\",\"direction\":\"{s}\",\"mode\":\"{s}\"", .{ start.name, direction, mode });

        // Run outbound traversal for callees
        var outbound_edges: []store.TraversalEdge = &.{};
        defer self.db.freeTraversalEdges(outbound_edges);
        if (traversal_direction == .outbound or traversal_direction == .both) {
            outbound_edges = try self.db.traverseEdgesBreadthFirst(project, start.id, .outbound, max_depth, edge_types, 100);
        }

        // Run inbound traversal for callers
        var inbound_edges: []store.TraversalEdge = &.{};
        defer self.db.freeTraversalEdges(inbound_edges);
        if (traversal_direction == .inbound or traversal_direction == .both) {
            inbound_edges = try self.db.traverseEdgesBreadthFirst(project, start.id, .inbound, max_depth, edge_types, 100);
        }

        // Emit a start-centered flat edge array that matches the upstream trace contract.
        try payload.appendSlice(self.allocator, ",\"edges\":[");
        {
            var edge_count: usize = 0;
            var emitted = std.StringHashMap(void).init(self.allocator);
            defer {
                var it = emitted.iterator();
                while (it.next()) |entry| self.allocator.free(entry.key_ptr.*);
                emitted.deinit();
            }

            for (outbound_edges) |edge| {
                const target = (try self.db.findNodeById(project, edge.target_id)) orelse continue;
                defer freeOwnedNode(self.allocator, target);

                const target_is_test = isTestFile(target.file_path);
                if (!include_tests and target_is_test) continue;

                const key = try std.fmt.allocPrint(self.allocator, "{s}|{s}|{s}", .{
                    start.qualified_name,
                    edge.edge_type,
                    target.qualified_name,
                });
                const entry = try emitted.getOrPut(key);
                if (entry.found_existing) {
                    self.allocator.free(key);
                    continue;
                }
                if (edge_count > 0) try payload.append(self.allocator, ',');
                try w.print(
                    "{{\"source\":\"{s}\",\"target\":\"{s}\",\"type\":\"{s}\"}}",
                    .{ start.qualified_name, target.qualified_name, edge.edge_type },
                );
                edge_count += 1;
            }

            for (inbound_edges) |edge| {
                const source = (try self.db.findNodeById(project, edge.source_id)) orelse continue;
                defer freeOwnedNode(self.allocator, source);

                const source_is_test = isTestFile(source.file_path);
                if (!include_tests and source_is_test) continue;

                const key = try std.fmt.allocPrint(self.allocator, "{s}|{s}|{s}", .{
                    source.qualified_name,
                    edge.edge_type,
                    start.qualified_name,
                });
                const entry = try emitted.getOrPut(key);
                if (entry.found_existing) {
                    self.allocator.free(key);
                    continue;
                }
                if (edge_count > 0) try payload.append(self.allocator, ',');
                try w.print(
                    "{{\"source\":\"{s}\",\"target\":\"{s}\",\"type\":\"{s}\"}}",
                    .{ source.qualified_name, start.qualified_name, edge.edge_type },
                );
                edge_count += 1;
            }
        }
        try payload.append(self.allocator, ']');

        // Emit structured callees
        try payload.appendSlice(self.allocator, ",\"callees\":[");
        {
            var callee_count: usize = 0;
            for (outbound_edges) |edge| {
                const target = (try self.db.findNodeById(project, edge.target_id)) orelse continue;
                defer freeOwnedNode(self.allocator, target);

                const target_is_test = isTestFile(target.file_path);
                if (!include_tests and target_is_test) continue;

                if (callee_count > 0) try payload.append(self.allocator, ',');
                try w.print("{{\"name\":\"{s}\",\"qualified_name\":\"{s}\",\"hop\":{d}", .{
                    target.name,
                    target.qualified_name,
                    edge.depth,
                });
                if (risk_labels) {
                    try w.print(",\"risk\":\"{s}\"", .{hopToRisk(edge.depth)});
                }
                if (target_is_test) {
                    try payload.appendSlice(self.allocator, ",\"is_test\":true");
                }
                try payload.append(self.allocator, '}');
                callee_count += 1;
            }
        }
        try payload.append(self.allocator, ']');

        // Emit structured callers
        try payload.appendSlice(self.allocator, ",\"callers\":[");
        {
            var caller_count: usize = 0;
            for (inbound_edges) |edge| {
                const source = (try self.db.findNodeById(project, edge.source_id)) orelse continue;
                defer freeOwnedNode(self.allocator, source);

                const source_is_test = isTestFile(source.file_path);
                if (!include_tests and source_is_test) continue;

                if (caller_count > 0) try payload.append(self.allocator, ',');
                try w.print("{{\"name\":\"{s}\",\"qualified_name\":\"{s}\",\"hop\":{d}", .{
                    source.name,
                    source.qualified_name,
                    edge.depth,
                });
                if (risk_labels) {
                    try w.print(",\"risk\":\"{s}\"", .{hopToRisk(edge.depth)});
                }
                if (source_is_test) {
                    try payload.appendSlice(self.allocator, ",\"is_test\":true");
                }
                try payload.append(self.allocator, '}');
                caller_count += 1;
            }
        }
        try payload.append(self.allocator, ']');

        try payload.append(self.allocator, '}');
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
        var router = query_router.QueryRouter.init(self.allocator, self.db);
        const payload = router.getCodeSnippetPayload(.{
            .project = project,
            .qualified_name = qualified_name,
            .include_neighbors = include_neighbors,
        }) catch |err| switch (err) {
            error.UnknownProject => return self.errorResponse(request_id, -32602, "Unknown project"),
            error.SymbolNotFound => return self.errorResponse(
                request_id,
                -32602,
                "symbol not found. Use search_graph(name_pattern=\"...\") first to discover the exact qualified_name, then pass it to get_code_snippet.",
            ),
            else => return err,
        };
        defer self.allocator.free(payload);
        return self.successResponse(request_id, payload);
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
        var router = query_router.QueryRouter.init(self.allocator, self.db);
        const payload = router.getArchitecturePayload(.{
            .project = project,
            .include_structure = aspectWanted(args, "structure"),
            .include_dependencies = aspectWanted(args, "dependencies"),
            .include_languages = explicitArchitectureAspectWanted(args, "languages"),
            .include_packages = explicitArchitectureAspectWanted(args, "packages"),
            .include_hotspots = explicitArchitectureAspectWanted(args, "hotspots"),
            .include_entry_points = explicitArchitectureAspectWanted(args, "entry_points"),
            .include_routes = explicitArchitectureAspectWanted(args, "route_summaries"),
            .include_messages = explicitArchitectureAspectWanted(args, "message_summaries"),
        }) catch |err| switch (err) {
            error.UnknownProject => return self.errorResponse(request_id, -32602, "Unknown project"),
            else => return err,
        };
        defer self.allocator.free(payload);
        return self.successResponse(request_id, payload);
    }

    fn handleSearchCode(self: *McpServer, request_id: ?std.json.Value, args: std.json.Value) !?[]const u8 {
        const project = stringArg(args, "project") orelse return self.errorResponse(request_id, -32602, "Missing project");
        const pattern = stringArg(args, "pattern") orelse return self.errorResponse(request_id, -32602, "Missing pattern");
        var router = query_router.QueryRouter.init(self.allocator, self.db);
        const payload = router.searchCodePayload(.{
            .project = project,
            .pattern = pattern,
            .mode = parseSearchCodeMode(stringArg(args, "mode")),
            .file_pattern = stringArg(args, "file_pattern"),
            .path_filter = stringArg(args, "path_filter"),
            .regex = boolArg(args, "regex") orelse false,
            .limit = intArg(args, "limit") orelse 25,
            .context = intArg(args, "context") orelse 0,
        }) catch |err| switch (err) {
            error.UnknownProject => return self.errorResponse(request_id, -32602, "Unknown project"),
            else => return err,
        };
        defer self.allocator.free(payload);
        return self.successResponse(request_id, payload);
    }

    fn handleDetectChanges(self: *McpServer, request_id: ?std.json.Value, args: std.json.Value) !?[]const u8 {
        const project = stringArg(args, "project") orelse return self.errorResponse(request_id, -32602, "Missing project");
        var router = query_router.QueryRouter.init(self.allocator, self.db);
        const payload = router.detectChangesPayload(.{
            .project = project,
            .base_branch = stringArg(args, "base_branch") orelse "main",
            .since = stringArg(args, "since"),
            .scope = stringArg(args, "scope"),
            .depth = intArg(args, "depth") orelse 3,
        }) catch |err| switch (err) {
            error.UnknownProject => return self.errorResponse(request_id, -32602, "Unknown project"),
            error.InvalidSinceSelector => return self.errorResponse(request_id, -32602, "Invalid since selector"),
            else => return err,
        };
        defer self.allocator.free(payload);
        return self.successResponse(request_id, payload);
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

    fn handleIngestTraces(self: *McpServer, request_id: ?std.json.Value, args: std.json.Value) !?[]const u8 {
        _ = stringArg(args, "project") orelse return self.errorResponse(request_id, -32602, "Missing project");
        if (args != .object) return self.errorResponse(request_id, -32602, "Missing traces");
        const traces = args.object.get("traces") orelse return self.errorResponse(request_id, -32602, "Missing traces");
        if (traces != .array) return self.errorResponse(request_id, -32602, "Invalid traces");

        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"status\":\"accepted\",\"traces_received\":{d},\"note\":\"Runtime edge creation from traces not yet implemented\"}}",
            .{traces.array.items.len},
        );
        defer self.allocator.free(payload);
        return self.successResponse(request_id, payload);
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
        const owned = try response.toOwnedSlice(self.allocator);
        if (owned.len <= max_response_bytes) return owned;
        self.allocator.free(owned);
        return self.errorResponse(request_id, response_too_large_code, "Response too large");
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

const SearchCodeMode = query_router.SearchCodeMode;

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

fn negotiatedProtocolVersion(params: ?std.json.Value) []const u8 {
    if (params) |value| {
        if (value == .object) {
            if (value.object.get("protocolVersion")) |version| {
                if (version == .string and isSupportedProtocolVersion(version.string)) {
                    return version.string;
                }
            }
        }
    }
    return supported_protocol_versions[0];
}

fn isSupportedProtocolVersion(version: []const u8) bool {
    for (supported_protocol_versions) |candidate| {
        if (std.mem.eql(u8, version, candidate)) return true;
    }
    return false;
}

fn indexRepositoryPathArg(args: std.json.Value) ?[]const u8 {
    return stringArg(args, "repo_path") orelse stringArg(args, "project_path");
}

fn indexModeText(mode: pipeline.IndexMode) []const u8 {
    return switch (mode) {
        .full => "full",
        .fast => "fast",
    };
}

fn signedIntArg(value: std.json.Value, key: []const u8) ?i32 {
    if (value != .object) return null;
    const child = value.object.get(key) orelse return null;
    return switch (child) {
        .integer => |v| std.math.cast(i32, v),
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

fn nowMillis() u64 {
    const now = std.time.milliTimestamp();
    return if (now <= 0) 0 else @intCast(now);
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
    if (std.mem.eql(u8, name, "ingest_traces")) return .ingest_traces;
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
        .integer => |v| std.math.cast(u32, v),
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

/// Extract a JSON array of strings from a named argument.
/// Returns null if the key is missing or the value is not an array.
/// Caller must free the returned slice with `allocator.free(result)`.
fn stringArrayArg(allocator: std.mem.Allocator, value: std.json.Value, key: []const u8) ?[]const []const u8 {
    if (value != .object) return null;
    const child = value.object.get(key) orelse return null;
    if (child != .array) return null;
    const items = child.array.items;
    if (items.len == 0) return null;

    var out = allocator.alloc([]const u8, items.len) catch return null;
    var count: usize = 0;
    for (items) |item| {
        switch (item) {
            .string => |s| {
                out[count] = s;
                count += 1;
            },
            else => {},
        }
    }
    if (count == 0) {
        allocator.free(out);
        return null;
    }
    return out[0..count];
}

/// Resolve trace edge types from mode and optional explicit override.
/// Priority: explicit edge_types > mode defaults > "CALLS" fallback.
fn resolveTraceEdgeTypes(mode: []const u8) []const []const u8 {
    if (std.mem.eql(u8, mode, "data_flow")) {
        return &.{ "CALLS", "DATA_FLOWS" };
    }
    if (std.mem.eql(u8, mode, "cross_service")) {
        return &.{ "HTTP_CALLS", "ASYNC_CALLS", "EMITS", "SUBSCRIBES", "DATA_FLOWS", "CALLS" };
    }
    // Default: "calls" mode or any unrecognized mode
    return &.{"CALLS"};
}

/// Map BFS hop distance to risk classification label.
fn hopToRisk(hop: u32) []const u8 {
    return switch (hop) {
        1 => "CRITICAL",
        2 => "HIGH",
        3 => "MEDIUM",
        else => "LOW",
    };
}

/// Heuristic test-file detection based on path patterns.
fn isTestFile(file_path: []const u8) bool {
    if (std.mem.indexOf(u8, file_path, "/test/") != null) return true;
    if (std.mem.indexOf(u8, file_path, "/tests/") != null) return true;
    if (std.mem.indexOf(u8, file_path, "/spec/") != null) return true;
    if (std.mem.indexOf(u8, file_path, "test_") != null) return true;
    if (std.mem.indexOf(u8, file_path, "_test.") != null) return true;
    if (std.mem.indexOf(u8, file_path, ".test.") != null) return true;
    return false;
}

fn jsonValueToString(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    // Note: .string intentionally falls through to the generic std.json.fmt
    // branch below so that double-quotes, backslashes, and control characters
    // in the string are properly JSON-escaped.
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
    try std.testing.expectEqual(SupportedTool.ingest_traces, try SupportedToolFromString("ingest_traces"));
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

test "tools/list advertises ingest_traces, repo_path, detect_changes since, and search_graph query" {
    var s = try store.Store.openMemory(std.testing.allocator);
    defer s.deinit();
    var srv = McpServer.init(std.testing.allocator, &s);
    defer srv.deinit();

    const response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":43,"method":"tools/list","params":{}}
    )).?;
    defer std.testing.allocator.free(response);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"ingest_traces\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"repo_path\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"since\":{\"type\":\"string\",\"description\":\"Git ref or date to compare from (e.g. HEAD~5, v0.5.0, 2026-01-01)\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"query\":{\"type\":\"string\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"project_path\"") == null);
}

test "initialize negotiates supported protocol versions" {
    var s = try store.Store.openMemory(std.testing.allocator);
    defer s.deinit();
    var srv = McpServer.init(std.testing.allocator, &s);
    defer srv.deinit();

    const supported_response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":44,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}
    )).?;
    defer std.testing.allocator.free(supported_response);
    try std.testing.expect(std.mem.indexOf(u8, supported_response, "\"protocolVersion\":\"2024-11-05\"") != null);

    const fallback_response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":45,"method":"initialize","params":{"protocolVersion":"2026-01-01"}}
    )).?;
    defer std.testing.allocator.free(fallback_response);
    try std.testing.expect(std.mem.indexOf(u8, fallback_response, "\"protocolVersion\":\"2025-11-25\"") != null);
}

test "successResponse converts oversized payloads into deterministic errors" {
    var s = try store.Store.openMemory(std.testing.allocator);
    defer s.deinit();
    var srv = McpServer.init(std.testing.allocator, &s);
    defer srv.deinit();

    const payload = try std.testing.allocator.alloc(u8, max_response_bytes + 1);
    defer std.testing.allocator.free(payload);
    @memset(payload, 'a');

    const response = (try srv.successResponse(.{ .integer = 1 }, payload)).?;
    defer std.testing.allocator.free(response);

    try std.testing.expect(std.mem.indexOf(u8, response, "\"error\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"Response too large\"") != null);
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

test "trace_call_path returns structured callees and callers" {
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

    // Test outbound trace with new structured format
    const response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"trace_call_path","arguments":{"project":"demo","start_node_qn":"demo:start","direction":"outbound","depth":2}}}
    )).?;
    defer std.testing.allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, response, .{});
    defer parsed.deinit();

    const result = parsed.value.object.get("result").?;
    // Verify top-level fields
    try std.testing.expectEqualStrings("start", result.object.get("function").?.string);
    try std.testing.expectEqualStrings("outbound", result.object.get("direction").?.string);
    try std.testing.expectEqualStrings("calls", result.object.get("mode").?.string);

    // Verify flat edges array (backward compat)
    const edges = result.object.get("edges").?.array;
    try std.testing.expectEqual(@as(usize, 1), edges.items.len);
    try std.testing.expectEqualStrings("demo:start", edges.items[0].object.get("source").?.string);
    try std.testing.expectEqualStrings("demo:finish", edges.items[0].object.get("target").?.string);

    // Verify callees
    const callees = result.object.get("callees").?.array;
    try std.testing.expectEqual(@as(usize, 1), callees.items.len);
    try std.testing.expectEqualStrings("finish", callees.items[0].object.get("name").?.string);
    try std.testing.expectEqualStrings("demo:finish", callees.items[0].object.get("qualified_name").?.string);
    try std.testing.expectEqual(@as(i64, 1), callees.items[0].object.get("hop").?.integer);

    // Verify callers is empty for outbound direction
    const callers = result.object.get("callers").?.array;
    try std.testing.expectEqual(@as(usize, 0), callers.items.len);
}

test "trace_call_path function_name alias works" {
    var s = try store.Store.openMemory(std.testing.allocator);
    defer s.deinit();
    try s.upsertProject("demo", "/tmp/demo");
    const source_id = try s.upsertNode(.{
        .project = "demo",
        .label = "Function",
        .name = "entry",
        .qualified_name = "demo:entry",
        .file_path = "main.py",
    });
    const target_id = try s.upsertNode(.{
        .project = "demo",
        .label = "Function",
        .name = "worker",
        .qualified_name = "demo:worker",
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

    // Use function_name instead of start_node_qn
    const response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"trace_call_path","arguments":{"project":"demo","function_name":"entry","direction":"out","depth":1}}}
    )).?;
    defer std.testing.allocator.free(response);

    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, response, .{});
    defer parsed.deinit();

    const result = parsed.value.object.get("result").?;
    try std.testing.expectEqualStrings("entry", result.object.get("function").?.string);
    const callees = result.object.get("callees").?.array;
    try std.testing.expectEqual(@as(usize, 1), callees.items.len);
    try std.testing.expectEqualStrings("worker", callees.items[0].object.get("name").?.string);
}

test "trace_call_path risk_labels and include_tests" {
    var s = try store.Store.openMemory(std.testing.allocator);
    defer s.deinit();
    try s.upsertProject("demo", "/tmp/demo");
    const main_id = try s.upsertNode(.{
        .project = "demo",
        .label = "Function",
        .name = "main",
        .qualified_name = "demo:main",
        .file_path = "app.py",
    });
    const helper_id = try s.upsertNode(.{
        .project = "demo",
        .label = "Function",
        .name = "helper",
        .qualified_name = "demo:helper",
        .file_path = "app.py",
    });
    const test_id = try s.upsertNode(.{
        .project = "demo",
        .label = "Function",
        .name = "test_main",
        .qualified_name = "demo:test_main",
        .file_path = "test_app.py",
    });
    _ = try s.upsertEdge(.{
        .project = "demo",
        .source_id = main_id,
        .target_id = helper_id,
        .edge_type = "CALLS",
    });
    _ = try s.upsertEdge(.{
        .project = "demo",
        .source_id = test_id,
        .target_id = main_id,
        .edge_type = "CALLS",
    });

    var srv = McpServer.init(std.testing.allocator, &s);
    defer srv.deinit();

    // Test with risk_labels=true and explicit include_tests=true
    {
        const response = (try srv.handleRequest(
            \\{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"trace_call_path","arguments":{"project":"demo","start_node_qn":"demo:main","direction":"both","depth":2,"risk_labels":true,"include_tests":true}}}
        )).?;
        defer std.testing.allocator.free(response);

        const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, response, .{});
        defer parsed.deinit();

        const result = parsed.value.object.get("result").?;
        const callees = result.object.get("callees").?.array;
        try std.testing.expectEqual(@as(usize, 1), callees.items.len);
        try std.testing.expectEqualStrings("CRITICAL", callees.items[0].object.get("risk").?.string);

        const callers = result.object.get("callers").?.array;
        try std.testing.expectEqual(@as(usize, 1), callers.items.len);
        try std.testing.expectEqualStrings("CRITICAL", callers.items[0].object.get("risk").?.string);
        // test_main is in test_app.py, should have is_test marker
        try std.testing.expectEqual(true, callers.items[0].object.get("is_test").?.bool);
    }

    // Default behavior should exclude tests.
    {
        const response = (try srv.handleRequest(
            \\{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"trace_call_path","arguments":{"project":"demo","start_node_qn":"demo:main","direction":"both","depth":2}}}
        )).?;
        defer std.testing.allocator.free(response);

        const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, response, .{});
        defer parsed.deinit();

        const result = parsed.value.object.get("result").?;
        // Callers should exclude test_main (which is in test_app.py)
        const callers = result.object.get("callers").?.array;
        try std.testing.expectEqual(@as(usize, 0), callers.items.len);
    }
}

test "trace_call_path mode parameter selects edge types" {
    var s = try store.Store.openMemory(std.testing.allocator);
    defer s.deinit();
    try s.upsertProject("demo", "/tmp/demo");
    const a_id = try s.upsertNode(.{
        .project = "demo",
        .label = "Function",
        .name = "service_a",
        .qualified_name = "demo:service_a",
        .file_path = "service.py",
    });
    const b_id = try s.upsertNode(.{
        .project = "demo",
        .label = "Function",
        .name = "service_b",
        .qualified_name = "demo:service_b",
        .file_path = "service.py",
    });
    const c_id = try s.upsertNode(.{
        .project = "demo",
        .label = "Function",
        .name = "service_c",
        .qualified_name = "demo:service_c",
        .file_path = "service.py",
    });
    // CALLS edge
    _ = try s.upsertEdge(.{
        .project = "demo",
        .source_id = a_id,
        .target_id = b_id,
        .edge_type = "CALLS",
    });
    // DATA_FLOWS edge
    _ = try s.upsertEdge(.{
        .project = "demo",
        .source_id = a_id,
        .target_id = c_id,
        .edge_type = "DATA_FLOWS",
    });

    var srv = McpServer.init(std.testing.allocator, &s);
    defer srv.deinit();

    // mode=calls should only find CALLS edges
    {
        const response = (try srv.handleRequest(
            \\{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"trace_call_path","arguments":{"project":"demo","start_node_qn":"demo:service_a","direction":"out","depth":1,"mode":"calls"}}}
        )).?;
        defer std.testing.allocator.free(response);

        const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, response, .{});
        defer parsed.deinit();

        const callees = parsed.value.object.get("result").?.object.get("callees").?.array;
        try std.testing.expectEqual(@as(usize, 1), callees.items.len);
        try std.testing.expectEqualStrings("service_b", callees.items[0].object.get("name").?.string);
    }

    // mode=data_flow should find CALLS + DATA_FLOWS edges
    {
        const response = (try srv.handleRequest(
            \\{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"trace_call_path","arguments":{"project":"demo","start_node_qn":"demo:service_a","direction":"out","depth":1,"mode":"data_flow"}}}
        )).?;
        defer std.testing.allocator.free(response);

        const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, response, .{});
        defer parsed.deinit();

        const callees = parsed.value.object.get("result").?.object.get("callees").?.array;
        try std.testing.expectEqual(@as(usize, 2), callees.items.len);
    }
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
    try std.testing.expect(result.get("languages").?.array.items.len >= 1);
    const language = result.get("languages").?.array.items[0].object.get("language").?.string;
    try std.testing.expectEqualStrings("python", language);
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
        "{{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"tools/call\",\"params\":{{\"name\":\"index_repository\",\"arguments\":{{\"repo_path\":\"{s}\"}}}}}}",
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

    const stdin_reader = std.fs.File{ .handle = stdin_pipe[0] };
    defer stdin_reader.close();
    var stdin_writer = std.fs.File{ .handle = stdin_pipe[1] };

    var stdout_reader = std.fs.File{ .handle = stdout_pipe[0] };
    defer stdout_reader.close();
    var stdout_writer = std.fs.File{ .handle = stdout_pipe[1] };

    const input = try std.fmt.allocPrint(
        allocator,
        "{{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{{}}}}\n" ++
            "{{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{{\"name\":\"index_repository\",\"arguments\":{{\"repo_path\":\"{s}\"}}}}}}\n",
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

const RunFilesThreadContext = struct {
    server: *McpServer,
    stdin_file: std.fs.File,
    stdout_file: std.fs.File,
    err: ?anyerror = null,
};

fn runFilesThread(ctx: *RunFilesThreadContext) void {
    defer ctx.stdin_file.close();
    defer ctx.stdout_file.close();
    ctx.server.runFiles(ctx.stdin_file, ctx.stdout_file) catch |err| {
        ctx.err = err;
    };
}

test "runFiles rejects oversized request lines and continues after newline" {
    const allocator = std.testing.allocator;

    var s = try store.Store.openMemory(allocator);
    defer s.deinit();
    var srv = McpServer.init(allocator, &s);
    defer srv.deinit();

    const stdin_pipe = try std.posix.pipe();
    const stdout_pipe = try std.posix.pipe();

    const stdin_reader = std.fs.File{ .handle = stdin_pipe[0] };
    var stdin_writer = std.fs.File{ .handle = stdin_pipe[1] };

    var stdout_reader = std.fs.File{ .handle = stdout_pipe[0] };
    defer stdout_reader.close();
    var run_ctx = RunFilesThreadContext{
        .server = &srv,
        .stdin_file = stdin_reader,
        .stdout_file = std.fs.File{ .handle = stdout_pipe[1] },
    };
    const thread = try std.Thread.spawn(.{}, runFilesThread, .{&run_ctx});
    defer thread.join();

    const oversized_line = try allocator.alloc(u8, max_request_line_bytes + 1);
    defer allocator.free(oversized_line);
    @memset(oversized_line, 'a');

    const valid_tail =
        \\{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
        \\
    ;

    try stdin_writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}\n");
    try stdin_writer.writeAll(oversized_line);
    try stdin_writer.writeAll("\n");
    try stdin_writer.writeAll(valid_tail);
    stdin_writer.close();

    const output = try stdout_reader.readToEndAlloc(allocator, 2 * 1024 * 1024);
    defer allocator.free(output);
    try std.testing.expect(run_ctx.err == null);

    var responses = std.mem.splitScalar(u8, output, '\n');
    const initialize_response = responses.next() orelse return error.Unexpected;
    const oversized_response = responses.next() orelse return error.Unexpected;
    const tools_response = responses.next() orelse return error.Unexpected;

    try std.testing.expect(std.mem.indexOf(u8, initialize_response, "\"protocolVersion\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, oversized_response, "\"Request too large\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, tools_response, "\"tools\"") != null);
}

test "notifications are ignored without a response" {
    var s = try store.Store.openMemory(std.testing.allocator);
    defer s.deinit();

    var srv = McpServer.init(std.testing.allocator, &s);
    defer srv.deinit();

    const response = try srv.handleRequest(
        \\{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}
    );
    try std.testing.expect(response == null);
}

test "notifications do not consume the first update notice response" {
    const allocator = std.testing.allocator;

    var s = try store.Store.openMemory(allocator);
    defer s.deinit();
    var srv = McpServer.init(allocator, &s);
    defer srv.deinit();

    var lifecycle = runtime_lifecycle.RuntimeLifecycle.init(allocator, "0.0.0");
    defer lifecycle.deinit();
    srv.setRuntimeLifecycle(&lifecycle);
    lifecycle.update_notice = try allocator.dupe(u8, "Update available: 0.0.0 -> 9.9.9 -- run: cbm update");

    const initialize_response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
    )).?;
    defer allocator.free(initialize_response);

    const notification_response = try srv.handleRequest(
        \\{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}
    );
    try std.testing.expect(notification_response == null);

    const tools_response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
    )).?;
    defer allocator.free(tools_response);

    try std.testing.expect(std.mem.indexOf(u8, initialize_response, "\"protocolVersion\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, tools_response, "\"update_notice\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, tools_response, "Update available: 0.0.0 -> 9.9.9") != null);
}

test "ingest_traces returns accepted stub payload" {
    var s = try store.Store.openMemory(std.testing.allocator);
    defer s.deinit();
    var srv = McpServer.init(std.testing.allocator, &s);
    defer srv.deinit();

    const response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":46,"method":"tools/call","params":{"name":"ingest_traces","arguments":{"project":"demo","traces":[{"kind":"span"},{"kind":"span"}]}}}
    )).?;
    defer std.testing.allocator.free(response);

    try std.testing.expect(std.mem.indexOf(u8, response, "\"status\":\"accepted\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"traces_received\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "not yet implemented") != null);
}

test "idle store eviction closes the runtime db and reopens on the next tool call" {
    const allocator = std.testing.allocator;
    var temp_dir = std.testing.tmpDir(.{});
    defer temp_dir.cleanup();

    const temp_root = try temp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(temp_root);
    const db_path = try std.fs.path.join(allocator, &.{ temp_root, "runtime.db" });
    defer allocator.free(db_path);
    const db_path_z = try allocator.dupeZ(u8, db_path);
    defer allocator.free(db_path_z);

    var s = try store.Store.openPath(allocator, db_path_z);
    defer s.deinit();

    var srv = McpServer.init(allocator, &s);
    defer srv.deinit();
    srv.setRuntimeStorePath(db_path);
    srv.setIdleStoreTimeoutMs(50);
    srv.noteStoreActivityAt(100);

    try std.testing.expect(s.db != null);
    srv.evictIdleStoreIfNeededAt(151);
    try std.testing.expect(s.db == null);

    const response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_projects","arguments":{}}}
    )).?;
    defer allocator.free(response);

    try std.testing.expect(s.db != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"projects\"") != null);
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

test "trace_call_path defaults omitted mode to calls" {
    var s = try store.Store.openMemory(std.testing.allocator);
    defer s.deinit();
    try s.upsertProject("demo", "/tmp/demo");
    const start_id = try s.upsertNode(.{
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
        .source_id = start_id,
        .target_id = target_id,
        .edge_type = "CALLS",
    });
    _ = try s.upsertEdge(.{
        .project = "demo",
        .source_id = start_id,
        .target_id = target_id,
        .edge_type = "USAGE",
    });

    var srv = McpServer.init(std.testing.allocator, &s);
    defer srv.deinit();

    const response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":21,"method":"tools/call","params":{"name":"trace_call_path","arguments":{"project":"demo","start_node_qn":"demo:start","direction":"out","depth":1}}}
    )).?;
    defer std.testing.allocator.free(response);

    try std.testing.expect(std.mem.indexOf(u8, response, "\"mode\":\"calls\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"type\":\"CALLS\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"type\":\"USAGE\"") == null);
}

test "get_code_snippet file stem suffix resolves colon qualified names" {
    var s = try store.Store.openMemory(std.testing.allocator);
    defer s.deinit();
    try s.upsertProject("demo", "/tmp/demo");
    _ = try s.upsertNode(.{
        .project = "demo",
        .label = "Function",
        .name = "entry",
        .qualified_name = "demo:main.py:python:symbol:python:entry",
        .file_path = "main.py",
        .start_line = 1,
        .end_line = 2,
    });

    var srv = McpServer.init(std.testing.allocator, &s);
    defer srv.deinit();

    const response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":22,"method":"tools/call","params":{"name":"get_code_snippet","arguments":{"project":"demo","qualified_name":"main.entry"}}}
    )).?;
    defer std.testing.allocator.free(response);

    try std.testing.expect(std.mem.indexOf(u8, response, "\"name\":\"entry\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"match_method\":\"suffix\"") != null);
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

test "search_graph query returns bm25-ranked results and falls back when terms are unusable" {
    var s = try store.Store.openMemory(std.testing.allocator);
    defer s.deinit();
    try s.upsertProject("demo", "/tmp/demo");

    _ = try s.upsertNode(.{
        .project = "demo",
        .label = "Function",
        .name = "update_settings",
        .qualified_name = "demo.update_settings",
        .file_path = "src/main.py",
        .start_line = 1,
        .end_line = 3,
    });
    _ = try s.upsertNode(.{
        .project = "demo",
        .label = "Class",
        .name = "SettingsWorker",
        .qualified_name = "demo.SettingsWorker",
        .file_path = "src/worker.py",
        .start_line = 1,
        .end_line = 5,
    });
    _ = try s.upsertNode(.{
        .project = "demo",
        .label = "Function",
        .name = "beta",
        .qualified_name = "demo.beta",
        .file_path = "src/fallback.py",
        .start_line = 1,
        .end_line = 2,
    });
    _ = try s.upsertNode(.{
        .project = "demo",
        .label = "Variable",
        .name = "settings_value",
        .qualified_name = "demo.settings_value",
        .file_path = "src/main.py",
        .start_line = 4,
        .end_line = 4,
    });
    try s.insertSearchDocument("demo", "src/main.py", "def update_settings():\n    return cloud settings\n");
    try s.insertSearchDocument("demo", "src/worker.py", "class SettingsWorker:\n    def update_cloud_client(self):\n        return settings\n");
    try s.insertSearchDocument("demo", "src/fallback.py", "def beta():\n    return 1\n");

    var srv = McpServer.init(std.testing.allocator, &s);
    defer srv.deinit();

    const query_response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":23,"method":"tools/call","params":{"name":"search_graph","arguments":{"project":"demo","query":"update settings","name_pattern":"beta","limit":1,"offset":0}}}
    )).?;
    defer std.testing.allocator.free(query_response);

    const query_parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, query_response, .{});
    defer query_parsed.deinit();
    const query_result = query_parsed.value.object.get("result").?.object;
    try std.testing.expectEqualStrings("bm25", query_result.get("search_mode").?.string);
    try std.testing.expectEqual(@as(i64, 2), query_result.get("total").?.integer);
    try std.testing.expectEqual(true, query_result.get("has_more").?.bool);
    const query_hits = query_result.get("results").?.array;
    try std.testing.expectEqual(@as(usize, 1), query_hits.items.len);
    try std.testing.expectEqualStrings("update_settings", query_hits.items[0].object.get("name").?.string);
    try std.testing.expect(query_hits.items[0].object.get("rank") != null);

    const fallback_response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":24,"method":"tools/call","params":{"name":"search_graph","arguments":{"project":"demo","query":"x","name_pattern":"beta","limit":5}}}
    )).?;
    defer std.testing.allocator.free(fallback_response);

    const fallback_parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, fallback_response, .{});
    defer fallback_parsed.deinit();
    const fallback_result = fallback_parsed.value.object.get("result").?.object;
    try std.testing.expect(fallback_result.get("search_mode") == null);
    const fallback_hits = fallback_result.get("results").?.array;
    try std.testing.expectEqual(@as(usize, 1), fallback_hits.items.len);
    try std.testing.expectEqualStrings("beta", fallback_hits.items[0].object.get("name").?.string);
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

test "detect_changes supports since refs, dates, and invalid selectors" {
    const allocator = std.testing.allocator;
    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(allocator, "/tmp/cbm-phase5-since-{x}", .{project_id});
    defer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};
    const src_dir = try std.fs.path.join(allocator, &.{ project_dir, "src" });
    defer allocator.free(src_dir);
    try std.fs.cwd().makePath(src_dir);

    const main_path = try std.fs.path.join(allocator, &.{ project_dir, "src", "main.py" });
    defer allocator.free(main_path);

    try runTestCommand(allocator, &.{ "git", "-C", project_dir, "init", "-b", "main" });
    try runTestCommand(allocator, &.{ "git", "-C", project_dir, "config", "user.email", "tests@example.com" });
    try runTestCommand(allocator, &.{ "git", "-C", project_dir, "config", "user.name", "Phase Five Tests" });

    {
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
    }
    try runTestCommand(allocator, &.{ "git", "-C", project_dir, "add", "." });
    try runTestCommand(allocator, &.{
        "env",
        "GIT_AUTHOR_DATE=2026-04-18T12:00:00Z",
        "GIT_COMMITTER_DATE=2026-04-18T12:00:00Z",
        "git",
        "-C",
        project_dir,
        "commit",
        "-m",
        "initial",
    });

    {
        var updated_file = try std.fs.cwd().createFile(main_path, .{ .truncate = true });
        defer updated_file.close();
        try updated_file.writeAll(
            \\def run():
            \\    return helper() + 1
            \\
            \\def helper():
            \\    return 2
            \\
        );
    }
    try runTestCommand(allocator, &.{ "git", "-C", project_dir, "add", "." });
    try runTestCommand(allocator, &.{
        "env",
        "GIT_AUTHOR_DATE=2026-04-20T12:00:00Z",
        "GIT_COMMITTER_DATE=2026-04-20T12:00:00Z",
        "git",
        "-C",
        project_dir,
        "commit",
        "-m",
        "update",
    });

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

    const ref_response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":16,"method":"tools/call","params":{"name":"detect_changes","arguments":{"project":"demo","since":"HEAD~1","depth":2}}}
    )).?;
    defer allocator.free(ref_response);

    const ref_parsed = try std.json.parseFromSlice(std.json.Value, allocator, ref_response, .{});
    defer ref_parsed.deinit();
    const ref_result = ref_parsed.value.object.get("result").?.object;
    try std.testing.expectEqual(@as(i64, 1), ref_result.get("changed_count").?.integer);
    try std.testing.expectEqualStrings("HEAD~1", ref_result.get("since").?.string);
    try std.testing.expect(ref_result.get("impacted_symbols").?.array.items.len >= 2);

    const date_response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":17,"method":"tools/call","params":{"name":"detect_changes","arguments":{"project":"demo","since":"2026-04-19","depth":2}}}
    )).?;
    defer allocator.free(date_response);

    const date_parsed = try std.json.parseFromSlice(std.json.Value, allocator, date_response, .{});
    defer date_parsed.deinit();
    const date_result = date_parsed.value.object.get("result").?.object;
    try std.testing.expectEqual(@as(i64, 1), date_result.get("changed_count").?.integer);
    try std.testing.expectEqualStrings("2026-04-19", date_result.get("since").?.string);
    try std.testing.expect(date_result.get("impacted_symbols").?.array.items.len >= 2);

    const invalid_response = (try srv.handleRequest(
        \\{"jsonrpc":"2.0","id":18,"method":"tools/call","params":{"name":"detect_changes","arguments":{"project":"demo","since":"not-a-ref-or-date","depth":2}}}
    )).?;
    defer allocator.free(invalid_response);

    const invalid_parsed = try std.json.parseFromSlice(std.json.Value, allocator, invalid_response, .{});
    defer invalid_parsed.deinit();
    const invalid_error = invalid_parsed.value.object.get("error").?.object;
    try std.testing.expectEqual(@as(i64, -32602), invalid_error.get("code").?.integer);
    try std.testing.expectEqualStrings("Invalid since selector", invalid_error.get("message").?.string);
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

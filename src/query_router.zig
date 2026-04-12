const std = @import("std");
const discover = @import("discover.zig");
const scip = @import("scip.zig");
const search_index = @import("search_index.zig");
const store = @import("store.zig");
const text_match = @import("text_match.zig");

const Store = store.Store;

pub const SearchCodeMode = enum { compact, full, files };

pub const SearchCodeRequest = struct {
    project: []const u8,
    pattern: []const u8,
    mode: SearchCodeMode = .compact,
    file_pattern: ?[]const u8 = null,
    path_filter: ?[]const u8 = null,
    regex: bool = false,
    limit: usize = 25,
    context: usize = 0,
};

pub const SnippetRequest = struct {
    project: []const u8,
    qualified_name: []const u8,
    include_neighbors: bool = false,
};

pub const ArchitectureRequest = struct {
    project: []const u8,
    include_structure: bool = true,
    include_dependencies: bool = true,
    include_languages: bool = false,
    include_packages: bool = false,
    include_hotspots: bool = false,
    include_entry_points: bool = false,
    include_routes: bool = false,
};

pub const DetectChangesRequest = struct {
    project: []const u8,
    base_branch: []const u8 = "main",
    scope: ?[]const u8 = null,
    depth: usize = 3,
};

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

const SnippetLineRange = struct {
    start_line: i32,
    end_line: i32,
};

pub const QueryRouter = struct {
    allocator: std.mem.Allocator,
    db: *Store,

    pub fn init(allocator: std.mem.Allocator, db: *Store) QueryRouter {
        return .{ .allocator = allocator, .db = db };
    }

    pub fn searchCodePayload(self: *QueryRouter, request: SearchCodeRequest) ![]u8 {
        const status = try self.db.getProjectStatus(request.project);
        defer self.db.freeProjectStatus(status);
        if (status.status == .not_found) return error.UnknownProject;

        const hits = try collectSearchCodeHits(
            self.allocator,
            self.db,
            request.project,
            status.root_path,
            request.pattern,
            request.mode,
            request.file_pattern,
            request.path_filter,
            request.regex,
            request.limit,
            request.context,
        );
        defer freeCodeSearchHits(self.allocator, hits);

        var payload = std.ArrayList(u8).empty;
        try payload.appendSlice(self.allocator, "{");
        try appendJsonStringField(&payload, self.allocator, "mode", searchCodeModeText(request.mode), true);
        try appendJsonIntField(&payload, self.allocator, "total", @as(i64, @intCast(hits.len)), false);
        try payload.appendSlice(self.allocator, ",\"results\":[");
        for (hits, 0..) |hit, idx| {
            if (idx > 0) try payload.append(self.allocator, ',');
            try payload.appendSlice(self.allocator, "{");
            try appendJsonStringField(&payload, self.allocator, "file", hit.file_path, true);
            try appendJsonStringField(&payload, self.allocator, "file_path", hit.file_path, false);
            if (request.mode != .files) {
                try appendJsonIntField(&payload, self.allocator, "line", @as(i64, @intCast(hit.line)), false);
                if (hit.start_line > 0) try appendJsonIntField(&payload, self.allocator, "start_line", hit.start_line, false);
                if (hit.end_line > 0) try appendJsonIntField(&payload, self.allocator, "end_line", hit.end_line, false);
                if (request.mode == .full or hit.name == null) {
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
        return try payload.toOwnedSlice(self.allocator);
    }

    pub fn getCodeSnippetPayload(self: *QueryRouter, request: SnippetRequest) ![]u8 {
        const status = try self.db.getProjectStatus(request.project);
        defer self.db.freeProjectStatus(status);
        if (status.status == .not_found) return error.UnknownProject;

        if (try self.db.findNodeByQualifiedName(request.project, request.qualified_name)) |node| {
            defer self.db.freeNode(node);
            return self.buildSnippetPayloadFromNode(request.project, status.root_path, node, request.include_neighbors, null);
        }

        const suffix_matches = try self.db.findNodesByQualifiedNameSuffix(request.project, request.qualified_name, 10);
        defer self.db.freeNodes(suffix_matches);
        if (suffix_matches.len == 1) {
            return self.buildSnippetPayloadFromNode(
                request.project,
                status.root_path,
                suffix_matches[0],
                request.include_neighbors,
                "suffix",
            );
        }
        if (suffix_matches.len > 1) {
            return buildNodeSuggestionsPayload(self.allocator, request.qualified_name, suffix_matches);
        }

        if (try self.db.findScipSymbolByQualifiedName(request.project, request.qualified_name)) |symbol| {
            defer self.db.freeScipSymbol(symbol);
            return self.buildSnippetPayloadFromScipSymbol(status.root_path, symbol, "scip");
        }

        const scip_suffix_matches = try self.db.findScipSymbolsByQualifiedNameSuffix(request.project, request.qualified_name, 10);
        defer self.db.freeScipSymbols(scip_suffix_matches);
        if (scip_suffix_matches.len == 1) {
            return self.buildSnippetPayloadFromScipSymbol(status.root_path, scip_suffix_matches[0], "scip_suffix");
        }
        if (scip_suffix_matches.len > 1) {
            return buildScipSuggestionsPayload(self.allocator, request.qualified_name, scip_suffix_matches);
        }

        return error.SymbolNotFound;
    }

    pub fn getArchitecturePayload(self: *QueryRouter, request: ArchitectureRequest) ![]u8 {
        const status = try self.db.getProjectStatus(request.project);
        defer self.db.freeProjectStatus(status);
        if (status.status == .not_found) return error.UnknownProject;

        const schema = try self.db.getSchema(request.project);
        defer self.db.freeSchema(schema);
        const files = try self.db.listProjectFiles(request.project);
        defer self.db.freePaths(files);

        var payload = std.ArrayList(u8).empty;
        try payload.appendSlice(self.allocator, "{");
        try appendJsonStringField(&payload, self.allocator, "project", request.project, true);
        try appendJsonIntField(&payload, self.allocator, "total_nodes", status.nodes, false);
        try appendJsonIntField(&payload, self.allocator, "total_edges", status.edges, false);

        if (request.include_structure) {
            try appendSchemaCountsField(&payload, self.allocator, "node_labels", schema.labels);
        }
        if (request.include_dependencies) {
            try appendEdgeTypeCountsField(&payload, self.allocator, "edge_types", schema.edge_types);
        }
        if (request.include_languages) {
            try appendLanguageSummaryField(&payload, self.allocator, files);
        }
        if (request.include_packages) {
            try appendDirectorySummaryField(&payload, self.allocator, files);
        }
        if (request.include_hotspots) {
            try appendHotspotsField(&payload, self, request.project, 10);
        }
        if (request.include_entry_points) {
            try appendEntryPointsField(&payload, self, request.project, 15);
        }
        if (request.include_routes) {
            try appendRoutesField(&payload, self, request.project);
        }

        try payload.appendSlice(self.allocator, "}");
        return try payload.toOwnedSlice(self.allocator);
    }

    pub fn detectChangesPayload(self: *QueryRouter, request: DetectChangesRequest) ![]u8 {
        const status = try self.db.getProjectStatus(request.project);
        defer self.db.freeProjectStatus(status);
        if (status.status == .not_found) return error.UnknownProject;

        const want_symbols = request.scope == null or
            std.mem.eql(u8, request.scope.?, "symbols") or
            std.mem.eql(u8, request.scope.?, "impact") or
            std.mem.eql(u8, request.scope.?, "full");
        const include_blast_radius = request.scope != null and std.mem.eql(u8, request.scope.?, "full");

        const changed_files = try collectChangedFiles(self.allocator, status.root_path, request.base_branch);
        defer freeOwnedStrings(self.allocator, changed_files);
        const impacted = if (want_symbols)
            try collectImpactedSymbols(self.allocator, self.db, request.project, changed_files)
        else
            &[_]ChangeSymbol{};
        defer if (want_symbols) freeChangeSymbols(self.allocator, impacted);
        const blast_radius = if (include_blast_radius)
            try collectBlastRadius(self.allocator, self.db, request.project, impacted, request.depth)
        else
            &[_]BlastItem{};
        defer if (include_blast_radius) freeBlastItems(self.allocator, blast_radius);

        var payload = std.ArrayList(u8).empty;
        try payload.appendSlice(self.allocator, "{");
        try appendJsonStringField(&payload, self.allocator, "project", request.project, true);
        try appendJsonStringField(&payload, self.allocator, "base_branch", request.base_branch, false);
        if (request.scope) |scope_value| try appendJsonStringField(&payload, self.allocator, "scope", scope_value, false);
        try appendJsonIntField(&payload, self.allocator, "depth", @as(i64, @intCast(request.depth)), false);
        try appendJsonStringArrayField(&payload, self.allocator, "changed_files", changed_files, false);
        try appendJsonIntField(&payload, self.allocator, "changed_count", @as(i64, @intCast(changed_files.len)), false);
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
                try appendJsonIntField(&payload, self.allocator, "hop", @as(i64, @intCast(item.hop)), false);
                try appendJsonStringField(&payload, self.allocator, "risk", riskLabel(item.hop), false);
                try payload.appendSlice(self.allocator, "}");
            }
        }
        try payload.appendSlice(self.allocator, "]}");
        return try payload.toOwnedSlice(self.allocator);
    }

    fn buildSnippetPayloadFromNode(
        self: *QueryRouter,
        project: []const u8,
        root_path: []const u8,
        node: store.Node,
        include_neighbors: bool,
        match_method: ?[]const u8,
    ) ![]u8 {
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
        if (match_method) |method| try appendJsonStringField(&payload, self.allocator, "match_method", method, false);
        try appendPropertyFields(&payload, self.allocator, node.properties_json);
        try appendJsonIntField(&payload, self.allocator, "callers", degree.callers, false);
        try appendJsonIntField(&payload, self.allocator, "callees", degree.callees, false);
        if (caller_names) |names| try appendJsonStringArrayField(&payload, self.allocator, "caller_names", names, false);
        if (callee_names) |names| try appendJsonStringArrayField(&payload, self.allocator, "callee_names", names, false);
        try payload.appendSlice(self.allocator, "}");
        return try payload.toOwnedSlice(self.allocator);
    }

    fn buildSnippetPayloadFromScipSymbol(
        self: *QueryRouter,
        root_path: []const u8,
        symbol: store.ScipSymbol,
        match_method: []const u8,
    ) ![]u8 {
        const line_range = snippetLineRange(symbol.start_line, symbol.end_line);
        const source_path = try resolveSnippetPath(self.allocator, root_path, symbol.file_path);
        defer if (source_path) |path| self.allocator.free(path);

        const source = if (source_path) |path|
            readFileLines(self.allocator, path, line_range.start_line, line_range.end_line) catch null
        else
            null;
        defer if (source) |snippet| self.allocator.free(snippet);

        var payload = std.ArrayList(u8).empty;
        try payload.appendSlice(self.allocator, "{");
        try appendJsonStringField(&payload, self.allocator, "name", symbol.display_name, true);
        try appendJsonStringField(&payload, self.allocator, "qualified_name", symbol.qualified_name, false);
        try appendJsonStringField(&payload, self.allocator, "label", scip.labelForKind(symbol.kind), false);
        try appendJsonStringField(
            &payload,
            self.allocator,
            "file_path",
            if (source_path) |path| path else symbol.file_path,
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
        try appendJsonStringField(&payload, self.allocator, "match_method", match_method, false);
        try appendPropertyFields(&payload, self.allocator, symbol.properties_json);
        try appendJsonIntField(&payload, self.allocator, "callers", 0, false);
        try appendJsonIntField(&payload, self.allocator, "callees", 0, false);
        try payload.appendSlice(self.allocator, "}");
        return try payload.toOwnedSlice(self.allocator);
    }

    fn collectNeighborNames(
        self: *QueryRouter,
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
            for (names.items) |name| self.allocator.free(name);
            names.deinit(self.allocator);
        }
        var seen = std.StringHashMap(void).init(self.allocator);
        defer {
            var it = seen.iterator();
            while (it.next()) |entry| self.allocator.free(entry.key_ptr.*);
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
};

fn buildNodeSuggestionsPayload(allocator: std.mem.Allocator, input: []const u8, suggestions: []const store.Node) ![]u8 {
    var payload = std.ArrayList(u8).empty;
    try payload.appendSlice(allocator, "{");
    try appendJsonStringField(&payload, allocator, "status", "ambiguous", true);
    const message = try std.fmt.allocPrint(
        allocator,
        "{d} matches for \"{s}\". Pick a qualified_name from suggestions below, or use search_graph(name_pattern=\"...\") to narrow results.",
        .{ suggestions.len, input },
    );
    defer allocator.free(message);
    try appendJsonStringField(&payload, allocator, "message", message, false);
    try payload.appendSlice(allocator, ",\"suggestions\":[");
    for (suggestions, 0..) |node, idx| {
        if (idx > 0) try payload.append(allocator, ',');
        try payload.appendSlice(allocator, "{");
        try appendJsonStringField(&payload, allocator, "qualified_name", node.qualified_name, true);
        try appendJsonStringField(&payload, allocator, "name", node.name, false);
        try appendJsonStringField(&payload, allocator, "label", node.label, false);
        try appendJsonStringField(&payload, allocator, "file_path", node.file_path, false);
        try payload.appendSlice(allocator, "}");
    }
    try payload.appendSlice(allocator, "]}");
    return try payload.toOwnedSlice(allocator);
}

fn buildScipSuggestionsPayload(allocator: std.mem.Allocator, input: []const u8, suggestions: []const store.ScipSymbol) ![]u8 {
    var payload = std.ArrayList(u8).empty;
    try payload.appendSlice(allocator, "{");
    try appendJsonStringField(&payload, allocator, "status", "ambiguous", true);
    const message = try std.fmt.allocPrint(
        allocator,
        "{d} matches for \"{s}\". Pick a qualified_name from suggestions below, or use search_graph(name_pattern=\"...\") to narrow results.",
        .{ suggestions.len, input },
    );
    defer allocator.free(message);
    try appendJsonStringField(&payload, allocator, "message", message, false);
    try payload.appendSlice(allocator, ",\"suggestions\":[");
    for (suggestions, 0..) |symbol, idx| {
        if (idx > 0) try payload.append(allocator, ',');
        try payload.appendSlice(allocator, "{");
        try appendJsonStringField(&payload, allocator, "qualified_name", symbol.qualified_name, true);
        try appendJsonStringField(&payload, allocator, "name", symbol.display_name, false);
        try appendJsonStringField(&payload, allocator, "label", scip.labelForKind(symbol.kind), false);
        try appendJsonStringField(&payload, allocator, "file_path", symbol.file_path, false);
        try payload.appendSlice(allocator, "}");
    }
    try payload.appendSlice(allocator, "]}");
    return try payload.toOwnedSlice(allocator);
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
        if (entry.found_existing) allocator.free(key);
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
        if (entry.found_existing) allocator.free(key);
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
    router: *QueryRouter,
    project: []const u8,
    limit: usize,
) !void {
    const page = try router.db.searchGraph(.{
        .project = project,
        .sort_field = .total_degree,
        .descending = true,
        .limit = limit,
    });
    defer router.db.freeGraphSearchPage(page);

    try payload.appendSlice(router.allocator, ",\"hotspots\":[");
    for (page.hits, 0..) |hit, idx| {
        if (idx > 0) try payload.append(router.allocator, ',');
        try payload.appendSlice(router.allocator, "{");
        try appendJsonStringField(payload, router.allocator, "name", hit.node.name, true);
        try appendJsonStringField(payload, router.allocator, "label", hit.node.label, false);
        try appendJsonStringField(payload, router.allocator, "file_path", hit.node.file_path, false);
        try appendJsonIntField(payload, router.allocator, "in_degree", hit.in_degree, false);
        try appendJsonIntField(payload, router.allocator, "out_degree", hit.out_degree, false);
        try payload.appendSlice(router.allocator, "}");
    }
    try payload.append(router.allocator, ']');
}

fn appendEntryPointsField(
    payload: *std.ArrayList(u8),
    router: *QueryRouter,
    project: []const u8,
    limit: usize,
) !void {
    const page = try router.db.searchGraph(.{
        .project = project,
        .label_pattern = "Function",
        .sort_field = .out_degree,
        .descending = true,
        .limit = 100,
    });
    defer router.db.freeGraphSearchPage(page);

    try payload.appendSlice(router.allocator, ",\"entry_points\":[");
    var written: usize = 0;
    for (page.hits) |hit| {
        if (hit.in_degree != 0 or hit.out_degree == 0) continue;
        if (written >= limit) break;
        if (written > 0) try payload.append(router.allocator, ',');
        try payload.appendSlice(router.allocator, "{");
        try appendJsonStringField(payload, router.allocator, "name", hit.node.name, true);
        try appendJsonStringField(payload, router.allocator, "qualified_name", hit.node.qualified_name, false);
        try appendJsonStringField(payload, router.allocator, "file_path", hit.node.file_path, false);
        try appendJsonIntField(payload, router.allocator, "out_degree", hit.out_degree, false);
        try payload.appendSlice(router.allocator, "}");
        written += 1;
    }
    try payload.append(router.allocator, ']');
}

fn appendRoutesField(payload: *std.ArrayList(u8), router: *QueryRouter, project: []const u8) !void {
    const nodes = try router.db.searchNodes(.{
        .project = project,
        .label_pattern = "Route",
        .limit = 500,
    });
    defer router.db.freeNodes(nodes);

    const edges = try router.db.listEdges(project, null);
    defer router.db.freeEdges(edges);

    try payload.appendSlice(router.allocator, ",\"routes\":[");
    var wrote: usize = 0;
    for (nodes) |node| {
        if (wrote > 0) try payload.append(router.allocator, ',');
        try payload.appendSlice(router.allocator, "{");
        try appendJsonStringField(payload, router.allocator, "name", node.name, true);
        try appendJsonStringField(payload, router.allocator, "file_path", node.file_path, false);
        try payload.appendSlice(router.allocator, "}");
        wrote += 1;
    }
    for (edges) |edge| {
        if (!std.mem.containsAtLeast(u8, edge.edge_type, 1, "HTTP") and !std.mem.containsAtLeast(u8, edge.edge_type, 1, "ROUTE")) continue;
        const source = (try router.db.findNodeById(project, edge.source_id)) orelse continue;
        defer router.db.freeNode(source);
        const target = (try router.db.findNodeById(project, edge.target_id)) orelse continue;
        defer router.db.freeNode(target);
        if (wrote > 0) try payload.append(router.allocator, ',');
        try payload.appendSlice(router.allocator, "{");
        try appendJsonStringField(payload, router.allocator, "name", source.name, true);
        try appendJsonStringField(payload, router.allocator, "target", target.name, false);
        try appendJsonStringField(payload, router.allocator, "type", edge.edge_type, false);
        try payload.appendSlice(router.allocator, "}");
        wrote += 1;
    }
    try payload.append(router.allocator, ']');
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
    if (try search_index.findCandidatePaths(allocator, db, project, pattern, regex, limit)) |candidate_paths| {
        defer db.freePaths(candidate_paths);
        const indexed_hits = try collectSearchCodeHitsFromPaths(
            allocator,
            db,
            project,
            root_path,
            pattern,
            mode,
            file_pattern,
            path_filter,
            regex,
            limit,
            context,
            candidate_paths,
        );
        if (indexed_hits.len > 0) return indexed_hits;
        allocator.free(indexed_hits);
    }

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
        if (try appendSearchCodeHitsForPath(
            allocator,
            db,
            project,
            file.path,
            file.rel_path,
            pattern,
            mode,
            file_pattern,
            path_filter,
            regex,
            limit,
            context,
            &out,
            &seen,
        )) break :file_loop;
    }

    if (mode != .files and out.items.len > 1) {
        try foldContainedSearchHits(allocator, &out);
        std.sort.pdq(CodeSearchHit, out.items, {}, searchCodeLessThan);
    }

    return out.toOwnedSlice(allocator);
}

fn collectSearchCodeHitsFromPaths(
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
    rel_paths: [][]u8,
) ![]CodeSearchHit {
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

    path_loop: for (rel_paths) |rel_path| {
        const abs_path = std.fs.path.join(allocator, &.{ root_path, rel_path }) catch continue;
        defer allocator.free(abs_path);

        if (try appendSearchCodeHitsForPath(
            allocator,
            db,
            project,
            abs_path,
            rel_path,
            pattern,
            mode,
            file_pattern,
            path_filter,
            regex,
            limit,
            context,
            &out,
            &seen,
        )) break :path_loop;
    }

    if (mode != .files and out.items.len > 1) {
        try foldContainedSearchHits(allocator, &out);
        std.sort.pdq(CodeSearchHit, out.items, {}, searchCodeLessThan);
    }

    return out.toOwnedSlice(allocator);
}

fn appendSearchCodeHitsForPath(
    allocator: std.mem.Allocator,
    db: *Store,
    project: []const u8,
    abs_path: []const u8,
    rel_path: []const u8,
    pattern: []const u8,
    mode: SearchCodeMode,
    file_pattern: ?[]const u8,
    path_filter: ?[]const u8,
    regex: bool,
    limit: usize,
    context: usize,
    out: *std.ArrayList(CodeSearchHit),
    seen: *std.StringHashMap(usize),
) !bool {
    if (path_filter) |filter| {
        if (std.mem.indexOf(u8, rel_path, filter) == null) return false;
    }
    if (file_pattern) |pattern_filter| {
        if (!text_match.globMatch(rel_path, pattern_filter)) return false;
    }

    const bytes = std.fs.cwd().readFileAlloc(allocator, abs_path, 8 * 1024 * 1024) catch return false;
    defer allocator.free(bytes);
    const file_nodes = try db.findNodesByFile(project, rel_path);
    defer db.freeNodes(file_nodes);

    var line_iter = std.mem.splitAny(u8, bytes, "\n");
    var line_no: u32 = 1;
    while (line_iter.next()) |line| : (line_no += 1) {
        if (!searchPatternMatches(allocator, line, pattern, regex)) continue;

        if (mode == .files) {
            const key = try allocator.dupe(u8, rel_path);
            if (seen.contains(key)) {
                allocator.free(key);
                break;
            }
            try seen.put(key, out.items.len);
            try out.append(allocator, .{
                .file_path = try allocator.dupe(u8, rel_path),
                .snippet = try allocator.dupe(u8, ""),
                .match_lines = try allocator.dupe(u32, &[_]u32{}),
            });
            return out.items.len >= limit;
        }

        const snippet = try buildSearchSnippet(allocator, bytes, line_no, if (mode == .full) context else 0);
        const symbol = bestSearchCodeNode(file_nodes, line_no);
        const dedupe_key = if (mode == .compact and symbol != null)
            try allocator.dupe(u8, symbol.?.qualified_name)
        else
            try std.fmt.allocPrint(allocator, "{s}:{d}", .{ rel_path, line_no });
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
            .file_path = try allocator.dupe(u8, rel_path),
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
        if (out.items.len >= limit) return true;
    }

    return false;
}

fn collectChangedFiles(
    allocator: std.mem.Allocator,
    root_path: []const u8,
    base_branch: []const u8,
) ![][]u8 {
    const branch_spec = try std.fmt.allocPrint(allocator, "{s}...HEAD", .{base_branch});
    defer allocator.free(branch_spec);
    const diff_base = runCommandCapture(
        allocator,
        &.{ "git", "-C", root_path, "diff", "--name-only", branch_spec },
    ) catch |err| switch (err) {
        error.CommandFailed => return try allocator.alloc([]u8, 0),
        else => return err,
    };
    defer freeCommandResult(allocator, diff_base);
    const diff_worktree = runCommandCapture(
        allocator,
        &.{ "git", "-C", root_path, "diff", "--name-only" },
    ) catch |err| switch (err) {
        error.CommandFailed => return try allocator.alloc([]u8, 0),
        else => return err,
    };
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

        const scip_symbols = try db.findScipSymbolsByFile(project, file_path);
        defer db.freeScipSymbols(scip_symbols);
        for (scip_symbols) |symbol| {
            const key = try allocator.dupe(u8, symbol.qualified_name);
            if (seen.contains(key)) {
                allocator.free(key);
                continue;
            }
            try seen.put(key, {});
            try out.append(allocator, .{
                .id = 0,
                .name = try allocator.dupe(u8, symbol.display_name),
                .label = try allocator.dupe(u8, scip.labelForKind(symbol.kind)),
                .file_path = try allocator.dupe(u8, symbol.file_path),
                .qualified_name = try allocator.dupe(u8, symbol.qualified_name),
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
        if (symbol.id == 0) continue;
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
    const ok = switch (result.term) {
        .Exited => |code| code == 0,
        else => false,
    };
    if (!ok) {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
        return error.CommandFailed;
    }
    return .{
        .stdout = result.stdout,
        .stderr = result.stderr,
    };
}

fn freeCommandResult(allocator: std.mem.Allocator, result: CommandResult) void {
    allocator.free(result.stdout);
    allocator.free(result.stderr);
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
    if (std.mem.indexOfScalar(u8, path, '/')) |slash| return path[0..slash];
    return ".";
}

fn totalSearchMatchLines(hits: []const CodeSearchHit) usize {
    var total: usize = 0;
    for (hits) |hit| total += @max(@as(usize, 1), hit.match_lines.len);
    return total;
}

fn dedupRatioText(allocator: std.mem.Allocator, hits: []const CodeSearchHit) ![]u8 {
    const raw = totalSearchMatchLines(hits);
    if (raw == 0) return allocator.dupe(u8, "1.0x");
    const scaled = @as(u32, @intFromFloat(@round((@as(f64, @floatFromInt(raw)) / @as(f64, @floatFromInt(hits.len))) * 10.0)));
    return std.fmt.allocPrint(allocator, "{d}.{d}x", .{ scaled / 10, scaled % 10 });
}

fn compatibleNodeDisplayName(node: store.Node) []const u8 {
    if (std.mem.eql(u8, node.label, "Module")) return std.fs.path.basename(node.file_path);
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

fn freeCodeSearchHits(allocator: std.mem.Allocator, hits: []const CodeSearchHit) void {
    for (hits) |hit| freeCodeSearchHit(allocator, hit);
    allocator.free(hits);
}

fn searchCodeCanContain(candidate: CodeSearchHit, nested: CodeSearchHit) bool {
    const candidate_rank = searchCodeLabelRank(candidate.label);
    const nested_rank = searchCodeLabelRank(nested.label);
    if (candidate_rank >= nested_rank) return false;
    if (!std.mem.eql(u8, candidate.file_path, nested.file_path)) return false;
    if (candidate.start_line <= 0 or candidate.end_line < candidate.start_line) return false;
    for (nested.match_lines) |line_no| {
        if (line_no < @as(u32, @intCast(candidate.start_line)) or line_no > @as(u32, @intCast(candidate.end_line))) return false;
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
            for (current.match_lines) |line_no| try appendUniqueMatchLine(allocator, &hits.items[candidate_idx], line_no);
            freeCodeSearchHit(allocator, hits.orderedRemove(idx));
            continue;
        }

        idx += 1;
    }
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

fn searchPatternMatches(allocator: std.mem.Allocator, line: []const u8, pattern: []const u8, regex: bool) bool {
    if (!regex) return std.mem.indexOf(u8, line, pattern) != null;
    var iter = std.mem.splitSequence(u8, pattern, "|");
    while (iter.next()) |branch| {
        const trimmed = std.mem.trim(u8, branch, " \t");
        if (trimmed.len == 0) continue;
        if (text_match.matchRegexish(allocator, line, trimmed)) return true;
    }
    return false;
}

fn searchCodeModeText(mode: SearchCodeMode) []const u8 {
    return switch (mode) {
        .compact => "compact",
        .full => "full",
        .files => "files",
    };
}

fn snippetLineRange(start_line: i32, end_line: i32) SnippetLineRange {
    const start = if (start_line > 0) start_line else 1;
    const end = if (end_line >= start) end_line else start;
    return .{ .start_line = start, .end_line = end };
}

fn resolveSnippetPath(allocator: std.mem.Allocator, root_path: []const u8, file_path: []const u8) !?[]u8 {
    if (file_path.len == 0) return null;
    if (std.fs.path.isAbsolute(file_path)) return try allocator.dupe(u8, file_path);
    return std.fs.path.join(allocator, &.{ root_path, file_path }) catch null;
}

fn readFileLines(
    allocator: std.mem.Allocator,
    path: []const u8,
    start_line: i32,
    end_line: i32,
) ![]u8 {
    const bytes = try std.fs.cwd().readFileAlloc(allocator, path, 8 * 1024 * 1024);
    defer allocator.free(bytes);
    return readInlineLines(allocator, bytes, start_line, end_line);
}

fn appendJsonStringField(
    payload: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    key: []const u8,
    value: []const u8,
    first: bool,
) !void {
    if (!first) try payload.append(allocator, ',');
    try appendJsonString(payload, allocator, key);
    try payload.append(allocator, ':');
    try appendJsonString(payload, allocator, value);
}

fn appendJsonIntField(
    payload: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    key: []const u8,
    value: anytype,
    first: bool,
) !void {
    if (!first) try payload.append(allocator, ',');
    try appendJsonString(payload, allocator, key);
    try payload.append(allocator, ':');
    try payload.writer(allocator).print("{d}", .{value});
}

fn appendJsonStringArrayField(
    payload: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    key: []const u8,
    values: [][]u8,
    first: bool,
) !void {
    if (!first) try payload.append(allocator, ',');
    try appendJsonString(payload, allocator, key);
    try payload.appendSlice(allocator, ":[");
    for (values, 0..) |value, idx| {
        if (idx > 0) try payload.append(allocator, ',');
        try appendJsonString(payload, allocator, value);
    }
    try payload.append(allocator, ']');
}

fn appendPropertyFields(payload: *std.ArrayList(u8), allocator: std.mem.Allocator, properties_json: []const u8) !void {
    const trimmed = std.mem.trim(u8, properties_json, " \t\r\n");
    if (trimmed.len == 0) return;

    const parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        trimmed,
        .{},
    ) catch return; // malformed JSON: skip silently
    defer parsed.deinit();

    const obj = switch (parsed.value) {
        .object => |o| o,
        else => return, // not an object: skip
    };

    var it = obj.iterator();
    const writer = payload.writer(allocator);
    while (it.next()) |entry| {
        try writer.writeByte(',');
        try writer.print("{f}:", .{std.json.fmt(entry.key_ptr.*, .{})});
        try writer.print("{f}", .{std.json.fmt(entry.value_ptr.*, .{})});
    }
}

fn appendJsonString(payload: *std.ArrayList(u8), allocator: std.mem.Allocator, value: []const u8) !void {
    try payload.writer(allocator).print("{f}", .{std.json.fmt(value, .{})});
}

fn freeOwnedStrings(allocator: std.mem.Allocator, values: [][]u8) void {
    for (values) |value| allocator.free(value);
    allocator.free(values);
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

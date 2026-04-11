// cypher.zig — Read-only Cypher-like query bridge for Phase 5 workflows.
//
// Supported query shapes:
//   * MATCH (n[:Label]) [WHERE ...] RETURN ...
//   * MATCH (a)-[r:TYPE]->(b) [WHERE ...] RETURN ...
//   * COUNT(), ORDER BY, LIMIT, DISTINCT
//   * Property access for node/edge properties JSON via n.foo / r.bar

const std = @import("std");
const store = @import("store.zig");

const Store = store.Store;

pub const CypherResult = struct {
    columns: [][]const u8,
    rows: [][][]const u8,
    err: ?[]const u8 = null,
};

const QueryKind = enum { node, edge };
const ValueSubject = enum { node, source, target, edge };
const Operator = enum { eq, neq, contains, like, regex, gt, gte, lt, lte };

const NodePattern = struct {
    var_name: []const u8,
    label: ?[]const u8 = null,
};

const EdgePattern = struct {
    source: NodePattern,
    edge_var: []const u8 = "r",
    edge_type: ?[]const u8 = null,
    target: NodePattern,
};

const Condition = struct {
    subject: ValueSubject,
    field: []const u8,
    op: Operator,
    value: []const u8,
    join_with_or: bool = false,
};

const ReturnExpr = struct {
    subject: ValueSubject,
    field: []const u8,
    alias: ?[]const u8 = null,
    display_name: []const u8 = "",
    kind: Kind = .field,

    const Kind = enum {
        field,
        count,
        distinct_field,
        node_default,
    };
};

const OrderBy = struct {
    subject: ValueSubject,
    field: []const u8,
    descending: bool = false,
};

const ParsedQuery = struct {
    kind: QueryKind,
    node_pattern: ?NodePattern = null,
    edge_pattern: ?EdgePattern = null,
    conditions: []Condition,
    returns: []ReturnExpr,
    order_by: []OrderBy,
    limit: ?usize = null,
};

const QueryRow = struct {
    values: [][]const u8,
    sort_values: [][]const u8,
};

const EdgeContext = struct {
    edge: store.Edge,
    source: store.Node,
    target: store.Node,
};

pub fn freeResult(allocator: std.mem.Allocator, result: CypherResult) void {
    for (result.columns) |column| allocator.free(column);
    allocator.free(result.columns);
    for (result.rows) |row| {
        for (row) |cell| allocator.free(cell);
        allocator.free(row);
    }
    allocator.free(result.rows);
    if (result.err) |err_text| allocator.free(err_text);
}

pub fn execute(
    allocator: std.mem.Allocator,
    db: *Store,
    query: []const u8,
    project: ?[]const u8,
    max_rows: u32,
) !CypherResult {
    const trimmed = std.mem.trim(u8, query, " \t\r\n;");
    const parsed = parseQuery(allocator, trimmed) catch |err| {
        return .{
            .columns = try allocator.alloc([]const u8, 0),
            .rows = try allocator.alloc([][]const u8, 0),
            .err = try allocator.dupe(u8, switch (err) {
                error.UnsupportedQuery => "unsupported query",
                error.InvalidQuery => "invalid query",
                else => "query execution failed",
            }),
        };
    };
    defer freeParsedQuery(allocator, parsed);

    const effective_limit: usize = if (parsed.limit) |limit|
        limit
    else if (max_rows > 0)
        max_rows
    else
        200;

    return switch (parsed.kind) {
        .node => try executeNodeQuery(allocator, db, project orelse "", parsed, effective_limit),
        .edge => try executeEdgeQuery(allocator, db, project orelse "", parsed, effective_limit),
    };
}

fn executeNodeQuery(
    allocator: std.mem.Allocator,
    db: *Store,
    project: []const u8,
    parsed: ParsedQuery,
    effective_limit: usize,
) !CypherResult {
    const pattern = parsed.node_pattern orelse return error.InvalidQuery;
    const nodes = try db.searchNodes(.{
        .project = project,
        .label_pattern = pattern.label,
        .limit = 100_000,
    });
    defer db.freeNodes(nodes);

    var rows = std.ArrayList(QueryRow).empty;
    defer rows.deinit(allocator);
    defer freeQueryRows(allocator, rows.items);

    for (nodes) |node| {
        if (!evaluateNodeConditions(allocator, node, parsed.conditions, pattern.var_name)) continue;
        const built = try buildNodeReturnRow(allocator, node, parsed.returns, parsed.order_by, pattern.var_name);
        try rows.append(allocator, built);
    }

    if (parsed.returns.len == 1 and parsed.returns[0].kind == .count) {
        return buildCountResult(allocator, parsed.returns[0], rows.items.len);
    }

    if (parsed.order_by.len == 0 and rows.items.len > 1) {
        std.sort.pdq(QueryRow, rows.items, parsed.order_by, queryRowLessThan);
    }
    try finalizeRows(allocator, &rows, parsed.returns, parsed.order_by, effective_limit);
    return buildTabularResult(allocator, parsed.returns, rows.items);
}

fn executeEdgeQuery(
    allocator: std.mem.Allocator,
    db: *Store,
    project: []const u8,
    parsed: ParsedQuery,
    effective_limit: usize,
) !CypherResult {
    const pattern = parsed.edge_pattern orelse return error.InvalidQuery;
    const sources = try db.searchNodes(.{
        .project = project,
        .label_pattern = pattern.source.label,
        .limit = 100_000,
    });
    defer db.freeNodes(sources);

    var rows = std.ArrayList(QueryRow).empty;
    defer rows.deinit(allocator);
    defer freeQueryRows(allocator, rows.items);

    for (sources) |source| {
        const edges = try db.findEdgesBySource(project, source.id, canonicalEdgeType(pattern.edge_type));
        defer db.freeEdges(edges);

        for (edges) |edge| {
            const target = (try db.findNodeById(project, edge.target_id)) orelse continue;
            defer db.freeNode(target);

            if (pattern.target.label) |label| {
                if (!std.mem.eql(u8, target.label, label)) continue;
            }

            const ctx = EdgeContext{
                .edge = edge,
                .source = source,
                .target = target,
            };
            if (!evaluateEdgeConditions(allocator, ctx, parsed.conditions, pattern)) continue;
            const built = try buildEdgeReturnRow(allocator, ctx, parsed.returns, parsed.order_by);
            try rows.append(allocator, built);
        }
    }

    if (parsed.returns.len == 1 and parsed.returns[0].kind == .count) {
        return buildCountResult(allocator, parsed.returns[0], rows.items.len);
    }

    try finalizeRows(allocator, &rows, parsed.returns, parsed.order_by, effective_limit);
    return buildTabularResult(allocator, parsed.returns, rows.items);
}

fn finalizeRows(
    allocator: std.mem.Allocator,
    rows: *std.ArrayList(QueryRow),
    returns: []const ReturnExpr,
    order_by: []const OrderBy,
    effective_limit: usize,
) !void {
    if (rows.items.len == 0) return;

    const distinct = returns.len > 0 and returns[0].kind == .distinct_field;
    if (distinct) {
        try dedupeRows(allocator, rows);
    }
    if (order_by.len > 0) {
        std.sort.pdq(QueryRow, rows.items, order_by, queryRowLessThan);
    }
    if (rows.items.len > effective_limit) {
        var idx = effective_limit;
        while (idx < rows.items.len) : (idx += 1) {
            freeQueryRow(allocator, rows.items[idx]);
        }
        rows.shrinkRetainingCapacity(effective_limit);
    }
}

fn buildCountResult(allocator: std.mem.Allocator, expr: ReturnExpr, count: usize) !CypherResult {
    const alias = expr.alias orelse "count";
    const columns = try allocator.alloc([]const u8, 1);
    errdefer allocator.free(columns);
    columns[0] = try allocator.dupe(u8, alias);
    errdefer allocator.free(columns[0]);

    const rows = try allocator.alloc([][]const u8, 1);
    errdefer allocator.free(rows);
    rows[0] = try allocator.alloc([]const u8, 1);
    errdefer allocator.free(rows[0]);
    rows[0][0] = try std.fmt.allocPrint(allocator, "{d}", .{count});
    errdefer allocator.free(rows[0][0]);

    return .{ .columns = columns, .rows = rows };
}

fn buildTabularResult(
    allocator: std.mem.Allocator,
    returns: []const ReturnExpr,
    rows: []const QueryRow,
) !CypherResult {
    const columns = try allocator.alloc([]const u8, returns.len);
    var col_filled: usize = 0;
    errdefer {
        for (columns[0..col_filled]) |col| allocator.free(col);
        allocator.free(columns);
    }
    for (returns, 0..) |expr, idx| {
        columns[idx] = try allocator.dupe(u8, returnColumnName(expr));
        col_filled += 1;
    }

    const out_rows = try allocator.alloc([][]const u8, rows.len);
    var row_filled: usize = 0;
    errdefer {
        var i: usize = 0;
        while (i < row_filled) : (i += 1) {
            for (out_rows[i]) |cell| allocator.free(cell);
            allocator.free(out_rows[i]);
        }
        allocator.free(out_rows);
    }
    for (rows, 0..) |row, idx| {
        out_rows[idx] = try allocator.alloc([]const u8, row.values.len);
        row_filled += 1;
        for (row.values, 0..) |cell, cell_idx| {
            out_rows[idx][cell_idx] = try allocator.dupe(u8, cell);
        }
    }

    return .{
        .columns = columns,
        .rows = out_rows,
    };
}

fn evaluateNodeConditions(
    allocator: std.mem.Allocator,
    node: store.Node,
    conditions: []const Condition,
    node_var: []const u8,
) bool {
    if (conditions.len == 0) return true;
    var result = true;
    for (conditions, 0..) |cond, idx| {
        const current = switch (cond.subject) {
            .node => evaluateFieldCondition(
                allocator,
                readNodeField(allocator, node, cond.field) catch return false,
                cond.op,
                cond.value,
            ),
            else => false,
        };
        if (idx == 0) {
            result = current;
        } else if (cond.join_with_or) {
            result = result or current;
        } else {
            result = result and current;
        }
    }
    _ = node_var;
    return result;
}

fn evaluateEdgeConditions(
    allocator: std.mem.Allocator,
    ctx: EdgeContext,
    conditions: []const Condition,
    pattern: EdgePattern,
) bool {
    if (conditions.len == 0) return true;
    var result = true;
    for (conditions, 0..) |cond, idx| {
        const current = switch (cond.subject) {
            .source => evaluateFieldCondition(
                allocator,
                readNodeField(allocator, ctx.source, cond.field) catch return false,
                cond.op,
                cond.value,
            ),
            .target => evaluateFieldCondition(
                allocator,
                readNodeField(allocator, ctx.target, cond.field) catch return false,
                cond.op,
                cond.value,
            ),
            .edge => evaluateFieldCondition(
                allocator,
                readEdgeField(allocator, ctx.edge, cond.field) catch return false,
                cond.op,
                cond.value,
            ),
            .node => false,
        };
        if (idx == 0) {
            result = current;
        } else if (cond.join_with_or) {
            result = result or current;
        } else {
            result = result and current;
        }
    }
    _ = pattern;
    return result;
}

fn evaluateFieldCondition(
    allocator: std.mem.Allocator,
    field_value: OwnedField,
    op: Operator,
    expected: []const u8,
) bool {
    defer field_value.deinit(allocator);
    return switch (op) {
        .eq => std.mem.eql(u8, field_value.value, expected),
        .neq => !std.mem.eql(u8, field_value.value, expected),
        .contains => std.mem.indexOf(u8, field_value.value, expected) != null,
        .like => matchLike(field_value.value, expected),
        .regex => matchRegexish(field_value.value, expected),
        .gt => compareNumeric(field_value.value, expected, .gt),
        .gte => compareNumeric(field_value.value, expected, .gte),
        .lt => compareNumeric(field_value.value, expected, .lt),
        .lte => compareNumeric(field_value.value, expected, .lte),
    };
}

const NumericCmp = enum { gt, gte, lt, lte };

fn compareNumeric(actual_text: []const u8, expected_text: []const u8, cmp: NumericCmp) bool {
    const actual = std.fmt.parseInt(i64, actual_text, 10) catch return false;
    const expected = std.fmt.parseInt(i64, expected_text, 10) catch return false;
    return switch (cmp) {
        .gt => actual > expected,
        .gte => actual >= expected,
        .lt => actual < expected,
        .lte => actual <= expected,
    };
}

fn buildNodeReturnRow(
    allocator: std.mem.Allocator,
    node: store.Node,
    returns: []const ReturnExpr,
    order_by: []const OrderBy,
    node_var: []const u8,
) !QueryRow {
    var values = std.ArrayList([]const u8).empty;
    errdefer {
        for (values.items) |value| allocator.free(value);
        values.deinit(allocator);
    }

    if (returns.len == 1 and returns[0].kind == .node_default) {
        try values.append(allocator, try std.fmt.allocPrint(allocator, "{d}", .{node.id}));
        try values.append(allocator, try allocator.dupe(u8, node.label));
        try values.append(allocator, try allocator.dupe(u8, node.name));
        try values.append(allocator, try allocator.dupe(u8, node.qualified_name));
        try values.append(allocator, try allocator.dupe(u8, node.file_path));
    } else {
        for (returns) |expr| {
            const owned = try readNodeField(allocator, node, expr.field);
            try values.append(allocator, try allocator.dupe(u8, owned.value));
            owned.deinit(allocator);
        }
    }

    const sort_values = if (order_by.len > 0)
        try buildNodeSortValues(allocator, node, order_by)
    else
        try buildDefaultSortValues(allocator, if (returns.len > 0 and values.items.len > 0) values.items[0] else node_var);

    return .{
        .values = try values.toOwnedSlice(allocator),
        .sort_values = sort_values,
    };
}

fn buildEdgeReturnRow(
    allocator: std.mem.Allocator,
    ctx: EdgeContext,
    returns: []const ReturnExpr,
    order_by: []const OrderBy,
) !QueryRow {
    var values = std.ArrayList([]const u8).empty;
    errdefer {
        for (values.items) |value| allocator.free(value);
        values.deinit(allocator);
    }

    for (returns) |expr| {
        const owned = try readSubjectField(allocator, ctx, expr.subject, expr.field);
        defer owned.deinit(allocator);
        try values.append(allocator, try allocator.dupe(u8, owned.value));
    }

    const sort_values = if (order_by.len > 0)
        try buildEdgeSortValues(allocator, ctx, order_by)
    else
        try buildDefaultSortValues(allocator, if (values.items.len > 0) values.items[0] else "");

    return .{
        .values = try values.toOwnedSlice(allocator),
        .sort_values = sort_values,
    };
}

fn buildDefaultSortValues(allocator: std.mem.Allocator, value: []const u8) ![][]const u8 {
    const out = try allocator.alloc([]const u8, 1);
    errdefer allocator.free(out);
    out[0] = try allocator.dupe(u8, value);
    return out;
}

fn buildNodeSortValues(allocator: std.mem.Allocator, node: store.Node, order_by: []const OrderBy) ![][]const u8 {
    const out = try allocator.alloc([]const u8, order_by.len);
    var filled: usize = 0;
    errdefer {
        var idx: usize = 0;
        while (idx < filled) : (idx += 1) allocator.free(out[idx]);
        allocator.free(out);
    }

    for (order_by, 0..) |ord, idx| {
        if (ord.subject != .node) {
            out[idx] = try allocator.dupe(u8, "");
        } else {
            const owned = try readNodeField(allocator, node, ord.field);
            defer owned.deinit(allocator);
            out[idx] = try allocator.dupe(u8, owned.value);
        }
        filled += 1;
    }
    return out;
}

fn buildEdgeSortValues(allocator: std.mem.Allocator, ctx: EdgeContext, order_by: []const OrderBy) ![][]const u8 {
    const out = try allocator.alloc([]const u8, order_by.len);
    var filled: usize = 0;
    errdefer {
        var idx: usize = 0;
        while (idx < filled) : (idx += 1) allocator.free(out[idx]);
        allocator.free(out);
    }

    for (order_by, 0..) |ord, idx| {
        const owned = try readSubjectField(allocator, ctx, ord.subject, ord.field);
        defer owned.deinit(allocator);
        out[idx] = try allocator.dupe(u8, owned.value);
        filled += 1;
    }
    return out;
}

fn readSubjectField(
    allocator: std.mem.Allocator,
    ctx: EdgeContext,
    subject: ValueSubject,
    field: []const u8,
) !OwnedField {
    return switch (subject) {
        .source => try readNodeField(allocator, ctx.source, field),
        .target => try readNodeField(allocator, ctx.target, field),
        .edge => try readEdgeField(allocator, ctx.edge, field),
        .node => error.InvalidQuery,
    };
}

const OwnedField = struct {
    value: []const u8,
    owned: bool = false,

    fn deinit(self: OwnedField, allocator: std.mem.Allocator) void {
        if (self.owned) allocator.free(self.value);
    }
};

fn readNodeField(allocator: std.mem.Allocator, node: store.Node, field: []const u8) !OwnedField {
    if (std.mem.eql(u8, field, "id")) return .{ .value = try std.fmt.allocPrint(allocator, "{d}", .{node.id}), .owned = true };
    if (std.mem.eql(u8, field, "label")) return .{ .value = node.label };
    if (std.mem.eql(u8, field, "name")) return .{ .value = node.name };
    if (std.mem.eql(u8, field, "qualified_name")) return .{ .value = node.qualified_name };
    if (std.mem.eql(u8, field, "file_path")) return .{ .value = node.file_path };
    if (std.mem.eql(u8, field, "start_line")) return .{ .value = try std.fmt.allocPrint(allocator, "{d}", .{node.start_line}), .owned = true };
    if (std.mem.eql(u8, field, "end_line")) return .{ .value = try std.fmt.allocPrint(allocator, "{d}", .{node.end_line}), .owned = true };
    if (std.mem.eql(u8, field, "properties")) return .{ .value = node.properties_json };
    if (jsonProperty(allocator, node.properties_json, field)) |value| return .{ .value = value, .owned = true };
    return .{ .value = "" };
}

fn readEdgeField(allocator: std.mem.Allocator, edge: store.Edge, field: []const u8) !OwnedField {
    if (std.mem.eql(u8, field, "id")) return .{ .value = try std.fmt.allocPrint(allocator, "{d}", .{edge.id}), .owned = true };
    if (std.mem.eql(u8, field, "type")) return .{ .value = edge.edge_type };
    if (std.mem.eql(u8, field, "properties")) return .{ .value = edge.properties_json };
    if (jsonProperty(allocator, edge.properties_json, field)) |value| return .{ .value = value, .owned = true };
    return .{ .value = "" };
}

fn jsonProperty(allocator: std.mem.Allocator, json_text: []const u8, key: []const u8) ?[]u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();
    const parsed = std.json.parseFromSlice(std.json.Value, arena_allocator, json_text, .{}) catch return null;
    if (parsed.value != .object) return null;
    const entry = parsed.value.object.get(key) orelse return null;
    return switch (entry) {
        .string => allocator.dupe(u8, entry.string) catch null,
        .integer => std.fmt.allocPrint(allocator, "{d}", .{entry.integer}) catch null,
        .bool => allocator.dupe(u8, if (entry.bool) "true" else "false") catch null,
        else => null,
    };
}

fn freeQueryRows(allocator: std.mem.Allocator, rows: []const QueryRow) void {
    for (rows) |row| freeQueryRow(allocator, row);
}

fn freeQueryRow(allocator: std.mem.Allocator, row: QueryRow) void {
    for (row.values) |value| allocator.free(value);
    allocator.free(row.values);
    for (row.sort_values) |value| allocator.free(value);
    allocator.free(row.sort_values);
}

fn queryRowLessThan(order: []const OrderBy, lhs: QueryRow, rhs: QueryRow) bool {
    const key_count = @min(lhs.sort_values.len, rhs.sort_values.len);
    var idx: usize = 0;
    while (idx < key_count) : (idx += 1) {
        const cmp = std.mem.order(u8, lhs.sort_values[idx], rhs.sort_values[idx]);
        if (cmp == .eq) continue;
        const descending = if (idx < order.len) order[idx].descending else false;
        return if (descending) cmp == .gt else cmp == .lt;
    }
    return false;
}

fn dedupeRows(allocator: std.mem.Allocator, rows: *std.ArrayList(QueryRow)) !void {
    var seen = std.StringHashMap(void).init(allocator);
    defer {
        var it = seen.iterator();
        while (it.next()) |entry| allocator.free(entry.key_ptr.*);
        seen.deinit();
    }

    var idx: usize = 0;
    while (idx < rows.items.len) {
        const key = try joinRowValues(allocator, rows.items[idx].values);
        errdefer allocator.free(key);
        if (seen.contains(key)) {
            allocator.free(key);
            freeQueryRow(allocator, rows.swapRemove(idx));
            continue;
        }
        try seen.put(key, {});
        idx += 1;
    }
}

fn joinRowValues(allocator: std.mem.Allocator, values: [][]const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    for (values, 0..) |value, idx| {
        if (idx > 0) try out.append(allocator, 0x1f);
        try out.appendSlice(allocator, value);
    }
    return out.toOwnedSlice(allocator);
}

fn returnColumnName(expr: ReturnExpr) []const u8 {
    if (expr.kind == .node_default) return "node";
    if (expr.alias) |alias| return alias;
    if (expr.display_name.len > 0) return expr.display_name;
    if (expr.kind == .count) return "count";
    return expr.field;
}

fn canonicalEdgeType(edge_type: ?[]const u8) ?[]const u8 {
    return edge_type;
}

fn matchLike(actual: []const u8, pattern: []const u8) bool {
    if (std.mem.eql(u8, pattern, "%")) return true;
    const starts = std.mem.startsWith(u8, pattern, "%");
    const ends = std.mem.endsWith(u8, pattern, "%");
    const trimmed = std.mem.trim(u8, pattern, "%");
    if (starts and ends) return std.mem.indexOf(u8, actual, trimmed) != null;
    if (starts) return std.mem.endsWith(u8, actual, trimmed);
    if (ends) return std.mem.startsWith(u8, actual, trimmed);
    return std.mem.eql(u8, actual, trimmed);
}

fn matchRegexish(actual: []const u8, pattern: []const u8) bool {
    if (pattern.len >= 2 and pattern[0] == '^' and pattern[pattern.len - 1] == '$') {
        const inner = pattern[1 .. pattern.len - 1];
        if (std.mem.eql(u8, inner, ".*")) return true;
        if (std.mem.startsWith(u8, inner, ".*") and std.mem.endsWith(u8, inner, ".*") and inner.len >= 4) {
            return std.mem.indexOf(u8, actual, inner[2 .. inner.len - 2]) != null;
        }
        return std.mem.eql(u8, actual, inner);
    }
    const simplified = std.mem.replaceOwned(u8, std.heap.page_allocator, pattern, ".*", "") catch return false;
    defer std.heap.page_allocator.free(simplified);
    if (simplified.len == 0) return true;
    return std.mem.indexOf(u8, actual, simplified) != null;
}

fn parseQuery(allocator: std.mem.Allocator, query: []const u8) !ParsedQuery {
    if (!startsWithInsensitive(query, "MATCH ")) return error.UnsupportedQuery;

    const return_pos = indexOfInsensitive(query, " RETURN ") orelse return error.InvalidQuery;
    const match_and_where = std.mem.trim(u8, query["MATCH ".len..return_pos], " \t");
    const after_return = query[return_pos + " RETURN ".len ..];
    const order_pos = indexOfInsensitive(after_return, " ORDER BY ");
    const limit_pos = indexOfInsensitive(after_return, " LIMIT ");

    const return_end = if (order_pos) |pos|
        pos
    else if (limit_pos) |pos|
        pos
    else
        after_return.len;
    const return_section = std.mem.trim(u8, after_return[0..return_end], " \t");

    const where_pos = indexOfInsensitive(match_and_where, " WHERE ");
    const pattern_section = std.mem.trim(u8, if (where_pos) |pos| match_and_where[0..pos] else match_and_where, " \t");
    const where_section = if (where_pos) |pos|
        std.mem.trim(u8, match_and_where[pos + " WHERE ".len ..], " \t")
    else
        null;

    var parsed = ParsedQuery{
        .kind = if (std.mem.indexOf(u8, pattern_section, "->") != null) .edge else .node,
        .conditions = &.{},
        .returns = &.{},
        .order_by = &.{},
    };
    errdefer freeParsedQuery(allocator, parsed);

    switch (parsed.kind) {
        .node => parsed.node_pattern = try parseNodePattern(pattern_section),
        .edge => parsed.edge_pattern = try parseEdgePattern(pattern_section),
    }
    parsed.conditions = try parseConditions(allocator, where_section);
    parsed.returns = try parseReturns(allocator, return_section, parsed);

    if (order_pos) |pos| {
        const order_tail = after_return[pos + " ORDER BY ".len ..];
        const order_end = if (limit_pos) |limit_idx| limit_idx - (pos + " ORDER BY ".len) else order_tail.len;
        parsed.order_by = try parseOrderBy(allocator, std.mem.trim(u8, order_tail[0..order_end], " \t"), parsed);
    }
    if (limit_pos) |pos| {
        const limit_text = std.mem.trim(u8, after_return[pos + " LIMIT ".len ..], " \t");
        parsed.limit = try std.fmt.parseInt(usize, limitTextToken(limit_text), 10);
    }
    return parsed;
}

fn freeParsedQuery(allocator: std.mem.Allocator, parsed: ParsedQuery) void {
    allocator.free(parsed.conditions);
    allocator.free(parsed.returns);
    if (parsed.order_by.len > 0) allocator.free(parsed.order_by);
}

fn parseNodePattern(section: []const u8) !NodePattern {
    const open = std.mem.indexOfScalar(u8, section, '(') orelse return error.InvalidQuery;
    const close = std.mem.indexOfScalarPos(u8, section, open + 1, ')') orelse return error.InvalidQuery;
    const inner = std.mem.trim(u8, section[open + 1 .. close], " \t");
    return parseNodePatternInner(inner);
}

fn parseEdgePattern(section: []const u8) !EdgePattern {
    const left_open = std.mem.indexOfScalar(u8, section, '(') orelse return error.InvalidQuery;
    const left_close = std.mem.indexOfScalarPos(u8, section, left_open + 1, ')') orelse return error.InvalidQuery;
    const rel_open = std.mem.indexOfScalarPos(u8, section, left_close, '[') orelse return error.InvalidQuery;
    const rel_close = std.mem.indexOfScalarPos(u8, section, rel_open + 1, ']') orelse return error.InvalidQuery;
    const right_open = std.mem.indexOfScalarPos(u8, section, rel_close, '(') orelse return error.InvalidQuery;
    const right_close = std.mem.indexOfScalarPos(u8, section, right_open + 1, ')') orelse return error.InvalidQuery;

    const source = try parseNodePatternInner(std.mem.trim(u8, section[left_open + 1 .. left_close], " \t"));
    const target = try parseNodePatternInner(std.mem.trim(u8, section[right_open + 1 .. right_close], " \t"));
    const rel_inner = std.mem.trim(u8, section[rel_open + 1 .. rel_close], " \t");

    var edge_var: []const u8 = "r";
    var edge_type: ?[]const u8 = null;
    if (rel_inner.len > 0) {
        if (std.mem.indexOfScalar(u8, rel_inner, ':')) |colon| {
            const left = std.mem.trim(u8, rel_inner[0..colon], " \t");
            const right = std.mem.trim(u8, rel_inner[colon + 1 ..], " \t");
            if (left.len > 0) edge_var = left;
            if (right.len > 0) edge_type = right;
        } else {
            edge_var = rel_inner;
        }
    }

    return .{
        .source = source,
        .edge_var = edge_var,
        .edge_type = edge_type,
        .target = target,
    };
}

fn parseNodePatternInner(inner: []const u8) !NodePattern {
    if (std.mem.indexOfScalar(u8, inner, ':')) |colon| {
        return .{
            .var_name = std.mem.trim(u8, inner[0..colon], " \t"),
            .label = std.mem.trim(u8, inner[colon + 1 ..], " \t"),
        };
    }
    return .{ .var_name = inner };
}

fn parseConditions(allocator: std.mem.Allocator, where_section: ?[]const u8) ![]Condition {
    const section = where_section orelse return allocator.alloc(Condition, 0);
    var out = std.ArrayList(Condition).empty;
    errdefer out.deinit(allocator);

    var cursor: usize = 0;
    var join_with_or = false;
    while (cursor < section.len) {
        const next_and = indexOfKeyword(section, cursor, " AND ");
        const next_or = indexOfKeyword(section, cursor, " OR ");
        const next_pos = if (next_and == null) next_or else if (next_or == null) next_and else @min(next_and.?, next_or.?);
        const chunk_end = next_pos orelse section.len;
        const chunk = std.mem.trim(u8, section[cursor..chunk_end], " \t");
        if (chunk.len > 0) {
            var cond = try parseCondition(chunk);
            cond.join_with_or = join_with_or;
            try out.append(allocator, cond);
        }
        if (next_pos) |pos| {
            join_with_or = next_or != null and next_or.? == pos;
            cursor = pos + 5;
            if (join_with_or) cursor = pos + 4;
            continue;
        }
        break;
    }
    return out.toOwnedSlice(allocator);
}

fn parseCondition(chunk: []const u8) !Condition {
    const operators = [_]struct { text: []const u8, op: Operator }{
        .{ .text = " CONTAINS ", .op = .contains },
        .{ .text = " LIKE ", .op = .like },
        .{ .text = " =~ ", .op = .regex },
        .{ .text = " >= ", .op = .gte },
        .{ .text = " <= ", .op = .lte },
        .{ .text = " != ", .op = .neq },
        .{ .text = " = ", .op = .eq },
        .{ .text = " > ", .op = .gt },
        .{ .text = " < ", .op = .lt },
    };
    for (operators) |operator| {
        if (indexOfInsensitive(chunk, operator.text)) |pos| {
            const left = std.mem.trim(u8, chunk[0..pos], " \t");
            const right = std.mem.trim(u8, chunk[pos + operator.text.len ..], " \t");
            const ref = try parseReference(left);
            return .{
                .subject = ref.subject,
                .field = ref.field,
                .op = operator.op,
                .value = unquote(right),
            };
        }
    }
    return error.InvalidQuery;
}

fn parseReturns(allocator: std.mem.Allocator, section: []const u8, parsed: ParsedQuery) ![]ReturnExpr {
    var parts = splitTopLevelComma(allocator, section);
    defer parts.deinit(allocator);

    var out = std.ArrayList(ReturnExpr).empty;
    errdefer out.deinit(allocator);

    for (parts.items) |part| {
        const trimmed = std.mem.trim(u8, part, " \t");
        if (trimmed.len == 0) continue;
        try appendReturnExpr(allocator, &out, trimmed, parsed);
    }

    return out.toOwnedSlice(allocator);
}

fn appendReturnExpr(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(ReturnExpr),
    text: []const u8,
    parsed: ParsedQuery,
) !void {
    const alias_pos = indexOfInsensitive(text, " AS ");
    const expr_text = std.mem.trim(u8, if (alias_pos) |pos| text[0..pos] else text, " \t");
    const alias_text = if (alias_pos) |pos| std.mem.trim(u8, text[pos + " AS ".len ..], " \t") else null;

    if (startsWithInsensitive(expr_text, "COUNT(")) {
        try out.append(allocator, .{
            .subject = .node,
            .field = "count",
            .alias = alias_text,
            .display_name = expr_text,
            .kind = .count,
        });
        return;
    }

    if (startsWithInsensitive(expr_text, "DISTINCT ")) {
        const inner = std.mem.trim(u8, expr_text["DISTINCT ".len..], " \t");
        const ref = try parseReference(inner);
        try out.append(allocator, .{
            .subject = ref.subject,
            .field = ref.field,
            .alias = alias_text,
            .display_name = inner,
            .kind = .distinct_field,
        });
        return;
    }

    if (parsed.kind == .node and parsed.node_pattern != null and std.mem.eql(u8, expr_text, parsed.node_pattern.?.var_name)) {
        if (alias_text != null) return error.InvalidQuery;
        const default_fields = [_][]const u8{ "id", "label", "name", "qualified_name", "file_path" };
        for (default_fields) |field| {
            try out.append(allocator, .{
                .subject = .node,
                .field = field,
                .kind = .field,
            });
        }
        return;
    }

    const ref = try parseReference(expr_text);
    try out.append(allocator, .{
        .subject = ref.subject,
        .field = ref.field,
        .alias = alias_text,
        .display_name = expr_text,
        .kind = .field,
    });
}

fn parseOrderBy(allocator: std.mem.Allocator, text: []const u8, parsed: ParsedQuery) ![]OrderBy {
    var parts = splitTopLevelComma(allocator, text);
    defer parts.deinit(allocator);

    const part = if (parts.items.len > 0) parts.items[0] else text;
    var expr = std.mem.trim(u8, part, " \t");
    var descending = false;
    if (endsWithInsensitive(expr, " DESC")) {
        descending = true;
        expr = std.mem.trim(u8, expr[0 .. expr.len - " DESC".len], " \t");
    } else if (endsWithInsensitive(expr, " ASC")) {
        expr = std.mem.trim(u8, expr[0 .. expr.len - " ASC".len], " \t");
    }

    const out = try allocator.alloc(OrderBy, 1);
    errdefer allocator.free(out);
    if (parsed.kind == .node and parsed.node_pattern != null and std.mem.eql(u8, expr, parsed.node_pattern.?.var_name)) {
        out[0] = .{ .subject = .node, .field = "name", .descending = descending };
        return out;
    }

    const ref = try parseReference(expr);
    out[0] = .{ .subject = ref.subject, .field = ref.field, .descending = descending };
    return out;
}

fn parseReference(text: []const u8) !struct { subject: ValueSubject, field: []const u8 } {
    if (std.mem.indexOfScalar(u8, text, '.')) |dot| {
        const left = std.mem.trim(u8, text[0..dot], " \t");
        const right = std.mem.trim(u8, text[dot + 1 ..], " \t");
        return .{
            .subject = subjectFromVar(left),
            .field = right,
        };
    }
    return .{
        .subject = .node,
        .field = std.mem.trim(u8, text, " \t"),
    };
}

fn subjectFromVar(var_name: []const u8) ValueSubject {
    if (std.mem.eql(u8, var_name, "n")) return .node;
    if (std.mem.eql(u8, var_name, "a")) return .source;
    if (std.mem.eql(u8, var_name, "b")) return .target;
    if (std.mem.eql(u8, var_name, "r")) return .edge;
    return .node;
}

fn splitTopLevelComma(allocator: std.mem.Allocator, text: []const u8) std.ArrayList([]const u8) {
    var out = std.ArrayList([]const u8).empty;
    var depth: usize = 0;
    var start: usize = 0;
    var idx: usize = 0;
    while (idx < text.len) : (idx += 1) {
        switch (text[idx]) {
            '(' => depth += 1,
            ')' => {
                if (depth > 0) depth -= 1;
            },
            ',' => if (depth == 0) {
                out.append(allocator, text[start..idx]) catch {};
                start = idx + 1;
            },
            else => {},
        }
    }
    out.append(allocator, text[start..]) catch {};
    return out;
}

fn limitTextToken(text: []const u8) []const u8 {
    var end = text.len;
    for (text, 0..) |ch, idx| {
        if (std.ascii.isWhitespace(ch)) {
            end = idx;
            break;
        }
    }
    return text[0..end];
}

fn indexOfInsensitive(haystack: []const u8, needle: []const u8) ?usize {
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return i;
    }
    return null;
}

fn startsWithInsensitive(text: []const u8, prefix: []const u8) bool {
    if (text.len < prefix.len) return false;
    return std.ascii.eqlIgnoreCase(text[0..prefix.len], prefix);
}

fn endsWithInsensitive(text: []const u8, suffix: []const u8) bool {
    if (text.len < suffix.len) return false;
    return std.ascii.eqlIgnoreCase(text[text.len - suffix.len ..], suffix);
}

fn indexOfKeyword(text: []const u8, start: usize, keyword: []const u8) ?usize {
    const sub = text[start..];
    const pos = indexOfInsensitive(sub, keyword) orelse return null;
    return start + pos;
}

fn unquote(text: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, text, " \t");
    if (trimmed.len >= 2 and ((trimmed[0] == '"' and trimmed[trimmed.len - 1] == '"') or
        (trimmed[0] == '\'' and trimmed[trimmed.len - 1] == '\'')))
    {
        return trimmed[1 .. trimmed.len - 1];
    }
    return trimmed;
}

test "cypher can return a count" {
    var s = try Store.openMemory(std.testing.allocator);
    defer s.deinit();
    try s.upsertProject("p", "/tmp/p");
    _ = try s.upsertNode(.{
        .project = "p",
        .label = "Function",
        .name = "f",
        .qualified_name = "p:f",
        .file_path = "x.rs",
        .start_line = 1,
        .end_line = 2,
    });

    const result = try execute(std.testing.allocator, &s, "MATCH (n:Function) RETURN count(n) AS count", "p", 10);
    defer freeResult(std.testing.allocator, result);
    try std.testing.expectEqualStrings("count", result.columns[0]);
    try std.testing.expectEqualStrings("1", result.rows[0][0]);
}

test "cypher supports node field returns and ordering" {
    var s = try Store.openMemory(std.testing.allocator);
    defer s.deinit();
    try s.upsertProject("p", "/tmp/p");
    _ = try s.upsertNode(.{
        .project = "p",
        .label = "Function",
        .name = "b",
        .qualified_name = "p:b",
        .file_path = "b.rs",
    });
    _ = try s.upsertNode(.{
        .project = "p",
        .label = "Function",
        .name = "a",
        .qualified_name = "p:a",
        .file_path = "a.rs",
    });

    const result = try execute(
        std.testing.allocator,
        &s,
        "MATCH (n:Function) RETURN n.name, n.file_path ORDER BY n.name ASC LIMIT 1",
        "p",
        20,
    );
    defer freeResult(std.testing.allocator, result);
    try std.testing.expectEqual(@as(usize, 1), result.rows.len);
    try std.testing.expectEqualStrings("a", result.rows[0][0]);
    try std.testing.expectEqualStrings("a.rs", result.rows[0][1]);
}

test "cypher supports edge queries" {
    var s = try Store.openMemory(std.testing.allocator);
    defer s.deinit();
    try s.upsertProject("p", "/tmp/p");
    const a = try s.upsertNode(.{
        .project = "p",
        .label = "Function",
        .name = "main",
        .qualified_name = "p:main",
        .file_path = "main.py",
    });
    const b = try s.upsertNode(.{
        .project = "p",
        .label = "Function",
        .name = "helper",
        .qualified_name = "p:helper",
        .file_path = "helper.py",
    });
    _ = try s.upsertEdge(.{
        .project = "p",
        .source_id = a,
        .target_id = b,
        .edge_type = "CALLS",
        .properties_json = "{\"callee\":\"helper\"}",
    });

    const result = try execute(
        std.testing.allocator,
        &s,
        "MATCH (a)-[r:CALLS]->(b) RETURN a.name, b.name, r.callee LIMIT 5",
        "p",
        20,
    );
    defer freeResult(std.testing.allocator, result);
    try std.testing.expectEqual(@as(usize, 1), result.rows.len);
    try std.testing.expectEqualStrings("main", result.rows[0][0]);
    try std.testing.expectEqualStrings("helper", result.rows[0][1]);
    try std.testing.expectEqualStrings("helper", result.rows[0][2]);
}

test "cypher preserves defines edge queries" {
    var s = try Store.openMemory(std.testing.allocator);
    defer s.deinit();
    try s.upsertProject("p", "/tmp/p");
    const file = try s.upsertNode(.{
        .project = "p",
        .label = "File",
        .name = "main.py",
        .qualified_name = "p:file",
        .file_path = "main.py",
    });
    const fn_node = try s.upsertNode(.{
        .project = "p",
        .label = "Function",
        .name = "run",
        .qualified_name = "p:run",
        .file_path = "main.py",
    });
    _ = try s.upsertEdge(.{
        .project = "p",
        .source_id = file,
        .target_id = fn_node,
        .edge_type = "DEFINES",
    });

    const result = try execute(
        std.testing.allocator,
        &s,
        "MATCH (a)-[r:DEFINES]->(b) RETURN a.label, a.name, b.label, b.name",
        "p",
        20,
    );
    defer freeResult(std.testing.allocator, result);
    try std.testing.expectEqual(@as(usize, 1), result.rows.len);
    try std.testing.expectEqualStrings("File", result.rows[0][0]);
    try std.testing.expectEqualStrings("main.py", result.rows[0][1]);
    try std.testing.expectEqualStrings("Function", result.rows[0][2]);
    try std.testing.expectEqualStrings("run", result.rows[0][3]);
}

test "cypher preserves shared default edge ordering without ORDER BY" {
    var s = try Store.openMemory(std.testing.allocator);
    defer s.deinit();
    try s.upsertProject("p", "/tmp/p");
    const module = try s.upsertNode(.{
        .project = "p",
        .label = "Module",
        .name = "index",
        .qualified_name = "p:index",
        .file_path = "src/index.js",
        .start_line = 1,
        .end_line = 24,
    });
    const decorate = try s.upsertNode(.{
        .project = "p",
        .label = "Function",
        .name = "decorate",
        .qualified_name = "p:decorate",
        .file_path = "src/index.js",
        .start_line = 1,
        .end_line = 3,
    });
    const log = try s.upsertNode(.{
        .project = "p",
        .label = "Method",
        .name = "log",
        .qualified_name = "p:log",
        .file_path = "src/index.js",
        .start_line = 11,
        .end_line = 13,
    });
    const write = try s.upsertNode(.{
        .project = "p",
        .label = "Method",
        .name = "write",
        .qualified_name = "p:write",
        .file_path = "src/index.js",
        .start_line = 6,
        .end_line = 8,
    });
    const boot = try s.upsertNode(.{
        .project = "p",
        .label = "Function",
        .name = "boot",
        .qualified_name = "p:boot",
        .file_path = "src/index.js",
        .start_line = 18,
        .end_line = 24,
    });

    _ = try s.upsertEdge(.{ .project = "p", .source_id = log, .target_id = write, .edge_type = "CALLS" });
    _ = try s.upsertEdge(.{ .project = "p", .source_id = module, .target_id = decorate, .edge_type = "CALLS" });
    _ = try s.upsertEdge(.{ .project = "p", .source_id = module, .target_id = boot, .edge_type = "CALLS" });
    _ = try s.upsertEdge(.{ .project = "p", .source_id = boot, .target_id = log, .edge_type = "CALLS" });

    const result = try execute(
        std.testing.allocator,
        &s,
        "MATCH (a)-[r:CALLS]->(b) RETURN a.name, b.name",
        "p",
        20,
    );
    defer freeResult(std.testing.allocator, result);

    try std.testing.expectEqual(@as(usize, 4), result.rows.len);
    try std.testing.expectEqualStrings("boot", result.rows[0][0]);
    try std.testing.expectEqualStrings("log", result.rows[0][1]);
    try std.testing.expectEqualStrings("index", result.rows[1][0]);
    try std.testing.expectEqualStrings("decorate", result.rows[1][1]);
    try std.testing.expectEqualStrings("index", result.rows[2][0]);
    try std.testing.expectEqualStrings("boot", result.rows[2][1]);
    try std.testing.expectEqualStrings("log", result.rows[3][0]);
    try std.testing.expectEqualStrings("write", result.rows[3][1]);
}

test "cypher reports unsupported queries as errors" {
    var s = try Store.openMemory(std.testing.allocator);
    defer s.deinit();

    const result = try execute(std.testing.allocator, &s, "RETURN 1", null, 10);
    defer freeResult(std.testing.allocator, result);

    try std.testing.expect(result.err != null);
    try std.testing.expectEqualStrings("unsupported query", result.err.?);
}

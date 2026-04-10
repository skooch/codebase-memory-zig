// cypher.zig — Lightweight read-only query bridge for readiness tests.
//
// This intentionally implements a constrained subset:
//   * MATCH (n) filtering by label, name, qualified_name, and file_path patterns
//   * RETURN n.* shapes
//   * RETURN count(n)

const std = @import("std");
const store = @import("store.zig");

const Store = store.Store;

const TokenType = enum { lparen, rparen, where_kw, return_kw, count_kw, id_kw, and_kw, or_kw, unknown };

pub const CypherResult = struct {
    columns: [][]const u8,
    rows: [][][]const u8,
    err: ?[]const u8 = null,
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
    const lowered = try toLower(allocator, query);
    defer allocator.free(lowered);

    if (std.mem.indexOf(u8, lowered, "return count") != null) {
        var filter = store.NodeSearchFilter{ .project = project orelse "", .limit = @as(usize, @max(1, max_rows)) };
        if (extractEqualsValue(allocator, query, "label")) |v| {
            filter.label_pattern = try allocator.dupe(u8, v);
        }
        if (extractEqualsValue(allocator, query, "name")) |v| {
            filter.name_pattern = try allocator.dupe(u8, v);
        }
        if (extractEqualsValue(allocator, query, "qualified_name")) |v| {
            filter.qn_pattern = try allocator.dupe(u8, v);
        }
        if (extractEqualsValue(allocator, query, "file_path")) |v| {
            filter.file_pattern = try allocator.dupe(u8, v);
        }
        defer {
            if (filter.label_pattern) |v| allocator.free(v);
            if (filter.name_pattern) |v| allocator.free(v);
            if (filter.qn_pattern) |v| allocator.free(v);
            if (filter.file_pattern) |v| allocator.free(v);
        }

        const nodes = try db.searchNodes(filter);
        defer db.freeNodes(nodes);
        const columns = try allocator.alloc([]const u8, 1);
        errdefer allocator.free(columns);
        columns[0] = try allocator.dupe(u8, "count");
        errdefer allocator.free(columns[0]);
        const rows = try allocator.alloc([][]const u8, 1);
        errdefer allocator.free(rows);
        rows[0] = try allocator.alloc([]const u8, 1);
        errdefer allocator.free(rows[0]);
        rows[0][0] = try std.fmt.allocPrint(allocator, "{d}", .{nodes.len});
        errdefer allocator.free(rows[0][0]);
        return CypherResult{
            .columns = columns,
            .rows = rows,
            .err = null,
        };
    }

    if (std.mem.indexOf(u8, lowered, "match (n)") == null) {
        return CypherResult{
            .columns = try allocator.alloc([]const u8, 0),
            .rows = try allocator.alloc([][]const u8, 0),
            .err = try allocator.dupe(u8, "unsupported query"),
        };
    }

    var filter = store.NodeSearchFilter{ .project = project orelse "", .limit = @as(usize, @max(1, max_rows)) };
    if (extractEqualsValue(allocator, query, "label")) |v| {
        filter.label_pattern = try allocator.dupe(u8, v);
    }
    if (extractEqualsValue(allocator, query, "name")) |v| {
        filter.name_pattern = try allocator.dupe(u8, v);
    }
    if (extractEqualsValue(allocator, query, "qualified_name")) |v| {
        filter.qn_pattern = try allocator.dupe(u8, v);
    }
    if (extractEqualsValue(allocator, query, "file_path")) |v| {
        filter.file_pattern = try allocator.dupe(u8, v);
    }
    defer {
        if (filter.label_pattern) |v| allocator.free(v);
        if (filter.name_pattern) |v| allocator.free(v);
        if (filter.qn_pattern) |v| allocator.free(v);
        if (filter.file_pattern) |v| allocator.free(v);
    }

    const nodes = try db.searchNodes(filter);
    errdefer db.freeNodes(nodes);

    const columns = try allocator.alloc([]const u8, 5);
    var columns_filled: usize = 0;
    errdefer {
        for (columns[0..columns_filled]) |column| allocator.free(column);
        allocator.free(columns);
    }
    columns[columns_filled] = try allocator.dupe(u8, "id");
    columns_filled += 1;
    columns[columns_filled] = try allocator.dupe(u8, "label");
    columns_filled += 1;
    columns[columns_filled] = try allocator.dupe(u8, "name");
    columns_filled += 1;
    columns[columns_filled] = try allocator.dupe(u8, "qualified_name");
    columns_filled += 1;
    columns[columns_filled] = try allocator.dupe(u8, "file_path");
    columns_filled += 1;

    const out_rows = try allocator.alloc([][]const u8, nodes.len);
    var rows_filled: usize = 0;
    errdefer {
        for (out_rows[0..rows_filled]) |row| {
            for (row) |cell| allocator.free(cell);
            allocator.free(row);
        }
        allocator.free(out_rows);
    }
    for (nodes, 0..) |node, idx| {
        const row = try allocator.alloc([]const u8, 5);
        var cells_filled: usize = 0;
        errdefer {
            for (row[0..cells_filled]) |cell| allocator.free(cell);
            allocator.free(row);
        }
        row[cells_filled] = try std.fmt.allocPrint(allocator, "{d}", .{node.id});
        cells_filled += 1;
        row[cells_filled] = try allocator.dupe(u8, node.label);
        cells_filled += 1;
        row[cells_filled] = try allocator.dupe(u8, node.name);
        cells_filled += 1;
        row[cells_filled] = try allocator.dupe(u8, node.qualified_name);
        cells_filled += 1;
        row[cells_filled] = try allocator.dupe(u8, node.file_path);
        out_rows[idx] = row;
        rows_filled += 1;
    }
    db.freeNodes(nodes);
    return CypherResult{
        .columns = columns,
        .rows = out_rows,
        .err = null,
    };
}

fn toLower(allocator: std.mem.Allocator, query: []const u8) ![]u8 {
    const out = try allocator.dupe(u8, query);
    for (out) |*ch| {
        ch.* = std.ascii.toLower(ch.*);
    }
    return out;
}

fn extractEqualsValue(allocator: std.mem.Allocator, query: []const u8, key: []const u8) ?[]const u8 {
    const marker = std.fmt.allocPrint(allocator, "n.{s}", .{key}) catch return null;
    defer allocator.free(marker);

    const pos = std.mem.indexOf(u8, query, marker) orelse return null;
    const after = query[pos + marker.len ..];
    const eq = std.mem.indexOf(u8, after, "=") orelse return null;
    const rhs = std.mem.trim(u8, after[eq + 1 ..], " \t");
    if (rhs.len == 0) return null;
    if (rhs[0] != '"' and rhs[0] != '\'') {
        return std.mem.trim(u8, rhs, " );\n");
    }
    const quote = rhs[0];
    const end = std.mem.indexOfScalarPos(u8, rhs, 1, quote) orelse return null;
    return rhs[1..end];
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

    const result = try execute(std.testing.allocator, &s, "MATCH (n) WHERE n.label = \"Function\" RETURN count(n)", "p", 10);
    defer freeResult(std.testing.allocator, result);
    try std.testing.expect(result.columns.len == 1);
    try std.testing.expectEqualStrings("count", result.columns[0]);
    try std.testing.expectEqual(@as(usize, 1), result.rows.len);
    try std.testing.expectEqualStrings("1", result.rows[0][0]);
}

test "cypher reports unsupported queries as errors" {
    var s = try Store.openMemory(std.testing.allocator);
    defer s.deinit();

    const result = try execute(std.testing.allocator, &s, "RETURN 1", null, 10);
    defer freeResult(std.testing.allocator, result);

    try std.testing.expectEqual(@as(usize, 0), result.columns.len);
    try std.testing.expectEqual(@as(usize, 0), result.rows.len);
    try std.testing.expect(result.err != null);
    try std.testing.expectEqualStrings("unsupported query", result.err.?);
}

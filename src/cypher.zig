// cypher.zig — Cypher query engine.
//
// Subset of Cypher for read-only graph queries:
//   MATCH (n:Label)-[:TYPE*1..3]->(m)
//   WHERE n.name =~ "pattern" AND m.label = "Function"
//   RETURN n.name, COUNT(m) AS cnt ORDER BY cnt DESC LIMIT 10

const std = @import("std");

pub const TokenType = enum {
    // Keywords
    match,
    where,
    @"return",
    order,
    by,
    limit,
    @"and",
    @"or",
    as,
    distinct,
    count,
    contains,
    starts,
    with,
    not,
    asc,
    desc,
    ends,
    in,
    is,
    null_kw,
    skip,
    union_kw,
    unwind,

    // Aggregate functions
    sum,
    avg,
    min_kw,
    max_kw,
    collect,

    // String functions
    toLower,
    toUpper,
    toString,

    // CASE
    case,
    when,
    then,
    else_kw,
    end,

    // Symbols
    lparen,
    rparen,
    lbracket,
    rbracket,
    dash,
    gt,
    lt,
    colon,
    dot,
    lbrace,
    rbrace,
    star,
    comma,
    eq,
    eq_tilde,
    gte,
    lte,
    neq,
    pipe,
    dot_dot,

    // Literals
    ident,
    string,
    number,

    eof,
};

pub const Token = struct {
    token_type: TokenType,
    text: []const u8,
    pos: u32,
};

pub const CypherResult = struct {
    columns: [][]const u8,
    rows: [][][]const u8,
    err: ?[]const u8 = null,
};

pub fn execute(
    allocator: std.mem.Allocator,
    query: []const u8,
    project: ?[]const u8,
    max_rows: u32,
) !CypherResult {
    _ = allocator;
    _ = query;
    _ = project;
    _ = max_rows;
    // TODO: lex -> parse -> plan -> execute against store
    return .{
        .columns = &.{},
        .rows = &.{},
    };
}

test "cypher token types exist" {
    // Smoke test that the enum compiles.
    try std.testing.expectEqual(TokenType.match, TokenType.match);
}

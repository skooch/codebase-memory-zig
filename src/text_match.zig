// text_match.zig — Shared text matching helpers for regex-ish and glob patterns.

const std = @import("std");

/// Simplified regex-like matching: handles ^...$, .* wildcards, and substring matching.
/// Allocates temporarily for .* stripping; caller provides allocator.
pub fn matchRegexish(allocator: std.mem.Allocator, actual: []const u8, pattern: []const u8) bool {
    if (expandAlternationAndMatch(allocator, actual, pattern)) |matched| return matched;
    if (pattern.len >= 2 and pattern[0] == '^' and pattern[pattern.len - 1] == '$') {
        const inner = pattern[1 .. pattern.len - 1];
        if (std.mem.eql(u8, inner, ".*")) return true;
        if (std.mem.startsWith(u8, inner, ".*") and std.mem.endsWith(u8, inner, ".*") and inner.len >= 4) {
            return std.mem.indexOf(u8, actual, inner[2 .. inner.len - 2]) != null;
        }
        return std.mem.eql(u8, actual, inner);
    }
    if (std.mem.indexOf(u8, pattern, ".*") == null) {
        return std.mem.indexOf(u8, actual, pattern) != null;
    }
    // Strip .* sequences and check if remainder is a substring
    var tmp = std.ArrayList(u8).empty;
    defer tmp.deinit(allocator);
    var i: usize = 0;
    while (i < pattern.len) : (i += 1) {
        if (pattern[i] == '.' and i + 1 < pattern.len and pattern[i + 1] == '*') {
            i += 1;
            continue;
        }
        tmp.append(allocator, pattern[i]) catch return false;
    }
    if (tmp.items.len == 0) return true;
    return std.mem.indexOf(u8, actual, tmp.items) != null;
}

fn expandAlternationAndMatch(
    allocator: std.mem.Allocator,
    actual: []const u8,
    pattern: []const u8,
) ?bool {
    if (pattern.len == 0) return null;

    var depth: usize = 0;
    var first_pipe: ?usize = null;
    for (pattern, 0..) |ch, idx| {
        switch (ch) {
            '(' => depth += 1,
            ')' => {
                if (depth > 0) depth -= 1;
            },
            '|' => if (depth == 0) {
                first_pipe = idx;
                break;
            },
            else => {},
        }
    }
    if (first_pipe) |_| {
        var branch_start: usize = 0;
        depth = 0;
        for (pattern, 0..) |ch, idx| {
            switch (ch) {
                '(' => depth += 1,
                ')' => {
                    if (depth > 0) depth -= 1;
                },
                '|' => if (depth == 0) {
                    if (matchRegexish(allocator, actual, pattern[branch_start..idx])) return true;
                    branch_start = idx + 1;
                },
                else => {},
            }
        }
        return matchRegexish(allocator, actual, pattern[branch_start..]);
    }

    const open = std.mem.indexOfScalar(u8, pattern, '(') orelse return null;
    const close_offset = std.mem.indexOfScalar(u8, pattern[open + 1 ..], ')') orelse return null;
    const close = open + 1 + close_offset;
    const group = pattern[open + 1 .. close];
    if (std.mem.indexOfScalar(u8, group, '|') == null) return null;

    var iter = std.mem.splitScalar(u8, group, '|');
    while (iter.next()) |branch| {
        const expanded = std.fmt.allocPrint(allocator, "{s}{s}{s}", .{
            pattern[0..open],
            branch,
            pattern[close + 1 ..],
        }) catch return false;
        defer allocator.free(expanded);
        if (matchRegexish(allocator, actual, expanded)) return true;
    }
    return false;
}

/// Simple glob matching with a single * wildcard.
pub fn globMatch(text: []const u8, pattern: []const u8) bool {
    if (std.mem.eql(u8, pattern, "*")) return true;
    if (std.mem.indexOfScalar(u8, pattern, '*') == null) return std.mem.eql(u8, text, pattern);
    if (std.mem.startsWith(u8, pattern, "*") and std.mem.endsWith(u8, pattern, "*") and pattern.len >= 2) {
        return std.mem.indexOf(u8, text, pattern[1 .. pattern.len - 1]) != null;
    }
    if (std.mem.startsWith(u8, pattern, "*")) return std.mem.endsWith(u8, text, pattern[1..]);
    if (std.mem.endsWith(u8, pattern, "*")) return std.mem.startsWith(u8, text, pattern[0 .. pattern.len - 1]);
    const star = std.mem.indexOfScalar(u8, pattern, '*') orelse return false;
    return std.mem.startsWith(u8, text, pattern[0..star]) and std.mem.endsWith(u8, text, pattern[star + 1 ..]);
}

test "matchRegexish anchored exact" {
    try std.testing.expect(matchRegexish(std.testing.allocator, "hello", "^hello$"));
    try std.testing.expect(!matchRegexish(std.testing.allocator, "hello world", "^hello$"));
}

test "matchRegexish wildcard" {
    try std.testing.expect(matchRegexish(std.testing.allocator, "anything", "^.*$"));
    try std.testing.expect(matchRegexish(std.testing.allocator, "foo bar baz", "^.*bar.*$"));
}

test "matchRegexish strip dotstar" {
    try std.testing.expect(matchRegexish(std.testing.allocator, "hello world", ".*hello.*"));
    try std.testing.expect(matchRegexish(std.testing.allocator, "hello world", "hello"));
    try std.testing.expect(!matchRegexish(std.testing.allocator, "goodbye", "hello"));
}

test "matchRegexish alternation groups" {
    try std.testing.expect(matchRegexish(std.testing.allocator, "needle alpha", "needle (alpha|beta)"));
    try std.testing.expect(matchRegexish(std.testing.allocator, "needle beta", "needle (alpha|beta)"));
    try std.testing.expect(!matchRegexish(std.testing.allocator, "needle gamma", "needle (alpha|beta)"));
}

test "globMatch patterns" {
    try std.testing.expect(globMatch("anything", "*"));
    try std.testing.expect(globMatch("foo.zig", "*.zig"));
    try std.testing.expect(globMatch("src/main", "src/*"));
    try std.testing.expect(globMatch("src/main.zig", "*main*"));
    try std.testing.expect(!globMatch("foo.py", "*.zig"));
}

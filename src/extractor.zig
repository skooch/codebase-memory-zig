// extractor.zig — Lightweight extraction stage.
//
// Current phase: create file/module nodes and discover simple symbols from source text
// for Rust, Zig, Python, and JavaScript-like languages.

const std = @import("std");
const discover = @import("discover.zig");
const graph_buffer = @import("graph_buffer.zig");

const ParsedSymbol = struct {
    label: []const u8,
    name: []const u8,
};

pub fn extractFile(
    allocator: std.mem.Allocator,
    project_name: []const u8,
    file: discover.FileInfo,
    gb: *graph_buffer.GraphBuffer,
) !void {
    const rel = file.rel_path;
    const file_name = std.fs.path.basename(rel);
    const stem = std.fs.path.stem(file_name);

    const qn_base = try normalizePath(allocator, rel);
    defer allocator.free(qn_base);

    const file_qn = try std.fmt.allocPrint(
        allocator,
        "{s}:file:{s}:{s}",
        .{ project_name, qn_base, @tagName(file.language) },
    );
    defer allocator.free(file_qn);

    const file_id = gb.upsertNode(
        "File",
        file_name,
        file_qn,
        rel,
        1,
        1,
    );
    if (file_id == 0) return;

    var module_id: i64 = file_id;
    if (stem.len > 0) {
        const module_qn = try std.fmt.allocPrint(
            allocator,
            "{s}:module:{s}:{s}",
            .{ project_name, qn_base, @tagName(file.language) },
        );
        defer allocator.free(module_qn);

        const symbol_name = if (stem.len > 0) stem else file_name;
        const module_name = symbol_name;
        const created_module = gb.upsertNode(
            "Module",
            module_name,
            module_qn,
            rel,
            1,
            1,
        );
        if (created_module > 0) {
            module_id = created_module;
            _ = gb.insertEdge(file_id, module_id, "CONTAINS");
        }
    }

    const bytes = std.fs.cwd().readFileAlloc(allocator, file.path, 8 * 1024 * 1024) catch |err| switch (err) {
        error.IsDir => return,
        else => return err,
    };
    defer allocator.free(bytes);

    var lines = std.mem.splitAny(u8, bytes, "\n\r");
    var line_no: i32 = 1;
    while (lines.next()) |line_raw| : (line_no += 1) {
        const line = std.mem.trim(u8, line_raw, " \t");
        if (line.len == 0) continue;
        const symbol = parseSymbol(file.language, line) orelse continue;

        const symbol_qn = try std.fmt.allocPrint(
            allocator,
            "{s}:{s}:{s}:symbol:{s}:{s}",
            .{ project_name, qn_base, @tagName(file.language), @tagName(file.language), symbol.name },
        );
        defer allocator.free(symbol_qn);

        const symbol_id = gb.upsertNode(
            symbol.label,
            symbol.name,
            symbol_qn,
            rel,
            line_no,
            line_no,
        );
        if (symbol_id > 0) {
            _ = gb.insertEdge(module_id, symbol_id, "CONTAINS");
        }
    }
}

fn normalizePath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const copied = try allocator.dupe(u8, path);
    for (copied) |*c| {
        if (c.* == std.fs.path.sep) c.* = '/';
    }
    return copied;
}

fn isIdentifierChar(c: u8) bool {
    return std.ascii.isAlphabetic(c) or
        std.ascii.isDigit(c) or
        c == '_' or
        c == '-';
}

fn isIdentifierStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) || c == '_';
}

fn parseToken(line: []const u8, prefix: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, line, prefix)) return null;
    var start = prefix.len;
    while (start < line.len and line[start] == ' ') start += 1;
    while (start < line.len and line[start] == '\t') start += 1;
    if (start >= line.len or !isIdentifierStart(line[start])) return null;

    var end = start + 1;
    while (end < line.len and isIdentifierChar(line[end])) end += 1;
    return line[start..end];
}

fn parseSymbol(language: discover.Language, line: []const u8) ?ParsedSymbol {
    switch (language) {
        .python => {
            if (parseToken(line, "def ")) |name| return .{ .label = "Function", .name = name };
            if (parseToken(line, "class ")) |name| return .{ .label = "Class", .name = name };
        },
        .javascript, .typescript, .tsx => {
            if (parseToken(line, "function ")) |name| return .{ .label = "Function", .name = name };
            if (parseToken(line, "async function ")) |name| return .{ .label = "Function", .name = name };
            if (parseToken(line, "class ")) |name| return .{ .label = "Class", .name = name };
        },
        .rust => {
            if (parseToken(line, "fn ")) |name| return .{ .label = "Function", .name = name };
            if (parseToken(line, "pub fn ")) |name| return .{ .label = "Function", .name = name };
            if (parseToken(line, "impl ")) |name| return .{ .label = "Class", .name = name };
            if (parseToken(line, "struct ")) |name| return .{ .label = "Class", .name = name };
        },
        .zig => {
            if (parseToken(line, "fn ")) |name| return .{ .label = "Function", .name = name };
            if (parseToken(line, "pub fn ")) |name| return .{ .label = "Function", .name = name };
            if (parseToken(line, "const ")) |name| return .{ .label = "Constant", .name = name };
            if (parseToken(line, "test ")) |name| return .{ .label = "Test", .name = name };
        },
        else => return null,
    }
    return null;
}

const std = @import("std");
const discover = @import("discover.zig");
const store = @import("store.zig");

const max_index_bytes = 8 * 1024 * 1024;

fn isTokenByte(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '_';
}

pub fn refreshProject(
    allocator: std.mem.Allocator,
    db: *store.Store,
    project: []const u8,
    files: []const discover.FileInfo,
) !void {
    try db.clearSearchDocuments(project);
    for (files) |file| {
        const bytes = std.fs.cwd().readFileAlloc(allocator, file.path, max_index_bytes) catch continue;
        defer allocator.free(bytes);
        try db.insertSearchDocument(project, file.rel_path, bytes);
    }
}

pub fn findCandidatePaths(
    allocator: std.mem.Allocator,
    db: *store.Store,
    project: []const u8,
    pattern: []const u8,
    regex: bool,
    limit: usize,
) !?[][]u8 {
    const query = (try buildFtsQuery(allocator, pattern, regex)) orelse return null;
    defer allocator.free(query);

    const candidate_limit = @max(if (limit == 0) @as(usize, 32) else limit * 8, 32);
    const paths = try db.searchDocumentPaths(project, query, candidate_limit);
    if (paths.len == 0) {
        db.freePaths(paths);
        return null;
    }
    return paths;
}

pub fn buildFtsQuery(allocator: std.mem.Allocator, pattern: []const u8, regex: bool) !?[]u8 {
    if (regex) return null;

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    var token_count: usize = 0;
    var token_start: ?usize = null;
    var idx: usize = 0;
    while (idx <= pattern.len) : (idx += 1) {
        const at_end = idx == pattern.len;
        const token_byte = if (!at_end) isTokenByte(pattern[idx]) else false;
        if (token_byte) {
            if (token_start == null) token_start = idx;
            continue;
        }

        if (token_start) |start| {
            const token = pattern[start..idx];
            if (token.len >= 2) {
                if (token_count > 0) try out.appendSlice(allocator, " AND ");
                try out.appendSlice(allocator, token);
                try out.append(allocator, '*');
                token_count += 1;
            }
            token_start = null;
        }
    }

    if (token_count == 0) return null;
    return try out.toOwnedSlice(allocator);
}

test "buildFtsQuery extracts prefix terms from plain text patterns" {
    const allocator = std.testing.allocator;

    const query = (try buildFtsQuery(allocator, "helper call()", false)).?;
    defer allocator.free(query);
    try std.testing.expectEqualStrings("helper* AND call*", query);

    try std.testing.expect((try buildFtsQuery(allocator, "x", false)) == null);
    try std.testing.expect((try buildFtsQuery(allocator, "^helper$", true)) == null);
}

test "refreshProject populates searchable paths" {
    const allocator = std.testing.allocator;
    const project_dir = try std.fmt.allocPrint(allocator, "/tmp/cbm-search-index-{x}", .{std.crypto.random.int(u64)});
    defer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    const src_dir = try std.fs.path.join(allocator, &.{ project_dir, "src" });
    defer allocator.free(src_dir);
    try std.fs.cwd().makePath(src_dir);

    const file_path = try std.fs.path.join(allocator, &.{ project_dir, "src", "main.py" });
    defer allocator.free(file_path);
    var file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();
    try file.writeAll(
        \\def helper():
        \\    return 1
        \\
    );

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();
    try db.upsertProject("demo", project_dir);

    const files = try allocator.alloc(discover.FileInfo, 1);
    defer {
        allocator.free(files[0].path);
        allocator.free(files[0].rel_path);
        allocator.free(files);
    }
    files[0] = .{
        .path = try allocator.dupe(u8, file_path),
        .rel_path = try allocator.dupe(u8, "src/main.py"),
        .language = .python,
        .size = 0,
    };

    try refreshProject(allocator, &db, "demo", files);
    const candidates = (try findCandidatePaths(allocator, &db, "demo", "helper", false, 5)).?;
    defer db.freePaths(candidates);
    try std.testing.expectEqual(@as(usize, 1), candidates.len);
    try std.testing.expectEqualStrings("src/main.py", candidates[0]);
}

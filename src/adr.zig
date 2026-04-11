const std = @import("std");

pub const Entry = struct {
    project: []const u8,
    content: []const u8,
    created_at: []const u8,
    updated_at: []const u8,
};

pub fn listMarkdownSections(allocator: std.mem.Allocator, content: []const u8) ![][]u8 {
    var sections = std.ArrayList([]u8).empty;
    errdefer {
        for (sections.items) |section| allocator.free(section);
        sections.deinit(allocator);
    }

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trimRight(u8, line_raw, "\r");
        if (line.len == 0 or line[0] != '#') continue;
        try sections.append(allocator, try allocator.dupe(u8, line));
    }

    return sections.toOwnedSlice(allocator);
}

// watcher.zig — File change watcher for auto-reindexing.
//
// Polls indexed projects for git changes (HEAD movement or dirty working tree)
// and triggers re-indexing via a callback. Uses adaptive polling intervals
// based on project size (5s base + 1s per 500 files, capped at 60s).

const std = @import("std");

pub const IndexFn = *const fn (project_name: []const u8, root_path: []const u8) anyerror!void;

const WatchEntry = struct {
    project_name: []const u8,
    root_path: []const u8,
    last_head: [40]u8 = [_]u8{0} ** 40,
    interval_ms: u32 = 5000,
};

pub const Watcher = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(WatchEntry),
    index_fn: ?IndexFn = null,
    should_stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    pub fn init(allocator: std.mem.Allocator, index_fn: ?IndexFn) Watcher {
        return .{
            .allocator = allocator,
            .entries = .empty,
            .index_fn = index_fn,
        };
    }

    pub fn deinit(self: *Watcher) void {
        self.entries.deinit(self.allocator);
    }

    pub fn watch(self: *Watcher, project_name: []const u8, root_path: []const u8) !void {
        try self.entries.append(self.allocator, .{
            .project_name = project_name,
            .root_path = root_path,
        });
    }

    pub fn unwatch(self: *Watcher, project_name: []const u8) void {
        var i: usize = 0;
        while (i < self.entries.items.len) {
            if (std.mem.eql(u8, self.entries.items[i].project_name, project_name)) {
                _ = self.entries.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    pub fn stop(self: *Watcher) void {
        self.should_stop.store(true, .release);
    }

    pub fn pollIntervalMs(file_count: u32) u32 {
        const base: u32 = 5000;
        const extra = file_count / 500 * 1000;
        return @min(base + extra, 60000);
    }
};

test "poll interval calculation" {
    try std.testing.expectEqual(@as(u32, 5000), Watcher.pollIntervalMs(0));
    try std.testing.expectEqual(@as(u32, 6000), Watcher.pollIntervalMs(500));
    try std.testing.expectEqual(@as(u32, 15000), Watcher.pollIntervalMs(5000));
    try std.testing.expectEqual(@as(u32, 60000), Watcher.pollIntervalMs(100000));
}

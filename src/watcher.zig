// watcher.zig — Git-based file change watcher for auto-reindex.
//
// Tracks watched projects, establishes a git baseline on first poll, and then
// triggers an indexing callback whenever HEAD moves or the working tree is
// dirty. Poll intervals are adaptive based on tracked file count.

const std = @import("std");

pub const IndexFn = *const fn (project_name: []const u8, root_path: []const u8) anyerror!void;

const WatchEntry = struct {
    project_name: []u8,
    root_path: []u8,
    last_head: []u8,
    is_git: bool = false,
    baseline_done: bool = false,
    file_count: u32 = 0,
    interval_ms: u32 = 5000,
    next_poll_ns: i64 = 0,

    fn deinit(self: WatchEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.project_name);
        allocator.free(self.root_path);
        allocator.free(self.last_head);
    }
};

const CommandOutput = struct {
    stdout: []u8,
    stderr: []u8,
    term: std.process.Child.Term,

    fn deinit(self: CommandOutput, allocator: std.mem.Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
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
        for (self.entries.items) |entry| {
            entry.deinit(self.allocator);
        }
        self.entries.deinit(self.allocator);
    }

    pub fn watch(self: *Watcher, project_name: []const u8, root_path: []const u8) !void {
        self.unwatch(project_name);
        try self.entries.append(self.allocator, .{
            .project_name = try self.allocator.dupe(u8, project_name),
            .root_path = try self.allocator.dupe(u8, root_path),
            .last_head = try self.allocator.dupe(u8, ""),
        });
    }

    pub fn unwatch(self: *Watcher, project_name: []const u8) void {
        var idx: usize = 0;
        while (idx < self.entries.items.len) {
            if (std.mem.eql(u8, self.entries.items[idx].project_name, project_name)) {
                const removed = self.entries.orderedRemove(idx);
                removed.deinit(self.allocator);
            } else {
                idx += 1;
            }
        }
    }

    pub fn touch(self: *Watcher, project_name: []const u8) void {
        for (self.entries.items) |*entry| {
            if (std.mem.eql(u8, entry.project_name, project_name)) {
                entry.next_poll_ns = 0;
                return;
            }
        }
    }

    pub fn watchCount(self: *const Watcher) usize {
        return self.entries.items.len;
    }

    pub fn stop(self: *Watcher) void {
        self.should_stop.store(true, .release);
    }

    pub fn pollOnce(self: *Watcher) !u32 {
        var reindexed: u32 = 0;
        const now = nowNs();

        for (self.entries.items) |*entry| {
            if (!entry.baseline_done) {
                try initBaseline(self.allocator, entry);
                continue;
            }
            if (!entry.is_git) continue;
            if (now < entry.next_poll_ns) continue;

            if (!(try checkForChanges(self.allocator, entry))) {
                entry.next_poll_ns = now + intervalToNs(entry.interval_ms);
                continue;
            }

            if (self.index_fn) |index_fn| {
                index_fn(entry.project_name, entry.root_path) catch {
                    entry.next_poll_ns = now + intervalToNs(entry.interval_ms);
                    continue;
                };
                reindexed += 1;
            }

            const refreshed_head = try gitHead(self.allocator, entry.root_path);
            self.allocator.free(entry.last_head);
            entry.last_head = refreshed_head;
            entry.file_count = try gitFileCount(self.allocator, entry.root_path);
            entry.interval_ms = pollIntervalMs(entry.file_count);
            entry.next_poll_ns = now + intervalToNs(entry.interval_ms);
        }

        return reindexed;
    }

    pub fn run(self: *Watcher, base_interval_ms: u32) !void {
        const sleep_ms = if (base_interval_ms == 0) 5000 else base_interval_ms;
        while (!self.should_stop.load(.acquire)) {
            _ = try self.pollOnce();

            var slept_ms: u32 = 0;
            while (slept_ms < sleep_ms and !self.should_stop.load(.acquire)) {
                const chunk_ms = @min(@as(u32, 500), sleep_ms - slept_ms);
                std.Thread.sleep(@as(u64, chunk_ms) * std.time.ns_per_ms);
                slept_ms += chunk_ms;
            }
        }
    }

    pub fn pollIntervalMs(file_count: u32) u32 {
        const base: u32 = 5000;
        const extra = (file_count / 500) * 1000;
        return @min(base + extra, 60000);
    }
};

fn nowNs() i64 {
    return @intCast(std.time.nanoTimestamp());
}

fn intervalToNs(interval_ms: u32) i64 {
    return @as(i64, @intCast(interval_ms)) * std.time.ns_per_ms;
}

fn initBaseline(allocator: std.mem.Allocator, entry: *WatchEntry) !void {
    entry.baseline_done = true;

    var dir = std.fs.cwd().openDir(entry.root_path, .{}) catch {
        entry.is_git = false;
        entry.next_poll_ns = nowNs() + intervalToNs(entry.interval_ms);
        return;
    };
    dir.close();

    entry.is_git = try isGitRepo(allocator, entry.root_path);
    if (!entry.is_git) {
        entry.next_poll_ns = nowNs() + intervalToNs(entry.interval_ms);
        return;
    }

    const head = try gitHead(allocator, entry.root_path);
    allocator.free(entry.last_head);
    entry.last_head = head;
    entry.file_count = try gitFileCount(allocator, entry.root_path);
    entry.interval_ms = Watcher.pollIntervalMs(entry.file_count);
    entry.next_poll_ns = nowNs() + intervalToNs(entry.interval_ms);
}

fn checkForChanges(allocator: std.mem.Allocator, entry: *WatchEntry) !bool {
    if (!entry.is_git) return false;

    const head = try gitHead(allocator, entry.root_path);
    defer allocator.free(head);
    if (entry.last_head.len > 0 and !std.mem.eql(u8, head, entry.last_head)) {
        allocator.free(entry.last_head);
        entry.last_head = try allocator.dupe(u8, head);
        return true;
    }

    allocator.free(entry.last_head);
    entry.last_head = try allocator.dupe(u8, head);
    return try gitIsDirty(allocator, entry.root_path);
}

fn isGitRepo(allocator: std.mem.Allocator, root_path: []const u8) !bool {
    const result = try runCommand(
        allocator,
        &.{ "git", "-C", root_path, "rev-parse", "--git-dir" },
    );
    defer result.deinit(allocator);
    return switch (result.term) {
        .Exited => |code| code == 0,
        else => false,
    };
}

fn gitHead(allocator: std.mem.Allocator, root_path: []const u8) ![]u8 {
    const result = try runCommand(
        allocator,
        &.{ "git", "-C", root_path, "rev-parse", "HEAD" },
    );
    defer result.deinit(allocator);
    return switch (result.term) {
        .Exited => |code| if (code == 0)
            allocator.dupe(u8, std.mem.trim(u8, result.stdout, " \t\r\n"))
        else
            allocator.dupe(u8, ""),
        else => allocator.dupe(u8, ""),
    };
}

fn gitIsDirty(allocator: std.mem.Allocator, root_path: []const u8) !bool {
    const result = try runCommand(
        allocator,
        &.{ "git", "-C", root_path, "status", "--porcelain", "--untracked-files=normal" },
    );
    defer result.deinit(allocator);
    return switch (result.term) {
        .Exited => |code| code == 0 and std.mem.trim(u8, result.stdout, " \t\r\n").len > 0,
        else => false,
    };
}

fn gitFileCount(allocator: std.mem.Allocator, root_path: []const u8) !u32 {
    const result = try runCommand(
        allocator,
        &.{ "git", "-C", root_path, "ls-files" },
    );
    defer result.deinit(allocator);
    return switch (result.term) {
        .Exited => |code| if (code == 0)
            countNonEmptyLines(result.stdout)
        else
            0,
        else => 0,
    };
}

fn countNonEmptyLines(text: []const u8) u32 {
    var count: u32 = 0;
    var iter = std.mem.splitAny(u8, text, "\n\r");
    while (iter.next()) |line| {
        if (std.mem.trim(u8, line, " \t").len > 0) count += 1;
    }
    return count;
}

fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) !CommandOutput {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .max_output_bytes = 8 * 1024 * 1024,
    });
    return .{
        .stdout = result.stdout,
        .stderr = result.stderr,
        .term = result.term,
    };
}

test "poll interval calculation" {
    try std.testing.expectEqual(@as(u32, 5000), Watcher.pollIntervalMs(0));
    try std.testing.expectEqual(@as(u32, 6000), Watcher.pollIntervalMs(500));
    try std.testing.expectEqual(@as(u32, 15000), Watcher.pollIntervalMs(5000));
    try std.testing.expectEqual(@as(u32, 60000), Watcher.pollIntervalMs(100000));
}

var test_watch_hits = std.atomic.Value(u32).init(0);

fn testIndexFn(_: []const u8, _: []const u8) !void {
    _ = test_watch_hits.fetchAdd(1, .acq_rel);
}

test "watcher tracks watched projects and resets touch state" {
    var watcher = Watcher.init(std.testing.allocator, null);
    defer watcher.deinit();

    try watcher.watch("demo", "/tmp/demo");
    try std.testing.expectEqual(@as(usize, 1), watcher.watchCount());
    watcher.touch("demo");
    watcher.unwatch("demo");
    try std.testing.expectEqual(@as(usize, 0), watcher.watchCount());
}

test "watcher baseline stays quiet on a clean git repo" {
    const allocator = std.testing.allocator;
    const repo = try makeGitRepo(allocator, "cbm-watcher-clean");
    defer cleanupRepo(allocator, repo);

    var watcher = Watcher.init(allocator, testIndexFn);
    defer watcher.deinit();
    test_watch_hits.store(0, .release);

    try watcher.watch("demo", repo);
    try std.testing.expectEqual(@as(u32, 0), try watcher.pollOnce());
    watcher.touch("demo");
    try std.testing.expectEqual(@as(u32, 0), try watcher.pollOnce());
    try std.testing.expectEqual(@as(u32, 0), test_watch_hits.load(.acquire));
}

test "watcher reindexes when the working tree changes" {
    const allocator = std.testing.allocator;
    const repo = try makeGitRepo(allocator, "cbm-watcher-dirty");
    defer cleanupRepo(allocator, repo);

    var watcher = Watcher.init(allocator, testIndexFn);
    defer watcher.deinit();
    test_watch_hits.store(0, .release);

    try watcher.watch("demo", repo);
    _ = try watcher.pollOnce();

    const file_path = try std.fs.path.join(allocator, &.{ repo, "main.py" });
    defer allocator.free(file_path);
    var file = try std.fs.cwd().createFile(file_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(
        \\def main():
        \\    return 2
        \\
    );

    watcher.touch("demo");
    try std.testing.expectEqual(@as(u32, 1), try watcher.pollOnce());
    try std.testing.expectEqual(@as(u32, 1), test_watch_hits.load(.acquire));
}

fn makeGitRepo(allocator: std.mem.Allocator, prefix: []const u8) ![]u8 {
    const repo_id = std.crypto.random.int(u64);
    const repo = try std.fmt.allocPrint(allocator, "/tmp/{s}-{x}", .{ prefix, repo_id });
    try std.fs.cwd().makePath(repo);

    const file_path = try std.fs.path.join(allocator, &.{ repo, "main.py" });
    defer allocator.free(file_path);
    var file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();
    try file.writeAll(
        \\def main():
        \\    return 1
        \\
    );

    try runTestCommand(allocator, &.{ "git", "-C", repo, "init", "-b", "main" });
    try runTestCommand(allocator, &.{ "git", "-C", repo, "config", "user.email", "tests@example.com" });
    try runTestCommand(allocator, &.{ "git", "-C", repo, "config", "user.name", "Watcher Tests" });
    try runTestCommand(allocator, &.{ "git", "-C", repo, "add", "." });
    try runTestCommand(allocator, &.{ "git", "-C", repo, "commit", "-m", "initial" });
    return repo;
}

fn cleanupRepo(allocator: std.mem.Allocator, repo: []const u8) void {
    std.fs.cwd().deleteTree(repo) catch {};
    allocator.free(repo);
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
            if (code != 0) return error.TestCommandFailed;
        },
        else => return error.TestCommandFailed,
    }
}

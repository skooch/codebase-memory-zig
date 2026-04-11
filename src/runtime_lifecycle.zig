const builtin = @import("builtin");
const std = @import("std");

const c = if (builtin.os.tag == .windows) struct {} else @cImport({
    @cInclude("signal.h");
    @cInclude("unistd.h");
});

const update_check_url = "https://api.github.com/repos/DeusData/codebase-memory-mcp/releases/latest";
var shutdown_requested = std.atomic.Value(bool).init(false);

pub const RuntimeLifecycle = struct {
    allocator: std.mem.Allocator,
    current_version: []const u8,
    mutex: std.Thread.Mutex = .{},
    update_notice: ?[]u8 = null,
    update_check_started: bool = false,
    update_thread: ?std.Thread = null,

    pub fn init(allocator: std.mem.Allocator, current_version: []const u8) RuntimeLifecycle {
        return .{
            .allocator = allocator,
            .current_version = current_version,
        };
    }

    pub fn deinit(self: *RuntimeLifecycle) void {
        if (self.update_thread) |thread| {
            thread.join();
            self.update_thread = null;
        }
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.update_notice) |notice| {
            self.allocator.free(notice);
            self.update_notice = null;
        }
    }

    pub fn startUpdateCheck(self: *RuntimeLifecycle) void {
        self.mutex.lock();
        if (self.update_check_started) {
            self.mutex.unlock();
            return;
        }
        self.update_check_started = true;
        self.mutex.unlock();

        if (envFlagEnabled("CBM_UPDATE_CHECK_DISABLE")) return;

        if (std.posix.getenv("CBM_UPDATE_CHECK_LATEST")) |latest| {
            self.storeNoticeIfNewer(latest) catch {};
            return;
        }

        self.update_thread = std.Thread.spawn(.{}, updateCheckThreadMain, .{self}) catch null;
    }

    pub fn injectUpdateNotice(self: *RuntimeLifecycle, response_json: []const u8) ![]const u8 {
        const notice = self.takeNotice() orelse return response_json;
        defer self.allocator.free(notice);

        const marker = ",\"result\":{";
        const marker_index = std.mem.indexOf(u8, response_json, marker) orelse {
            return response_json;
        };
        const object_start = marker_index + marker.len;

        const notice_json = try std.json.Stringify.valueAlloc(self.allocator, notice, .{});
        defer self.allocator.free(notice_json);

        var out = std.ArrayList(u8).empty;
        errdefer out.deinit(self.allocator);
        try out.appendSlice(self.allocator, response_json[0..object_start]);
        try out.appendSlice(self.allocator, "\"update_notice\":");
        try out.appendSlice(self.allocator, notice_json);
        if (object_start < response_json.len and response_json[object_start] != '}') {
            try out.append(self.allocator, ',');
        }
        try out.appendSlice(self.allocator, response_json[object_start..]);
        self.allocator.free(response_json);
        return out.toOwnedSlice(self.allocator);
    }

    fn takeNotice(self: *RuntimeLifecycle) ?[]u8 {
        self.mutex.lock();
        defer self.mutex.unlock();
        const notice = self.update_notice orelse return null;
        self.update_notice = null;
        return notice;
    }

    fn storeNoticeIfNewer(self: *RuntimeLifecycle, latest_raw: []const u8) !void {
        const latest = std.mem.trim(u8, latest_raw, " \t\r\n");
        if (latest.len == 0) return;
        const current = std.posix.getenv("CBM_UPDATE_CHECK_CURRENT") orelse self.current_version;
        if (compareVersions(latest, current) <= 0) return;

        const notice = try std.fmt.allocPrint(
            self.allocator,
            "Update available: {s} -> {s} -- run: cbm update",
            .{ current, latest },
        );
        errdefer self.allocator.free(notice);

        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.update_notice) |existing| {
            self.allocator.free(existing);
        }
        self.update_notice = notice;
    }
};

pub fn installSignalHandlers() void {
    shutdown_requested.store(false, .release);
    if (builtin.os.tag == .windows) return;

    _ = c.signal(c.SIGINT, signalHandler);
    _ = c.signal(c.SIGTERM, signalHandler);
}

pub fn shutdownRequested() bool {
    return shutdown_requested.load(.acquire);
}

fn signalHandler(sig: c_int) callconv(.c) void {
    _ = sig;
    shutdown_requested.store(true, .release);
    _ = c.close(0);
}

fn updateCheckThreadMain(runtime: *RuntimeLifecycle) void {
    runUpdateCheck(runtime) catch {};
}

fn runCurl(allocator: std.mem.Allocator, url: []const u8) ![]u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{
            "curl",
            "-sf",
            "--max-time",
            "5",
            "-H",
            "Accept: application/vnd.github+json",
            url,
        },
        .max_output_bytes = 64 * 1024,
    });
    defer allocator.free(result.stderr);
    defer allocator.free(result.stdout);
    switch (result.term) {
        .Exited => |code| if (code == 0 and result.stdout.len > 0) return allocator.dupe(u8, result.stdout),
        else => {},
    }
    return error.UpdateCheckFailed;
}

fn parseLatestTag(allocator: std.mem.Allocator, body: []const u8) !?[]u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch return null;
    defer parsed.deinit();

    if (parsed.value != .object) return null;
    const tag_value = parsed.value.object.get("tag_name") orelse return null;
    if (tag_value != .string) return null;
    return try allocator.dupe(u8, tag_value.string);
}

fn normalizeVersionPart(part: []const u8) []const u8 {
    return std.mem.trimLeft(u8, part, "vV");
}

fn compareVersions(lhs_raw: []const u8, rhs_raw: []const u8) i8 {
    var lhs_parts = std.mem.splitScalar(u8, normalizeVersionPart(lhs_raw), '.');
    var rhs_parts = std.mem.splitScalar(u8, normalizeVersionPart(rhs_raw), '.');

    var idx: usize = 0;
    while (idx < 4) : (idx += 1) {
        const lhs_part = lhs_parts.next() orelse "0";
        const rhs_part = rhs_parts.next() orelse "0";
        const lhs_value = std.fmt.parseUnsigned(u32, trimNumericPrefix(lhs_part), 10) catch 0;
        const rhs_value = std.fmt.parseUnsigned(u32, trimNumericPrefix(rhs_part), 10) catch 0;
        if (lhs_value > rhs_value) return 1;
        if (lhs_value < rhs_value) return -1;
    }
    return 0;
}

fn trimNumericPrefix(part: []const u8) []const u8 {
    var end: usize = 0;
    while (end < part.len and std.ascii.isDigit(part[end])) : (end += 1) {}
    if (end == 0) return "0";
    return part[0..end];
}

fn envFlagEnabled(name: []const u8) bool {
    const value = std.posix.getenv(name) orelse return false;
    return std.ascii.eqlIgnoreCase(value, "1") or
        std.ascii.eqlIgnoreCase(value, "true") or
        std.ascii.eqlIgnoreCase(value, "yes") or
        std.ascii.eqlIgnoreCase(value, "on");
}

fn runUpdateCheck(self: *RuntimeLifecycle) !void {
    const url = std.posix.getenv("CBM_UPDATE_CHECK_URL") orelse update_check_url;
    const body = runCurl(self.allocator, url) catch return;
    defer self.allocator.free(body);
    const latest = try parseLatestTag(self.allocator, body) orelse return;
    defer self.allocator.free(latest);
    try self.storeNoticeIfNewer(latest);
}

test "compareVersions handles shared semver-style tags" {
    try std.testing.expect(compareVersions("v1.2.3", "1.2.2") > 0);
    try std.testing.expect(compareVersions("1.2.3", "v1.2.3") == 0);
    try std.testing.expect(compareVersions("1.2.3", "1.3.0") < 0);
    try std.testing.expect(compareVersions("dev", "1.0.0") < 0);
}

test "injectUpdateNotice prepends one-shot result metadata" {
    var runtime = RuntimeLifecycle.init(std.testing.allocator, "0.0.0");
    defer runtime.deinit();

    try runtime.storeNoticeIfNewer("9.9.9");
    const response = try std.testing.allocator.dupe(u8, "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"project\":\"demo\"}}");
    const injected = try runtime.injectUpdateNotice(response);
    defer std.testing.allocator.free(injected);

    try std.testing.expect(std.mem.indexOf(u8, injected, "\"update_notice\":\"Update available:") != null);

    const second = try std.testing.allocator.dupe(u8, injected);
    const unchanged = try runtime.injectUpdateNotice(second);
    defer std.testing.allocator.free(unchanged);
    try std.testing.expectEqualStrings(injected, unchanged);
}

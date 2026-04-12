const std = @import("std");

pub const Status = enum { idle, running, done };

pub const Config = struct {
    mode: []const u8,
    retries: u8 = 3,

    pub fn isVerbose(self: Config) bool {
        return std.mem.eql(u8, self.mode, "verbose");
    }
};

pub fn createConfig(mode: []const u8) Config {
    return Config{ .mode = mode };
}

pub fn boot() !void {
    const cfg = createConfig("batch");
    if (cfg.isVerbose()) {
        std.debug.print("verbose mode\n", .{});
    }
}

test "config defaults" {
    const cfg = Config{ .mode = "test" };
    try std.testing.expectEqual(@as(u8, 3), cfg.retries);
}

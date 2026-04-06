// minhash.zig — MinHash fingerprinting + LSH for near-clone detection.
//
// Computes K=64 MinHash signatures from AST node-type trigrams.
// Uses xxHash with distinct seeds. Pure functions, thread-safe.

const std = @import("std");

pub const k: usize = 64;

// Minimum leaf AST tokens required to compute a fingerprint.
// 30 leaf tokens ~ 50 raw source tokens (BigCloneBench standard).
pub const min_nodes: usize = 30;

// Default Jaccard threshold for SIMILAR_TO edge emission.
pub const jaccard_threshold: f64 = 0.95;

pub const Fingerprint = struct {
    values: [k]u32 = [_]u32{std.math.maxInt(u32)} ** k,
};

pub fn jaccard(a: *const Fingerprint, b: *const Fingerprint) f64 {
    var agree: u32 = 0;
    for (0..k) |i| {
        if (a.values[i] == b.values[i]) agree += 1;
    }
    return @as(f64, @floatFromInt(agree)) / @as(f64, @floatFromInt(k));
}

pub fn toHex(fp: *const Fingerprint, buf: *[k * 8]u8) void {
    for (fp.values, 0..) |val, i| {
        _ = std.fmt.bufPrint(buf[i * 8 .. i * 8 + 8], "{x:0>8}", .{val}) catch unreachable;
    }
}

test "jaccard identical" {
    var a = Fingerprint{};
    a.values[0] = 42;
    a.values[1] = 99;
    const j = jaccard(&a, &a);
    try std.testing.expectEqual(@as(f64, 1.0), j);
}

test "jaccard different" {
    var a = Fingerprint{};
    var b = Fingerprint{};
    // Make all values different.
    for (0..k) |i| {
        a.values[i] = @intCast(i);
        b.values[i] = @intCast(i + k);
    }
    const j = jaccard(&a, &b);
    try std.testing.expectEqual(@as(f64, 0.0), j);
}

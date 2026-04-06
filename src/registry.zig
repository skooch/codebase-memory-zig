// registry.zig — Function name resolution registry.
//
// Symbol table mapping short names to qualified names. Used during call
// resolution to match callee names to their definitions.
//
// Strategies (in priority order):
//   1. Import map: local alias -> resolved QN
//   2. Same module
//   3. Same package
//   4. Import-reachable module prefix
//   5. Fuzzy by bare name (low confidence)

const std = @import("std");

pub const Resolution = struct {
    qualified_name: []const u8,
    strategy: []const u8,
    confidence: f64,
    candidate_count: u32,
};

pub const Registry = struct {
    allocator: std.mem.Allocator,
    // name -> list of qualified names
    by_name: std.StringHashMap(std.ArrayList([]const u8)),
    // qn -> label
    labels: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{
            .allocator = allocator,
            .by_name = std.StringHashMap(std.ArrayList([]const u8)).init(allocator),
            .labels = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Registry) void {
        var it = self.by_name.valueIterator();
        while (it.next()) |list| {
            list.deinit(self.allocator);
        }
        self.by_name.deinit();
        self.labels.deinit();
    }

    pub fn add(self: *Registry, name: []const u8, qualified_name: []const u8, label: []const u8) !void {
        const entry = try self.by_name.getOrPut(name);
        if (!entry.found_existing) {
            entry.value_ptr.* = .empty;
        }
        try entry.value_ptr.append(self.allocator, qualified_name);
        try self.labels.put(qualified_name, label);
    }

    pub fn exists(self: *const Registry, qn: []const u8) bool {
        return self.labels.contains(qn);
    }

    pub fn size(self: *const Registry) usize {
        return self.labels.count();
    }

    pub fn resolve(
        self: *const Registry,
        callee_name: []const u8,
        module_qn: []const u8,
    ) ?Resolution {
        _ = module_qn;
        const candidates = self.by_name.get(callee_name) orelse return null;
        if (candidates.items.len == 0) return null;

        // TODO: implement full resolution strategy chain
        return .{
            .qualified_name = candidates.items[0],
            .strategy = "first_match",
            .confidence = 0.5,
            .candidate_count = @intCast(candidates.items.len),
        };
    }
};

test "registry add and resolve" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    try reg.add("foo", "pkg.mod.foo", "Function");
    try std.testing.expect(reg.exists("pkg.mod.foo"));
    try std.testing.expectEqual(@as(usize, 1), reg.size());

    const res = reg.resolve("foo", "pkg.mod");
    try std.testing.expect(res != null);
    try std.testing.expectEqualStrings("pkg.mod.foo", res.?.qualified_name);
}

// registry — Function name resolution registry.
//
// Symbol table for best-effort symbol lookup during call and semantic passes.

const std = @import("std");

const SymbolRecord = struct {
    qualified_name: []const u8,
    label: []const u8,
    file_path: []const u8,
};

const ImportBinding = struct {
    alias: []const u8,
    namespace_hint: []const u8,
};

pub const Resolution = struct {
    qualified_name: []const u8,
    strategy: []const u8,
    confidence: f64,
    candidate_count: u32,
};

pub const Registry = struct {
    allocator: std.mem.Allocator,
    by_name: std.StringHashMap(std.ArrayList(SymbolRecord)),
    labels: std.StringHashMap([]const u8),
    import_bindings: std.AutoHashMap(i64, std.ArrayList(ImportBinding)),

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{
            .allocator = allocator,
            .by_name = std.StringHashMap(std.ArrayList(SymbolRecord)).init(allocator),
            .labels = std.StringHashMap([]const u8).init(allocator),
            .import_bindings = std.AutoHashMap(i64, std.ArrayList(ImportBinding)).init(allocator),
        };
    }

    pub fn deinit(self: *Registry) void {
        var label_it = self.labels.iterator();
        while (label_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        var it = self.by_name.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            const list = entry.value_ptr;
            for (list.items) |item| {
                self.allocator.free(item.qualified_name);
                self.allocator.free(item.label);
                self.allocator.free(item.file_path);
            }
            list.deinit(self.allocator);
        }

        var import_it = self.import_bindings.valueIterator();
        while (import_it.next()) |bindings| {
            for (bindings.items) |binding| {
                self.allocator.free(binding.alias);
                self.allocator.free(binding.namespace_hint);
            }
            bindings.deinit(self.allocator);
        }

        self.by_name.deinit();
        self.labels.deinit();
        self.import_bindings.deinit();
    }

    pub fn add(
        self: *Registry,
        name: []const u8,
        qualified_name: []const u8,
        label: []const u8,
        file_path: []const u8,
    ) !void {
        const owned_name = try self.allocator.dupe(u8, name);
        const entry = try self.by_name.getOrPut(owned_name);
        if (entry.found_existing) {
            self.allocator.free(owned_name);
        } else {
            entry.value_ptr.* = .empty;
        }
        try entry.value_ptr.append(self.allocator, .{
            .qualified_name = try self.allocator.dupe(u8, qualified_name),
            .label = try self.allocator.dupe(u8, label),
            .file_path = try self.allocator.dupe(u8, file_path),
        });

        const owned_qn = try self.allocator.dupe(u8, qualified_name);
        const label_entry = try self.labels.getOrPut(owned_qn);
        if (label_entry.found_existing) {
            self.allocator.free(owned_qn);
        }
        if (!label_entry.found_existing) {
            label_entry.value_ptr.* = try self.allocator.dupe(u8, label);
        }
    }

    pub fn addImportBinding(
        self: *Registry,
        importer_id: i64,
        alias: []const u8,
        namespace_hint: []const u8,
    ) !void {
        const entry = try self.import_bindings.getOrPut(importer_id);
        if (!entry.found_existing) {
            entry.value_ptr.* = .empty;
        }
        try entry.value_ptr.append(self.allocator, .{
            .alias = try self.allocator.dupe(u8, alias),
            .namespace_hint = try self.allocator.dupe(u8, namespace_hint),
        });
    }

    pub fn exists(self: *const Registry, qn: []const u8) bool {
        return self.labels.contains(qn);
    }

    pub fn size(self: *const Registry) usize {
        return self.labels.count();
    }

    pub fn getCandidates(self: *const Registry, callee_name: []const u8) ?[]const SymbolRecord {
        const candidates = self.by_name.get(callee_name) orelse return null;
        return candidates.items;
    }

    fn lastPathPart(raw: []const u8) []const u8 {
        const trimmed = std.mem.trim(u8, raw, " \t\"'");
        if (trimmed.len == 0) return "";
        if (std.mem.lastIndexOfAny(u8, trimmed, "/\\")) |idx| {
            return trimmed[idx + 1 ..];
        }
        return trimmed;
    }

    fn bestByFile(
        self: *const Registry,
        candidates: []const SymbolRecord,
        file_hint: []const u8,
    ) ?SymbolRecord {
        _ = self;
        if (file_hint.len == 0 or candidates.len == 0) return null;
        for (candidates) |cand| {
            if (std.mem.eql(u8, cand.file_path, file_hint)) {
                return cand;
            }
        }
        return null;
    }

    fn bestByNamespace(
        self: *const Registry,
        candidates: []const SymbolRecord,
        namespace_hint: []const u8,
    ) ?SymbolRecord {
        _ = self;
        if (namespace_hint.len == 0 or candidates.len == 0) return null;
        for (candidates) |cand| {
            if (std.mem.containsAtLeast(u8, cand.qualified_name, 1, namespace_hint)) {
                return cand;
            }
        }
        return null;
    }

    pub fn resolve(
        self: *const Registry,
        callee_name: []const u8,
        importer_id: i64,
        file_hint: []const u8,
        preferred_label: ?[]const u8,
    ) ?Resolution {
        const alias = lastPathPart(callee_name);
        const effective_name = if (alias.len > 0) alias else callee_name;

        if (self.import_bindings.get(importer_id)) |bindings| {
            for (bindings.items) |binding| {
                if (std.mem.eql(u8, binding.alias, effective_name) or
                    std.mem.eql(u8, binding.alias, callee_name))
                {
                    const candidates = self.by_name.get(effective_name) orelse
                        self.by_name.get(callee_name) orelse
                        return null;
                    if (self.bestByNamespace(candidates.items, binding.namespace_hint)) |best| {
                        return .{
                            .qualified_name = best.qualified_name,
                            .strategy = "import_namespace",
                            .confidence = 0.95,
                            .candidate_count = @intCast(candidates.items.len),
                        };
                    }
                }
            }
        }

        const candidates = self.by_name.get(effective_name) orelse
            self.by_name.get(callee_name) orelse
            return null;
        if (preferred_label) |label| {
            for (candidates.items) |cand| {
                if (std.mem.eql(u8, cand.label, label)) {
                    return .{
                        .qualified_name = cand.qualified_name,
                        .strategy = "preferred_label",
                        .confidence = 0.9,
                        .candidate_count = @intCast(candidates.items.len),
                    };
                }
            }
        }
        if (self.bestByFile(candidates.items, file_hint)) |best_file| {
            return .{
                .qualified_name = best_file.qualified_name,
                .strategy = "same_file",
                .confidence = 0.88,
                .candidate_count = @intCast(candidates.items.len),
            };
        }
        return .{
            .qualified_name = candidates.items[0].qualified_name,
            .strategy = "first_match",
            .confidence = 0.5,
            .candidate_count = @intCast(candidates.items.len),
        };
    }
};

test "registry add and resolve" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    try reg.add("foo", "pkg.mod.foo", "Function", "src/main.rs");
    try std.testing.expect(reg.exists("pkg.mod.foo"));
    try std.testing.expectEqual(@as(usize, 1), reg.size());

    const res = reg.resolve("foo", 0, "", null);
    try std.testing.expect(res != null);
    try std.testing.expectEqualStrings("pkg.mod.foo", res.?.qualified_name);
}

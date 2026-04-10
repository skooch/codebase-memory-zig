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
    import_bindings_by_file: std.StringHashMap(std.ArrayList(ImportBinding)),

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{
            .allocator = allocator,
            .by_name = std.StringHashMap(std.ArrayList(SymbolRecord)).init(allocator),
            .labels = std.StringHashMap([]const u8).init(allocator),
            .import_bindings = std.AutoHashMap(i64, std.ArrayList(ImportBinding)).init(allocator),
            .import_bindings_by_file = std.StringHashMap(std.ArrayList(ImportBinding)).init(allocator),
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

        var file_binding_it = self.import_bindings_by_file.iterator();
        while (file_binding_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.items) |binding| {
                self.allocator.free(binding.alias);
                self.allocator.free(binding.namespace_hint);
            }
            entry.value_ptr.deinit(self.allocator);
        }

        self.by_name.deinit();
        self.labels.deinit();
        self.import_bindings.deinit();
        self.import_bindings_by_file.deinit();
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
        file_path: []const u8,
    ) !void {
        const entry = try self.import_bindings.getOrPut(importer_id);
        if (!entry.found_existing) {
            entry.value_ptr.* = .empty;
        }
        try entry.value_ptr.append(self.allocator, .{
            .alias = try self.allocator.dupe(u8, alias),
            .namespace_hint = try self.allocator.dupe(u8, namespace_hint),
        });

        const owned_path = try self.allocator.dupe(u8, file_path);
        const file_entry = try self.import_bindings_by_file.getOrPut(owned_path);
        if (file_entry.found_existing) {
            self.allocator.free(owned_path);
        } else {
            file_entry.value_ptr.* = .empty;
        }
        try file_entry.value_ptr.append(self.allocator, .{
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
        return lastNamespaceSegment(trimmed);
    }

    fn secondLastPathPart(raw: []const u8) []const u8 {
        const trimmed = std.mem.trim(u8, raw, " \t\"'");
        if (trimmed.len == 0) return "";
        return secondLastNamespaceSegment(trimmed);
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
        const module_hint = secondLastPathPart(namespace_hint);
        for (candidates) |cand| {
            if (std.mem.containsAtLeast(u8, cand.qualified_name, 1, namespace_hint)) {
                return cand;
            }
            if (module_hint.len > 0 and std.mem.containsAtLeast(u8, cand.file_path, 1, module_hint)) {
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
        if (self.labels.contains(callee_name)) {
            return .{
                .qualified_name = callee_name,
                .strategy = "exact_qualified_name",
                .confidence = 1.0,
                .candidate_count = 1,
            };
        }

        const alias = lastPathPart(callee_name);
        const effective_name = if (alias.len > 0) alias else callee_name;

        if (self.resolveFromBindings(self.import_bindings.get(importer_id), effective_name, callee_name)) |resolution| {
            return resolution;
        }
        if (self.resolveFromBindings(self.import_bindings_by_file.get(file_hint), effective_name, callee_name)) |resolution| {
            return resolution;
        }

        const candidates = self.by_name.get(effective_name) orelse
            self.by_name.get(callee_name) orelse
            return null;
        if (!std.mem.eql(u8, effective_name, callee_name)) {
            if (self.bestByNamespace(candidates.items, callee_name)) |best_suffix| {
                return .{
                    .qualified_name = best_suffix.qualified_name,
                    .strategy = "qualified_suffix",
                    .confidence = 0.92,
                    .candidate_count = @intCast(candidates.items.len),
                };
            }
        }
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

    fn resolveFromBindings(
        self: *const Registry,
        bindings_opt: ?std.ArrayList(ImportBinding),
        effective_name: []const u8,
        callee_name: []const u8,
    ) ?Resolution {
        const bindings = bindings_opt orelse return null;
        for (bindings.items) |binding| {
            if (std.mem.eql(u8, binding.alias, effective_name) or
                std.mem.eql(u8, binding.alias, callee_name))
            {
                const imported_name = lastPathPart(binding.namespace_hint);
                const candidates = self.by_name.get(imported_name) orelse
                    self.by_name.get(effective_name) orelse
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
                if (candidates.items.len == 1) {
                    return .{
                        .qualified_name = candidates.items[0].qualified_name,
                        .strategy = "import_alias",
                        .confidence = 0.82,
                        .candidate_count = 1,
                    };
                }
            }
        }
        return null;
    }
};

fn lastNamespaceSegment(text: []const u8) []const u8 {
    const bounds = namespaceSegmentBounds(text);
    if (bounds.current_start == bounds.current_end) return "";
    return text[bounds.current_start..bounds.current_end];
}

fn secondLastNamespaceSegment(text: []const u8) []const u8 {
    const bounds = namespaceSegmentBounds(text);
    if (bounds.previous_start == bounds.previous_end) return "";
    return text[bounds.previous_start..bounds.previous_end];
}

const NamespaceSegmentBounds = struct {
    previous_start: usize = 0,
    previous_end: usize = 0,
    current_start: usize = 0,
    current_end: usize = 0,
};

fn namespaceSegmentBounds(text: []const u8) NamespaceSegmentBounds {
    var bounds = NamespaceSegmentBounds{};
    var segment_start: usize = 0;
    var i: usize = 0;

    while (i <= text.len) {
        if (i == text.len or isNamespaceBoundary(text, i)) {
            if (segment_start < i) {
                bounds.previous_start = bounds.current_start;
                bounds.previous_end = bounds.current_end;
                bounds.current_start = segment_start;
                bounds.current_end = i;
            }
            if (i == text.len) break;
            i = namespaceBoundaryEnd(text, i);
            segment_start = i;
            continue;
        }
        i += 1;
    }

    return bounds;
}

fn isNamespaceBoundary(text: []const u8, idx: usize) bool {
    return text[idx] == '/' or
        text[idx] == '\\' or
        text[idx] == '.' or
        text[idx] == ':';
}

fn namespaceBoundaryEnd(text: []const u8, idx: usize) usize {
    if (text[idx] == ':' and idx + 1 < text.len and text[idx + 1] == ':') {
        return idx + 2;
    }
    return idx + 1;
}

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

test "registry resolves namespaced imports and suffixes" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    try reg.add("helper", "demo:src/util.rs:rust:symbol:rust:helper", "Function", "src/util.rs");
    try reg.add("helper", "demo:src/other.rs:rust:symbol:rust:helper", "Function", "src/other.rs");
    try reg.addImportBinding(10, "helper", "crate::util::helper", "src/main.rs");

    const imported = reg.resolve("helper", 10, "src/main.rs", null);
    try std.testing.expect(imported != null);
    try std.testing.expectEqualStrings("demo:src/util.rs:rust:symbol:rust:helper", imported.?.qualified_name);
    try std.testing.expectEqualStrings("import_namespace", imported.?.strategy);

    try reg.add("run", "demo:src/main.py:python:symbol:python:run", "Function", "src/main.py");
    try reg.add("run", "demo:src/worker.py:python:symbol:python:run", "Function", "src/worker.py");

    const suffix = reg.resolve("main.run", 0, "", null);
    try std.testing.expect(suffix != null);
    try std.testing.expectEqualStrings("demo:src/main.py:python:symbol:python:run", suffix.?.qualified_name);
    try std.testing.expectEqualStrings("qualified_suffix", suffix.?.strategy);
}

const std = @import("std");
const graph_buffer = @import("graph_buffer.zig");

pub const Stats = struct {
    tests_edges: usize = 0,
    tests_file_edges: usize = 0,
};

pub fn isTestPath(path: []const u8) bool {
    if (path.len == 0) return false;
    const base = std.fs.path.basename(path);

    if (std.mem.startsWith(u8, base, "test_")) return true;
    if (std.mem.endsWith(u8, path, "_test.go")) return true;
    if (std.mem.endsWith(u8, path, "_test.py")) return true;
    if (std.mem.endsWith(u8, path, "_test.rs")) return true;
    if (std.mem.endsWith(u8, path, "_test.cpp")) return true;
    if (std.mem.endsWith(u8, path, "_test.lua")) return true;
    if (std.mem.endsWith(u8, path, "_spec.rb")) return true;

    if (std.mem.indexOf(u8, path, ".test.ts") != null) return true;
    if (std.mem.indexOf(u8, path, ".spec.ts") != null) return true;
    if (std.mem.indexOf(u8, path, ".test.js") != null) return true;
    if (std.mem.indexOf(u8, path, ".spec.js") != null) return true;
    if (std.mem.indexOf(u8, path, ".test.tsx") != null) return true;
    if (std.mem.indexOf(u8, path, ".spec.tsx") != null) return true;

    if (std.mem.endsWith(u8, path, "Test.java")) return true;
    if (std.mem.endsWith(u8, path, "Test.kt")) return true;
    if (std.mem.endsWith(u8, path, "Test.cs")) return true;
    if (std.mem.endsWith(u8, path, "Test.php")) return true;
    if (std.mem.endsWith(u8, path, "Spec.scala")) return true;

    if (std.mem.indexOf(u8, path, "__tests__/") != null) return true;
    if (std.mem.indexOf(u8, path, "/tests/") != null) return true;
    if (std.mem.indexOf(u8, path, "/test/") != null) return true;
    if (std.mem.indexOf(u8, path, "/spec/") != null) return true;

    if (std.mem.startsWith(u8, path, "tests/")) return true;
    if (std.mem.startsWith(u8, path, "test/")) return true;
    if (std.mem.startsWith(u8, path, "spec/")) return true;
    if (std.mem.startsWith(u8, path, "__tests__/")) return true;

    return false;
}

pub fn isTestFunctionName(name: []const u8) bool {
    if (name.len == 0) return false;

    if (std.mem.startsWith(u8, name, "Test")) {
        if (name.len == "Test".len) return true;
        if (std.ascii.isUpper(name["Test".len])) return true;
    }
    if (std.mem.startsWith(u8, name, "Benchmark")) {
        if (name.len == "Benchmark".len) return true;
        if (std.ascii.isUpper(name["Benchmark".len])) return true;
    }
    if (std.mem.startsWith(u8, name, "Example")) {
        if (name.len == "Example".len) return true;
        if (std.ascii.isUpper(name["Example".len])) return true;
    }

    if (std.mem.startsWith(u8, name, "test_")) return true;
    if (std.mem.startsWith(u8, name, "test") and name.len > "test".len and std.ascii.isUpper(name["test".len])) {
        return true;
    }

    return std.mem.eql(u8, name, "test") or
        std.mem.eql(u8, name, "it") or
        std.mem.eql(u8, name, "describe") or
        std.mem.eql(u8, name, "beforeAll") or
        std.mem.eql(u8, name, "afterAll") or
        std.mem.eql(u8, name, "beforeEach") or
        std.mem.eql(u8, name, "afterEach") or
        std.mem.eql(u8, name, "@testset") or
        std.mem.eql(u8, name, "@test");
}

pub fn symbolPropertiesJson(label: []const u8, name: []const u8, file_path: []const u8) []const u8 {
    if (std.mem.eql(u8, label, "Test")) return "{\"is_test\":true}";
    if (isTestPath(file_path)) return "{\"is_test\":true}";
    if (isTestFunctionName(name)) return "{\"is_test\":true}";
    return "{}";
}

pub fn runPass(allocator: std.mem.Allocator, gb: *graph_buffer.GraphBuffer) !Stats {
    var stats = Stats{};

    try ensureTestMetadata(allocator, gb);

    for (gb.edgeItems()) |edge| {
        if (!std.mem.eql(u8, edge.edge_type, "CALLS")) continue;

        const source = gb.findNodeById(edge.source_id) orelse continue;
        const target = gb.findNodeById(edge.target_id) orelse continue;

        const source_is_test = nodeIsTest(source) or isTestPath(source.file_path);
        if (!source_is_test) continue;
        if (!isTestFunctionName(source.name)) continue;

        const target_is_test = nodeIsTest(target) or isTestPath(target.file_path);
        if (target_is_test) continue;

        const inserted = insertDerivedEdge(gb, source.id, target.id, "TESTS") catch |err| switch (err) {
            error.OutOfMemory => return err,
        };
        if (inserted) stats.tests_edges += 1;
    }

    for (gb.nodes()) |node| {
        if (!std.mem.eql(u8, node.label, "File")) continue;
        if (!isTestPath(node.file_path)) continue;

        const prod_path = try testToProdPath(allocator, node.file_path);
        defer if (prod_path) |path| allocator.free(path);
        const resolved_path = prod_path orelse continue;
        const target = findFileNodeByPath(gb, resolved_path) orelse continue;
        if (target.id == node.id) continue;

        const inserted = insertDerivedEdge(gb, node.id, target.id, "TESTS_FILE") catch |err| switch (err) {
            error.OutOfMemory => return err,
        };
        if (inserted) stats.tests_file_edges += 1;
    }

    return stats;
}

fn ensureTestMetadata(allocator: std.mem.Allocator, gb: *graph_buffer.GraphBuffer) !void {
    for (gb.nodes_by_id.items) |*node| {
        if (!shouldMarkNodeAsTest(node)) continue;
        if (nodeIsTest(node)) continue;
        try setNodeIsTest(allocator, node);
    }
}

fn shouldMarkNodeAsTest(node: *const graph_buffer.BufferNode) bool {
    if (std.mem.eql(u8, node.label, "File")) return isTestPath(node.file_path);
    if (std.mem.eql(u8, node.label, "Function")) return isTestPath(node.file_path) or isTestFunctionName(node.name);
    if (std.mem.eql(u8, node.label, "Method")) return isTestPath(node.file_path) or isTestFunctionName(node.name);
    if (std.mem.eql(u8, node.label, "Test")) return true;
    return false;
}

fn setNodeIsTest(allocator: std.mem.Allocator, node: *graph_buffer.BufferNode) !void {
    const current = node.properties_json;
    const updated = if (std.mem.eql(u8, current, "{}"))
        try allocator.dupe(u8, "{\"is_test\":true}")
    else if (current.len > 0 and current[current.len - 1] == '}')
        try std.fmt.allocPrint(allocator, "{s},\"is_test\":true}}", .{current[0 .. current.len - 1]})
    else
        try allocator.dupe(u8, "{\"is_test\":true}");
    allocator.free(node.properties_json);
    node.properties_json = updated;
}

fn nodeIsTest(node: *const graph_buffer.BufferNode) bool {
    return std.mem.indexOf(u8, node.properties_json, "\"is_test\":true") != null;
}

fn insertDerivedEdge(
    gb: *graph_buffer.GraphBuffer,
    source_id: i64,
    target_id: i64,
    edge_type: []const u8,
) error{OutOfMemory}!bool {
    _ = gb.insertEdge(source_id, target_id, edge_type) catch |err| switch (err) {
        graph_buffer.GraphBufferError.DuplicateEdge => return false,
        graph_buffer.GraphBufferError.OutOfMemory => return error.OutOfMemory,
    };
    return true;
}

fn findFileNodeByPath(gb: *graph_buffer.GraphBuffer, file_path: []const u8) ?*const graph_buffer.BufferNode {
    for (gb.nodes()) |*node| {
        if (std.mem.eql(u8, node.label, "File") and std.mem.eql(u8, node.file_path, file_path)) {
            return node;
        }
    }
    return null;
}

pub fn testToProdPath(allocator: std.mem.Allocator, test_path: []const u8) !?[]u8 {
    if (test_path.len == 0) return null;
    const base = std.fs.path.basename(test_path);
    const dir_path = std.fs.path.dirname(test_path);

    if (std.mem.endsWith(u8, base, "_test.go")) {
        const path = try joinDerivedPath(allocator, dir_path, base[0 .. base.len - "_test.go".len], ".go");
        return path;
    }
    if (std.mem.startsWith(u8, base, "test_") and std.mem.endsWith(u8, base, ".py")) {
        const path = try joinDerivedPath(allocator, dir_path, base["test_".len .. base.len - ".py".len], ".py");
        return path;
    }
    if (std.mem.indexOf(u8, base, ".test.")) |idx| {
        const path = try joinDerivedPath(allocator, dir_path, base[0..idx], base[idx + ".test".len ..]);
        return path;
    }
    if (std.mem.indexOf(u8, base, ".spec.")) |idx| {
        const path = try joinDerivedPath(allocator, dir_path, base[0..idx], base[idx + ".spec".len ..]);
        return path;
    }
    return null;
}

fn joinDerivedPath(
    allocator: std.mem.Allocator,
    maybe_dir: ?[]const u8,
    stem: []const u8,
    extension: []const u8,
) ![]u8 {
    const file_name = try std.mem.concat(allocator, u8, &.{ stem, extension });
    defer allocator.free(file_name);
    if (maybe_dir) |dir_path| {
        if (dir_path.len > 0) {
            return std.fs.path.join(allocator, &.{ dir_path, file_name });
        }
    }
    return allocator.dupe(u8, file_name);
}

test "test-tagging helpers recognize shared file and function naming rules" {
    try std.testing.expect(isTestPath("tests/test_widget.py"));
    try std.testing.expect(isTestPath("pkg/widget_test.go"));
    try std.testing.expect(isTestPath("ui/widget.spec.ts"));
    try std.testing.expect(!isTestPath("src/widget.py"));

    try std.testing.expect(isTestFunctionName("test_widget_renders"));
    try std.testing.expect(isTestFunctionName("TestWidget"));
    try std.testing.expect(isTestFunctionName("beforeEach"));
    try std.testing.expect(!isTestFunctionName("render_widget"));
}

test "test-tagging derives production file paths from shared naming rules" {
    const allocator = std.testing.allocator;

    const py = (try testToProdPath(allocator, "python_tests/test_widget.py")).?;
    defer allocator.free(py);
    try std.testing.expectEqualStrings("python_tests/widget.py", py);

    const ts = (try testToProdPath(allocator, "ui/widget.test.ts")).?;
    defer allocator.free(ts);
    try std.testing.expectEqualStrings("ui/widget.ts", ts);

    try std.testing.expectEqual(@as(?[]u8, null), try testToProdPath(allocator, "src/widget.py"));
}

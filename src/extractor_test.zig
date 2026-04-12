// extractor_test.zig — End-to-end integration tests for extractFile.

const std = @import("std");
const extractor = @import("extractor.zig");
const discover = @import("discover.zig");
const graph_buffer = @import("graph_buffer.zig");

/// Write `content` into a file at `dir_path/file_name`, returning the
/// absolute path (caller must free).
fn writeTempFile(
    allocator: std.mem.Allocator,
    dir_path: []const u8,
    file_name: []const u8,
    content: []const u8,
) ![]const u8 {
    var dir = try std.fs.cwd().openDir(dir_path, .{});
    defer dir.close();
    var f = try dir.createFile(file_name, .{});
    defer f.close();
    try f.writeAll(content);
    return std.fs.path.join(allocator, &.{ dir_path, file_name });
}

fn containsSymbol(symbols: []const extractor.ExtractedSymbol, label: []const u8, name: []const u8) bool {
    for (symbols) |sym| {
        if (std.mem.eql(u8, sym.label, label) and std.mem.eql(u8, sym.name, name)) return true;
    }
    return false;
}

fn containsCall(calls: []const extractor.UnresolvedCall, callee_name: []const u8) bool {
    for (calls) |call| {
        if (std.mem.eql(u8, call.callee_name, callee_name)) return true;
    }
    return false;
}

test "extractFile produces nodes and edges for Python module" {
    const allocator = std.testing.allocator;

    const project_id = std.crypto.random.int(u64);
    const dir_path = try std.fmt.allocPrint(
        allocator,
        "/tmp/cbm-extractor-py-{x}",
        .{project_id},
    );
    defer allocator.free(dir_path);
    try std.fs.cwd().makePath(dir_path);
    defer std.fs.cwd().deleteTree(dir_path) catch {};

    const abs_path = try writeTempFile(allocator, dir_path, "app.py",
        \\class Handler:
        \\    pass
        \\
        \\def process(data):
        \\    return data
        \\
        \\def main():
        \\    return process(42)
        \\
    );
    defer allocator.free(abs_path);

    var gb = graph_buffer.GraphBuffer.init(allocator, "test-py");
    defer gb.deinit();

    const file_info = discover.FileInfo{
        .path = abs_path,
        .rel_path = "app.py",
        .language = .python,
        .size = 0,
    };

    const extraction = try extractor.extractFile(allocator, "test-py", file_info, &gb);
    defer extractor.freeFileExtraction(allocator, extraction);

    // Verify symbols discovered for Handler, process, and main.
    try std.testing.expect(containsSymbol(extraction.symbols, "Class", "Handler"));
    try std.testing.expect(containsSymbol(extraction.symbols, "Function", "process"));
    try std.testing.expect(containsSymbol(extraction.symbols, "Function", "main"));

    // The call from main to process should appear as an unresolved call.
    try std.testing.expect(containsCall(extraction.unresolved_calls, "process"));

    // GraphBuffer should contain nodes: at minimum File, Module, and the 3 symbols.
    try std.testing.expect(gb.nodes_by_id.items.len >= 5);
}

test "extractFile produces nodes for JavaScript file" {
    const allocator = std.testing.allocator;

    const project_id = std.crypto.random.int(u64);
    const dir_path = try std.fmt.allocPrint(
        allocator,
        "/tmp/cbm-extractor-js-{x}",
        .{project_id},
    );
    defer allocator.free(dir_path);
    try std.fs.cwd().makePath(dir_path);
    defer std.fs.cwd().deleteTree(dir_path) catch {};

    const abs_path = try writeTempFile(allocator, dir_path, "api.js",
        \\function fetchData(url) {
        \\    return fetch(url);
        \\}
        \\
        \\class ApiClient {
        \\    constructor() {}
        \\    getData() {
        \\        return fetchData("/api");
        \\    }
        \\}
        \\
    );
    defer allocator.free(abs_path);

    var gb = graph_buffer.GraphBuffer.init(allocator, "test-js");
    defer gb.deinit();

    const file_info = discover.FileInfo{
        .path = abs_path,
        .rel_path = "api.js",
        .language = .javascript,
        .size = 0,
    };

    const extraction = try extractor.extractFile(allocator, "test-js", file_info, &gb);
    defer extractor.freeFileExtraction(allocator, extraction);

    // Verify symbols for fetchData, ApiClient, and getData.
    try std.testing.expect(containsSymbol(extraction.symbols, "Function", "fetchData"));
    try std.testing.expect(containsSymbol(extraction.symbols, "Class", "ApiClient"));
    try std.testing.expect(containsSymbol(extraction.symbols, "Method", "getData"));

    // The call from getData to fetchData should appear as unresolved.
    try std.testing.expect(containsCall(extraction.unresolved_calls, "fetchData"));
}

test "extractFile handles empty file gracefully" {
    const allocator = std.testing.allocator;

    const project_id = std.crypto.random.int(u64);
    const dir_path = try std.fmt.allocPrint(
        allocator,
        "/tmp/cbm-extractor-empty-{x}",
        .{project_id},
    );
    defer allocator.free(dir_path);
    try std.fs.cwd().makePath(dir_path);
    defer std.fs.cwd().deleteTree(dir_path) catch {};

    const abs_path = try writeTempFile(allocator, dir_path, "empty.py", "");
    defer allocator.free(abs_path);

    var gb = graph_buffer.GraphBuffer.init(allocator, "test-empty");
    defer gb.deinit();

    const file_info = discover.FileInfo{
        .path = abs_path,
        .rel_path = "empty.py",
        .language = .python,
        .size = 0,
    };

    const extraction = try extractor.extractFile(allocator, "test-empty", file_info, &gb);
    defer extractor.freeFileExtraction(allocator, extraction);

    // Empty file should produce no symbols beyond the file/module nodes.
    try std.testing.expectEqual(@as(usize, 0), extraction.symbols.len);
    try std.testing.expectEqual(@as(usize, 0), extraction.unresolved_calls.len);

    // GraphBuffer should still have at least a File and Module node.
    try std.testing.expect(gb.nodes_by_id.items.len >= 2);
}

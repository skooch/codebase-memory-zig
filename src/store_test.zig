// store_test.zig — Integration tests for the SQLite store.

const std = @import("std");
const store = @import("store.zig");

test "open in-memory store" {
    var s = try store.Store.openMemory(std.testing.allocator);
    defer s.deinit();
    // If we get here, SQLite opened and schema was created successfully.
}

test "open and close multiple times" {
    {
        var s = try store.Store.openMemory(std.testing.allocator);
        defer s.deinit();
    }
    {
        var s = try store.Store.openMemory(std.testing.allocator);
        defer s.deinit();
    }
}

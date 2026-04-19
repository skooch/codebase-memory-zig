// route_nodes — Backward-compatible wrapper around the explicit routes module.

const std = @import("std");
const graph_buffer = @import("graph_buffer.zig");
const routes = @import("routes.zig");

pub fn runPass(
    allocator: std.mem.Allocator,
    gb: *graph_buffer.GraphBuffer,
) error{OutOfMemory}!usize {
    return routes.runPass(allocator, gb);
}

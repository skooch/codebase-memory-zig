// pipeline.zig — Indexing pipeline orchestrator.
//
// Orchestrates multi-pass indexing of a repository:
//   1. Discovery: walk filesystem, detect languages
//   2. Extraction: tree-sitter AST -> definition nodes
//   3. Resolution: call/usage/semantic edges via registry
//   4. Post-passes: git history, similarity, routes, tests

const std = @import("std");
const discover = @import("discover.zig");

pub const IndexMode = enum {
    full, // read everything, build from scratch
    fast, // skip non-essential files
};

pub const PassFn = *const fn (*PipelineContext) anyerror!void;

pub const PipelineContext = struct {
    project_name: []const u8,
    repo_path: []const u8,
    allocator: std.mem.Allocator,
    cancelled: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
};

pub const Pipeline = struct {
    allocator: std.mem.Allocator,
    repo_path: []const u8,
    mode: IndexMode,
    project_name: []const u8 = "",

    pub fn init(allocator: std.mem.Allocator, repo_path: []const u8, mode: IndexMode) Pipeline {
        return .{
            .allocator = allocator,
            .repo_path = repo_path,
            .mode = mode,
        };
    }

    pub fn deinit(self: *Pipeline) void {
        _ = self;
    }

    pub fn run(self: *Pipeline) !void {
        _ = self;
        // TODO: implement pipeline passes
    }

    pub fn cancel(self: *Pipeline) void {
        _ = self;
        // TODO: set atomic cancelled flag
    }
};

// pipeline.zig — Indexing pipeline orchestrator.
//
// Orchestrates multi-pass indexing of a repository:
//   1. Discovery: walk filesystem, detect languages
//   2. Extraction: tree-sitter AST -> definition nodes
//   3. Resolution: call/usage/semantic edges via registry
//   4. Post-passes: git history, similarity, routes, tests

const std = @import("std");
const discover = @import("discover.zig");
const GraphBuffer = @import("graph_buffer.zig").GraphBuffer;
const extractFile = @import("extractor.zig").extractFile;

pub const IndexMode = enum {
    full, // read everything, build from scratch
    fast, // skip non-essential files
};

pub const PipelineError = error{
    Cancelled,
    DiscoveryFailed,
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
    cancelled: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    pub fn init(allocator: std.mem.Allocator, repo_path: []const u8, mode: IndexMode) Pipeline {
        const base = std.fs.path.basename(repo_path);
        const project_name = if (base.len == 0) "project" else base;
        return .{
            .allocator = allocator,
            .repo_path = repo_path,
            .mode = mode,
            .project_name = project_name,
        };
    }

    pub fn deinit(self: *Pipeline) void {
        _ = self;
    }

    pub fn run(self: *Pipeline) PipelineError!void {
        if (self.cancelled.load(.acquire)) {
            return PipelineError.Cancelled;
        }

        const discovered_files = discover.discoverFiles(
            self.allocator,
            self.repo_path,
            .{ .mode = self.mode },
        ) catch |err| {
            std.log.warn("pipeline discovery failed for {s}: {}", .{ self.repo_path, err });
            return PipelineError.DiscoveryFailed;
        };
        defer self.freeDiscoveredFiles(discovered_files);

        if (self.cancelled.load(.acquire)) {
            return PipelineError.Cancelled;
        }

        if (discovered_files.len == 0) {
            std.log.info("pipeline discovered 0 indexable files in {s}", .{self.repo_path});
            return;
        }

        var gb = GraphBuffer.init(self.allocator, self.project_name);
        defer gb.deinit();

        for (discovered_files) |file| {
            extractFile(self.allocator, self.project_name, file, &gb) catch |err| {
                std.log.warn("extractor failed for {s}: {}", .{ file.rel_path, err });
            };
            if (self.cancelled.load(.acquire)) {
                return PipelineError.Cancelled;
            }
        }

        std.log.info(
            "pipeline discovered {} files for {s} ({s})",
            .{ discovered_files.len, self.repo_path, self.project_name },
        );
        std.log.info(
            "pipeline graph buffer: {} nodes, {} edges",
            .{ gb.nodeCount(), gb.edgeCount() },
        );

        // TODO: implement extraction and storage phases.
        // - pass_definitions
        // - pass_calls
        // - pass_usages
        // - pass_semantic
        // - pass_similarity
        // - pass_gitdiff
    }

    pub fn cancel(self: *Pipeline) void {
        self.cancelled.store(true, .release);
    }

    fn freeDiscoveredFiles(self: *Pipeline, discovered_files: []discover.FileInfo) void {
        for (discovered_files) |file| {
            self.allocator.free(file.path);
            self.allocator.free(file.rel_path);
        }
        self.allocator.free(discovered_files);
    }
};

// git_history — Analyzes git commit history to find file change coupling.
//
// Files that frequently change together in commits are connected with
// FILE_CHANGES_WITH edges, enabling structural coupling analysis.

const std = @import("std");
const graph_buffer = @import("graph_buffer.zig");
const GraphBufferError = graph_buffer.GraphBufferError;

// --- Public constants (matching the C original) ---

pub const GH_MIN_COMMITS: u32 = 3;
pub const GH_MAX_FILES: u32 = 20;
pub const MIN_COUPLING_SCORE: f64 = 0.3;
pub const MAX_COMMITS: u32 = 10000;

// --- Public types ---

pub const Coupling = struct {
    file_a: []const u8, // relative path
    file_b: []const u8, // relative path
    co_changes: u32,
    coupling_score: f64, // co_changes / min(count_a, count_b)
};

// --- Internal types ---

/// A single parsed commit: list of trackable file paths.
pub const Commit = struct {
    files: std.ArrayList([]const u8),

    pub fn init() Commit {
        return .{ .files = .empty };
    }

    pub fn deinit(self: *Commit, allocator: std.mem.Allocator) void {
        for (self.files.items) |f| allocator.free(f);
        self.files.deinit(allocator);
    }
};

// --- Public API ---

/// Spawn git log, parse commit history, and compute file couplings.
/// Returns an owned slice of Coupling structs; caller must free each
/// coupling's file_a/file_b slices and the slice itself.
pub fn computeCouplings(allocator: std.mem.Allocator, repo_path: []const u8) ![]Coupling {
    const commits = parseGitLog(allocator, repo_path) catch |err| {
        // If git is not available or the repo has no git, return empty.
        std.log.debug("git_history: git log failed ({}) for {s}, returning empty couplings", .{ err, repo_path });
        return allocator.alloc(Coupling, 0);
    };
    defer {
        for (commits) |*c| @constCast(c).deinit(allocator);
        allocator.free(commits);
    }

    return computeCouplingsFromCommits(allocator, commits);
}

/// Compute couplings from pre-parsed commit data (testable without git).
pub fn computeCouplingsFromCommits(allocator: std.mem.Allocator, commits: []const Commit) ![]Coupling {
    // Build file_counts and pair_counts maps.
    var file_counts = std.StringHashMap(u32).init(allocator);
    defer file_counts.deinit();

    // PairKey: canonical "file_a\x00file_b" string where file_a < file_b.
    var pair_counts = std.StringHashMap(u32).init(allocator);
    defer {
        var it = pair_counts.iterator();
        while (it.next()) |entry| allocator.free(entry.key_ptr.*);
        pair_counts.deinit();
    }

    for (commits) |commit| {
        const files = commit.files.items;

        // Skip commits with too many trackable files.
        if (files.len > GH_MAX_FILES) continue;

        // Increment per-file counts.
        for (files) |file| {
            const gop = try file_counts.getOrPut(file);
            if (gop.found_existing) {
                gop.value_ptr.* += 1;
            } else {
                gop.value_ptr.* = 1;
            }
        }

        // Increment pair counts for each unique pair in this commit.
        var i: usize = 0;
        while (i < files.len) : (i += 1) {
            var j: usize = i + 1;
            while (j < files.len) : (j += 1) {
                const pair_key = try makePairKey(allocator, files[i], files[j]);

                const gop = try pair_counts.getOrPut(pair_key);
                if (gop.found_existing) {
                    gop.value_ptr.* += 1;
                    // Key already in map; free the one we just created.
                    allocator.free(pair_key);
                } else {
                    gop.value_ptr.* = 1;
                }
            }
        }
    }

    // Build result: filter by GH_MIN_COMMITS and MIN_COUPLING_SCORE.
    var results: std.ArrayList(Coupling) = .empty;
    errdefer {
        for (results.items) |c| {
            allocator.free(c.file_a);
            allocator.free(c.file_b);
        }
        results.deinit(allocator);
    }

    var it = pair_counts.iterator();
    while (it.next()) |entry| {
        const co_changes = entry.value_ptr.*;
        if (co_changes < GH_MIN_COMMITS) continue;

        // Split pair key back into file_a and file_b.
        const key = entry.key_ptr.*;
        const sep_idx = std.mem.indexOfScalar(u8, key, 0) orelse continue;
        const a = key[0..sep_idx];
        const b = key[sep_idx + 1 ..];

        const count_a = file_counts.get(a) orelse continue;
        const count_b = file_counts.get(b) orelse continue;
        const min_count = @min(count_a, count_b);
        if (min_count == 0) continue;

        const raw_score: f64 = @as(f64, @floatFromInt(co_changes)) / @as(f64, @floatFromInt(min_count));
        const score: f64 = @min(1.0, raw_score);
        if (score < MIN_COUPLING_SCORE) continue;

        const file_a_owned = try allocator.dupe(u8, a);
        errdefer allocator.free(file_a_owned);
        const file_b_owned = try allocator.dupe(u8, b);

        try results.append(allocator, .{
            .file_a = file_a_owned,
            .file_b = file_b_owned,
            .co_changes = co_changes,
            .coupling_score = score,
        });
    }

    return results.toOwnedSlice(allocator);
}

/// Apply computed couplings to the graph buffer as FILE_CHANGES_WITH edges.
/// Returns the number of edges created.
pub fn applyToGraph(
    allocator: std.mem.Allocator,
    gb: *graph_buffer.GraphBuffer,
    couplings: []const Coupling,
) !usize {
    var edges_created: usize = 0;

    for (couplings) |coupling| {
        const id_a = findFileNodeIdByPath(gb, coupling.file_a) orelse continue;
        const id_b = findFileNodeIdByPath(gb, coupling.file_b) orelse continue;

        const props = try std.fmt.allocPrint(
            allocator,
            "{{\"co_changes\":{d},\"coupling_score\":{d:.2}}}",
            .{ coupling.co_changes, coupling.coupling_score },
        );
        defer allocator.free(props);

        _ = gb.insertEdgeWithProperties(id_a, id_b, "FILE_CHANGES_WITH", props) catch |err| switch (err) {
            GraphBufferError.DuplicateEdge => continue,
            GraphBufferError.OutOfMemory => return error.OutOfMemory,
        };
        edges_created += 1;
    }

    return edges_created;
}

/// Full pass: compute couplings from git log and apply to graph.
/// Returns the number of edges created.
pub fn runPass(
    allocator: std.mem.Allocator,
    repo_path: []const u8,
    gb: *graph_buffer.GraphBuffer,
) !usize {
    const couplings = try computeCouplings(allocator, repo_path);
    defer {
        for (couplings) |c| {
            allocator.free(c.file_a);
            allocator.free(c.file_b);
        }
        allocator.free(couplings);
    }

    return applyToGraph(allocator, gb, couplings);
}

/// Returns true for files that should be tracked in coupling analysis.
/// Excludes build artifacts, lock files, binary assets, and vendored dirs.
pub fn isTrackableFile(path: []const u8) bool {
    if (path.len == 0) return false;

    // Excluded directory prefixes.
    if (std.mem.startsWith(u8, path, ".git/")) return false;
    if (std.mem.startsWith(u8, path, "node_modules/")) return false;
    if (std.mem.startsWith(u8, path, "vendor/")) return false;
    if (std.mem.startsWith(u8, path, "__pycache__/")) return false;
    if (std.mem.startsWith(u8, path, ".cache/")) return false;

    const base = std.fs.path.basename(path);

    // Lock files.
    if (std.mem.eql(u8, base, "package-lock.json")) return false;
    if (std.mem.eql(u8, base, "yarn.lock")) return false;
    if (std.mem.eql(u8, base, "pnpm-lock.yaml")) return false;
    if (std.mem.eql(u8, base, "Cargo.lock")) return false;
    if (std.mem.eql(u8, base, "poetry.lock")) return false;
    if (std.mem.eql(u8, base, "composer.lock")) return false;
    if (std.mem.eql(u8, base, "Gemfile.lock")) return false;
    if (std.mem.eql(u8, base, "Pipfile.lock")) return false;

    // Binary and generated extensions.
    if (std.mem.endsWith(u8, path, ".lock")) return false;
    if (std.mem.endsWith(u8, path, ".sum")) return false;
    if (std.mem.endsWith(u8, path, ".min.js")) return false;
    if (std.mem.endsWith(u8, path, ".min.css")) return false;
    if (std.mem.endsWith(u8, path, ".map")) return false;
    if (std.mem.endsWith(u8, path, ".wasm")) return false;
    if (std.mem.endsWith(u8, path, ".png")) return false;
    if (std.mem.endsWith(u8, path, ".jpg")) return false;
    if (std.mem.endsWith(u8, path, ".gif")) return false;
    if (std.mem.endsWith(u8, path, ".ico")) return false;
    if (std.mem.endsWith(u8, path, ".svg")) return false;
    if (std.mem.endsWith(u8, path, ".pyc")) return false;
    if (std.mem.endsWith(u8, path, ".o")) return false;
    if (std.mem.endsWith(u8, path, ".so")) return false;
    if (std.mem.endsWith(u8, path, ".dylib")) return false;
    if (std.mem.endsWith(u8, path, ".class")) return false;

    return true;
}

// --- Internal helpers ---

/// Parse git log output into a list of Commit structures.
fn parseGitLog(allocator: std.mem.Allocator, repo_path: []const u8) ![]Commit {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{
            "git",
            "log",
            "--name-only",
            "--pretty=format:COMMIT:%H",
            "--since=1 year ago",
            "--max-count=10000",
        },
        .cwd = repo_path,
        .max_output_bytes = 64 * 1024 * 1024,
    });
    defer allocator.free(result.stderr);

    const ok = switch (result.term) {
        .Exited => |code| code == 0,
        else => false,
    };
    if (!ok) {
        allocator.free(result.stdout);
        return error.GitFailed;
    }

    defer allocator.free(result.stdout);
    return parseGitOutput(allocator, result.stdout);
}

/// Parse the raw git log output text into commit structures.
fn parseGitOutput(allocator: std.mem.Allocator, output: []const u8) ![]Commit {
    var commits: std.ArrayList(Commit) = .empty;
    errdefer {
        for (commits.items) |*c| c.deinit(allocator);
        commits.deinit(allocator);
    }

    var current_commit: ?Commit = null;

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trimRight(u8, raw_line, "\r");

        if (std.mem.startsWith(u8, line, "COMMIT:")) {
            // Finalize previous commit if it had files.
            if (current_commit) |*prev| {
                if (prev.files.items.len > 0) {
                    try commits.append(allocator, prev.*);
                } else {
                    prev.deinit(allocator);
                }
            }
            current_commit = Commit.init();
            continue;
        }

        if (line.len == 0) continue;

        // File path line; only add if we are inside a commit.
        if (current_commit) |*cc| {
            if (isTrackableFile(line)) {
                const owned = try allocator.dupe(u8, line);
                try cc.files.append(allocator, owned);
            }
        }
    }

    // Finalize last commit.
    if (current_commit) |*last| {
        if (last.files.items.len > 0) {
            try commits.append(allocator, last.*);
        } else {
            last.deinit(allocator);
        }
    }

    return commits.toOwnedSlice(allocator);
}

/// Build a canonical pair key: "lesser\x00greater" (lexicographic order).
fn makePairKey(allocator: std.mem.Allocator, a: []const u8, b: []const u8) ![]u8 {
    const order = std.mem.order(u8, a, b);
    const first = if (order == .lt) a else b;
    const second = if (order == .lt) b else a;
    const key = try allocator.alloc(u8, first.len + 1 + second.len);
    @memcpy(key[0..first.len], first);
    key[first.len] = 0;
    @memcpy(key[first.len + 1 ..], second);
    return key;
}

/// Find a File node's ID by its file_path field.
fn findFileNodeIdByPath(gb: *const graph_buffer.GraphBuffer, file_path: []const u8) ?i64 {
    for (gb.nodes()) |node| {
        if (std.mem.eql(u8, node.label, "File") and std.mem.eql(u8, node.file_path, file_path)) {
            return node.id;
        }
    }
    return null;
}

// --- Errors ---

const GitHistoryError = error{
    GitFailed,
    OutOfMemory,
};

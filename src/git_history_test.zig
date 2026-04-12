const std = @import("std");
const git_history = @import("git_history.zig");
const graph_buffer = @import("graph_buffer.zig");

// --- isTrackableFile tests ---

test "isTrackableFile excludes git directory" {
    try std.testing.expect(!git_history.isTrackableFile(".git/config"));
    try std.testing.expect(!git_history.isTrackableFile(".git/HEAD"));
}

test "isTrackableFile excludes vendored directories" {
    try std.testing.expect(!git_history.isTrackableFile("node_modules/express/index.js"));
    try std.testing.expect(!git_history.isTrackableFile("vendor/autoload.php"));
    try std.testing.expect(!git_history.isTrackableFile("__pycache__/module.cpython-39.pyc"));
    try std.testing.expect(!git_history.isTrackableFile(".cache/build.json"));
}

test "isTrackableFile excludes lock files" {
    try std.testing.expect(!git_history.isTrackableFile("package-lock.json"));
    try std.testing.expect(!git_history.isTrackableFile("yarn.lock"));
    try std.testing.expect(!git_history.isTrackableFile("pnpm-lock.yaml"));
    try std.testing.expect(!git_history.isTrackableFile("Cargo.lock"));
    try std.testing.expect(!git_history.isTrackableFile("poetry.lock"));
    try std.testing.expect(!git_history.isTrackableFile("composer.lock"));
    try std.testing.expect(!git_history.isTrackableFile("Gemfile.lock"));
    try std.testing.expect(!git_history.isTrackableFile("Pipfile.lock"));
    try std.testing.expect(!git_history.isTrackableFile("some/deep/path/package-lock.json"));
}

test "isTrackableFile excludes binary and generated extensions" {
    try std.testing.expect(!git_history.isTrackableFile("dep.lock"));
    try std.testing.expect(!git_history.isTrackableFile("go.sum"));
    try std.testing.expect(!git_history.isTrackableFile("bundle.min.js"));
    try std.testing.expect(!git_history.isTrackableFile("styles.min.css"));
    try std.testing.expect(!git_history.isTrackableFile("app.js.map"));
    try std.testing.expect(!git_history.isTrackableFile("module.wasm"));
    try std.testing.expect(!git_history.isTrackableFile("logo.png"));
    try std.testing.expect(!git_history.isTrackableFile("photo.jpg"));
    try std.testing.expect(!git_history.isTrackableFile("anim.gif"));
    try std.testing.expect(!git_history.isTrackableFile("favicon.ico"));
    try std.testing.expect(!git_history.isTrackableFile("icon.svg"));
    try std.testing.expect(!git_history.isTrackableFile("cache.pyc"));
    try std.testing.expect(!git_history.isTrackableFile("main.o"));
    try std.testing.expect(!git_history.isTrackableFile("libfoo.so"));
    try std.testing.expect(!git_history.isTrackableFile("libbar.dylib"));
    try std.testing.expect(!git_history.isTrackableFile("Main.class"));
}

test "isTrackableFile accepts normal source files" {
    try std.testing.expect(git_history.isTrackableFile("src/main.zig"));
    try std.testing.expect(git_history.isTrackableFile("lib/handler.py"));
    try std.testing.expect(git_history.isTrackableFile("app/models/user.rb"));
    try std.testing.expect(git_history.isTrackableFile("README.md"));
    try std.testing.expect(git_history.isTrackableFile("Makefile"));
    try std.testing.expect(git_history.isTrackableFile("Cargo.toml"));
    try std.testing.expect(git_history.isTrackableFile("package.json"));
    try std.testing.expect(git_history.isTrackableFile("src/index.ts"));
}

test "isTrackableFile rejects empty path" {
    try std.testing.expect(!git_history.isTrackableFile(""));
}

// --- Coupling computation tests ---

const Commit = git_history.Commit;

/// Helper: build a Commit with the given file list (allocates owned copies).
fn makeCommit(allocator: std.mem.Allocator, files: []const []const u8) !Commit {
    var commit = Commit.init();
    for (files) |f| {
        const owned = try allocator.dupe(u8, f);
        try commit.files.append(allocator, owned);
    }
    return commit;
}

test "coupling computation with co-changing files" {
    const allocator = std.testing.allocator;

    // Create 4 commits where a.py and b.py always change together.
    // c.py changes in only 2 of them, so a-c and b-c have fewer co-changes.
    var commits_list: std.ArrayList(Commit) = .empty;
    defer {
        for (commits_list.items) |*c| c.deinit(allocator);
        commits_list.deinit(allocator);
    }

    // Commit 1: a.py, b.py, c.py
    try commits_list.append(allocator, try makeCommit(allocator, &.{ "a.py", "b.py", "c.py" }));
    // Commit 2: a.py, b.py
    try commits_list.append(allocator, try makeCommit(allocator, &.{ "a.py", "b.py" }));
    // Commit 3: a.py, b.py, c.py
    try commits_list.append(allocator, try makeCommit(allocator, &.{ "a.py", "b.py", "c.py" }));
    // Commit 4: a.py, b.py
    try commits_list.append(allocator, try makeCommit(allocator, &.{ "a.py", "b.py" }));

    const couplings = try git_history.computeCouplingsFromCommits(allocator, commits_list.items);
    defer {
        for (couplings) |c| {
            allocator.free(c.file_a);
            allocator.free(c.file_b);
        }
        allocator.free(couplings);
    }

    // a-b: co_changes=4, count_a=4, count_b=4, score=1.0 -> included
    // a-c: co_changes=2, count_a=4, count_c=2, score=1.0 -> excluded (co_changes < 3)
    // b-c: co_changes=2, count_b=4, count_c=2, score=1.0 -> excluded (co_changes < 3)
    try std.testing.expectEqual(@as(usize, 1), couplings.len);

    const c = couplings[0];
    // Pair key is canonicalized, so file_a < file_b.
    try std.testing.expectEqualStrings("a.py", c.file_a);
    try std.testing.expectEqualStrings("b.py", c.file_b);
    try std.testing.expectEqual(@as(u32, 4), c.co_changes);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), c.coupling_score, 0.01);
}

test "coupling computation skips large commits" {
    const allocator = std.testing.allocator;

    // Create commits where a.py and b.py co-change 3 times,
    // but one of those commits has > GH_MAX_FILES files.
    var commits_list: std.ArrayList(Commit) = .empty;
    defer {
        for (commits_list.items) |*c| c.deinit(allocator);
        commits_list.deinit(allocator);
    }

    // Commit 1: a.py, b.py (normal)
    try commits_list.append(allocator, try makeCommit(allocator, &.{ "a.py", "b.py" }));
    // Commit 2: a.py, b.py (normal)
    try commits_list.append(allocator, try makeCommit(allocator, &.{ "a.py", "b.py" }));

    // Commit 3: a.py, b.py + 20 more files (> GH_MAX_FILES, will be skipped)
    {
        var big_commit = Commit.init();
        errdefer big_commit.deinit(allocator);
        try big_commit.files.append(allocator, try allocator.dupe(u8, "a.py"));
        try big_commit.files.append(allocator, try allocator.dupe(u8, "b.py"));
        var i: u32 = 0;
        while (i < 20) : (i += 1) {
            const name = try std.fmt.allocPrint(allocator, "extra_{d}.py", .{i});
            try big_commit.files.append(allocator, name);
        }
        try commits_list.append(allocator, big_commit);
    }

    const couplings = try git_history.computeCouplingsFromCommits(allocator, commits_list.items);
    defer {
        for (couplings) |c| {
            allocator.free(c.file_a);
            allocator.free(c.file_b);
        }
        allocator.free(couplings);
    }

    // Only 2 co-changes (the big commit was skipped), which is below GH_MIN_COMMITS.
    try std.testing.expectEqual(@as(usize, 0), couplings.len);
}

test "coupling computation respects minimum score threshold" {
    const allocator = std.testing.allocator;

    // f.py in 11 commits, g.py in 11 commits, co-changes = 3.
    // score = 3/11 = 0.2727 < 0.3 -> excluded.

    var commits_list: std.ArrayList(Commit) = .empty;
    defer {
        for (commits_list.items) |*c| c.deinit(allocator);
        commits_list.deinit(allocator);
    }

    // 3 commits with f.py and g.py together.
    var ci: u32 = 0;
    while (ci < 3) : (ci += 1) {
        try commits_list.append(allocator, try makeCommit(allocator, &.{ "f.py", "g.py" }));
    }
    // 8 more commits with only f.py.
    ci = 0;
    while (ci < 8) : (ci += 1) {
        try commits_list.append(allocator, try makeCommit(allocator, &.{"f.py"}));
    }
    // 8 more commits with only g.py.
    ci = 0;
    while (ci < 8) : (ci += 1) {
        try commits_list.append(allocator, try makeCommit(allocator, &.{"g.py"}));
    }

    const couplings = try git_history.computeCouplingsFromCommits(allocator, commits_list.items);
    defer {
        for (couplings) |c| {
            allocator.free(c.file_a);
            allocator.free(c.file_b);
        }
        allocator.free(couplings);
    }

    try std.testing.expectEqual(@as(usize, 0), couplings.len);
}

test "coupling computation empty input" {
    const allocator = std.testing.allocator;
    const empty: []const Commit = &.{};

    const couplings = try git_history.computeCouplingsFromCommits(allocator, empty);
    defer allocator.free(couplings);

    try std.testing.expectEqual(@as(usize, 0), couplings.len);
}

// --- applyToGraph tests ---

test "applyToGraph creates FILE_CHANGES_WITH edges for matching file nodes" {
    const allocator = std.testing.allocator;

    var gb = graph_buffer.GraphBuffer.init(allocator, "test-project");
    defer gb.deinit();

    // Create File nodes.
    const id_a = try gb.upsertNode("File", "main.py", "test:file:main.py:python", "main.py", 1, 50);
    const id_b = try gb.upsertNode("File", "utils.py", "test:file:utils.py:python", "utils.py", 1, 30);
    _ = try gb.upsertNode("Function", "do_stuff", "test.do_stuff", "main.py", 5, 10);

    const couplings = [_]git_history.Coupling{
        .{
            .file_a = "main.py",
            .file_b = "utils.py",
            .co_changes = 5,
            .coupling_score = 0.83,
        },
    };

    const edges_created = try git_history.applyToGraph(allocator, &gb, &couplings);
    try std.testing.expectEqual(@as(usize, 1), edges_created);

    // Verify the edge was created.
    const edges = gb.edgeItems();
    try std.testing.expectEqual(@as(usize, 1), edges.len);
    try std.testing.expectEqual(id_a, edges[0].source_id);
    try std.testing.expectEqual(id_b, edges[0].target_id);
    try std.testing.expectEqualStrings("FILE_CHANGES_WITH", edges[0].edge_type);

    // Verify properties contain co_changes and coupling_score.
    try std.testing.expect(std.mem.indexOf(u8, edges[0].properties_json, "\"co_changes\":5") != null);
    try std.testing.expect(std.mem.indexOf(u8, edges[0].properties_json, "\"coupling_score\":0.83") != null);
}

test "applyToGraph skips couplings when file nodes are missing" {
    const allocator = std.testing.allocator;

    var gb = graph_buffer.GraphBuffer.init(allocator, "test-project");
    defer gb.deinit();

    // Only create one of the two files.
    _ = try gb.upsertNode("File", "main.py", "test:file:main.py:python", "main.py", 1, 50);

    const couplings = [_]git_history.Coupling{
        .{
            .file_a = "main.py",
            .file_b = "nonexistent.py",
            .co_changes = 5,
            .coupling_score = 0.83,
        },
    };

    const edges_created = try git_history.applyToGraph(allocator, &gb, &couplings);
    try std.testing.expectEqual(@as(usize, 0), edges_created);
    try std.testing.expectEqual(@as(usize, 0), gb.edgeCount());
}

test "applyToGraph handles duplicate edges silently" {
    const allocator = std.testing.allocator;

    var gb = graph_buffer.GraphBuffer.init(allocator, "test-project");
    defer gb.deinit();

    _ = try gb.upsertNode("File", "main.py", "test:file:main.py:python", "main.py", 1, 50);
    _ = try gb.upsertNode("File", "utils.py", "test:file:utils.py:python", "utils.py", 1, 30);

    const couplings = [_]git_history.Coupling{
        .{
            .file_a = "main.py",
            .file_b = "utils.py",
            .co_changes = 5,
            .coupling_score = 0.83,
        },
    };

    // Apply twice; second time should not error or add duplicates.
    const first = try git_history.applyToGraph(allocator, &gb, &couplings);
    try std.testing.expectEqual(@as(usize, 1), first);

    const second = try git_history.applyToGraph(allocator, &gb, &couplings);
    try std.testing.expectEqual(@as(usize, 0), second);
    try std.testing.expectEqual(@as(usize, 1), gb.edgeCount());
}

test "applyToGraph ignores non-File nodes with matching file_path" {
    const allocator = std.testing.allocator;

    var gb = graph_buffer.GraphBuffer.init(allocator, "test-project");
    defer gb.deinit();

    // Create a Function node with file_path "main.py" but label "Function".
    _ = try gb.upsertNode("Function", "main", "test.main", "main.py", 1, 50);
    _ = try gb.upsertNode("File", "utils.py", "test:file:utils.py:python", "utils.py", 1, 30);

    const couplings = [_]git_history.Coupling{
        .{
            .file_a = "main.py",
            .file_b = "utils.py",
            .co_changes = 5,
            .coupling_score = 0.83,
        },
    };

    // Should not match the Function node, only File nodes.
    const edges_created = try git_history.applyToGraph(allocator, &gb, &couplings);
    try std.testing.expectEqual(@as(usize, 0), edges_created);
}

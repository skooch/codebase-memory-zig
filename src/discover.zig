// discover.zig — File discovery, language detection, and gitignore matching.

const std = @import("std");

// Language enum — mirrors CBMLanguage in the C codebase.
// Order matches lang_specs tables for grammar array indexing.
pub const Language = enum(u8) {
    go = 0,
    python,
    javascript,
    typescript,
    tsx,
    rust,
    java,
    cpp,
    csharp,
    php,
    lua,
    scala,
    kotlin,
    ruby,
    c,
    bash,
    zig,
    elixir,
    haskell,
    ocaml,
    objc,
    swift,
    dart,
    perl,
    groovy,
    erlang,
    r,
    html,
    css,
    scss,
    yaml,
    toml,
    hcl,
    sql,
    dockerfile,
    clojure,
    fsharp,
    julia,
    vimscript,
    nix,
    commonlisp,
    elm,
    fortran,
    cuda,
    cobol,
    verilog,
    emacslisp,
    json,
    xml,
    markdown,
    makefile,
    cmake,
    protobuf,
    graphql,
    vue,
    svelte,
    meson,
    glsl,
    ini,
    matlab,
    lean,
    form,
    magma,
    wolfram,
    kustomize,
    k8s,

    pub const count = @typeInfo(Language).@"enum".fields.len;

    pub fn name(self: Language) []const u8 {
        return @tagName(self);
    }
};

pub const FileInfo = struct {
    path: []const u8, // absolute
    rel_path: []const u8, // relative to repo root
    language: Language,
    size: i64,
};

pub const DiscoverOptions = struct {
    mode: @import("pipeline.zig").IndexMode = .full,
    max_file_size: u64 = 0, // 0 = no limit
};

const IgnoreRule = struct {
    pattern: []const u8,
    anchored: bool,
    dir_only: bool,
    negated: bool,
};

fn joinPath(allocator: std.mem.Allocator, parent: []const u8, child: []const u8) ![]u8 {
    if (parent.len == 0) {
        return allocator.dupe(u8, child);
    }
    return std.fs.path.join(allocator, &.{ parent, child });
}

fn loadIgnoreFile(
    allocator: std.mem.Allocator,
    root: []const u8,
    filename: []const u8,
    rel_prefix: []const u8,
    rules: *std.ArrayList(IgnoreRule),
) !void {
    const path = try joinPath(allocator, root, filename);
    defer allocator.free(path);

    const bytes = std.fs.cwd().readFileAlloc(allocator, path, 8 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer allocator.free(bytes);

    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw_line| {
        var line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') {
            continue;
        }

        var negated = false;
        if (line[0] == '!') {
            negated = true;
            line = line[1..];
        }
        line = std.mem.trim(u8, line, " \t");
        if (line.len == 0) {
            continue;
        }
        const dir_only = std.mem.endsWith(u8, line, "/");
        if (dir_only) {
            line = line[0 .. line.len - 1];
        }
        if (line.len == 0) {
            continue;
        }
        const anchored = line.len > 0 and line[0] == '/';
        const normalized = if (anchored) line[1..] else line;
        if (normalized.len == 0) {
            continue;
        }
        const stored = if (rel_prefix.len == 0)
            try allocator.dupe(u8, normalized)
        else
            try std.fs.path.join(allocator, &.{ rel_prefix, normalized });
        try rules.append(allocator, .{
            .pattern = stored,
            .anchored = anchored,
            .dir_only = dir_only,
            .negated = negated,
        });
    }
}

fn ruleMatches(rule: IgnoreRule, candidate: []const u8, is_dir: bool) bool {
    if (rule.dir_only and !is_dir) {
        return false;
    }
    if (rule.anchored) {
        if (!std.mem.startsWith(u8, candidate, rule.pattern)) {
            return false;
        }
    }
    if (!std.mem.containsAtLeast(u8, candidate, 1, rule.pattern)) {
        return false;
    }
    return true;
}

fn shouldIgnorePath(rules: []const IgnoreRule, candidate: []const u8, is_dir: bool) bool {
    var matched = false;
    for (rules) |rule| {
        if (ruleMatches(rule, candidate, is_dir)) {
            if (rule.negated) {
                matched = false;
            } else {
                matched = true;
            }
        }
    }
    return matched;
}

fn isSkipDirectory(name: []const u8) bool {
    const dirs = [_][]const u8{
        ".git",
        ".hg",
        ".svn",
        ".idea",
        ".vscode",
        ".cache",
        ".turbo",
        ".next",
        "node_modules",
        "dist",
        "build",
        "target",
        "out",
        ".github",
    };
    for (dirs) |item| {
        if (std.mem.eql(u8, name, item)) {
            return true;
        }
    }
    return false;
}

fn isSkipFileSuffix(name: []const u8) bool {
    const suffixes = [_][]const u8{
        ".png",
        ".jpg",
        ".jpeg",
        ".gif",
        ".svg",
        ".ico",
        ".pyc",
        ".class",
        ".o",
        ".obj",
        ".so",
        ".dll",
        ".dylib",
        ".a",
        ".zip",
        ".gz",
        ".tgz",
        ".bz2",
        ".7z",
        ".exe",
        ".bin",
        ".jar",
        ".class",
        ".dat",
        ".mp3",
        ".mp4",
        ".mov",
        ".avi",
        ".woff",
        ".woff2",
    };
    for (suffixes) |suffix| {
        if (std.mem.endsWith(u8, name, suffix)) {
            return true;
        }
    }
    return false;
}

fn isFastSkipFile(name: []const u8, opts: DiscoverOptions) bool {
    const shared_names = [_][]const u8{
        "package.json",
        "tsconfig.json",
    };
    for (shared_names) |item| {
        if (std.mem.eql(u8, name, item)) {
            return true;
        }
    }

    if (opts.mode != .fast) {
        return false;
    }

    const fast_names = [_][]const u8{
        "LICENSE",
        "license",
        "go.sum",
        "go.work.sum",
        "yarn.lock",
        "package-lock.json",
        "pnpm-lock.yaml",
        "pnpm-lock.yml",
    };
    for (fast_names) |item| {
        if (std.mem.eql(u8, name, item)) {
            return true;
        }
    }
    if (std.mem.endsWith(u8, name, ".d.ts")) {
        return true;
    }
    if (std.mem.endsWith(u8, name, ".pb.go")) {
        return true;
    }
    return false;
}

fn languageForFileName(name: []const u8) ?Language {
    if (std.mem.eql(u8, name, "Dockerfile")) {
        return .dockerfile;
    }
    if (std.mem.eql(u8, name, "Makefile")) {
        return .makefile;
    }
    if (std.mem.eql(u8, name, "CMakeLists.txt")) {
        return .cmake;
    }
    if (std.mem.eql(u8, name, ".gitignore")) {
        return null;
    }
    return null;
}

fn containsAny(haystack: []const u8, needle: []const []const u8) bool {
    for (needle) |n| {
        if (std.mem.indexOf(u8, haystack, n) != null) {
            return true;
        }
    }
    return false;
}

fn languageForMFile(abs_path: []const u8) !Language {
    const file = std.fs.cwd().openFile(abs_path, .{}) catch return .magma;
    defer file.close();

    var buf: [4096]u8 = undefined;
    const n = try file.readAll(&buf);
    const sample = buf[0..n];

    if (containsAny(sample, &.{ "@interface", "@implementation", "@protocol", "@property", "#import", "@encode" })) {
        return .objc;
    }
    if (containsAny(sample, &.{ "theorem", "induction", "theorems", "import Mathlib", "classical", "lemma" })) {
        return .magma;
    }
    return .matlab;
}

fn discoverForDirectory(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    abs_base: []const u8,
    rel_base: []const u8,
    opts: DiscoverOptions,
    ignore_rules: *std.ArrayList(IgnoreRule),
    out: *std.ArrayList(FileInfo),
) !void {
    var iterator = dir.iterate();

    while (try iterator.next()) |entry| {
        if (entry.kind == .sym_link) {
            continue;
        }

        const rel_path = if (rel_base.len == 0) try allocator.dupe(u8, entry.name) else try std.fs.path.join(allocator, &.{ rel_base, entry.name });
        defer allocator.free(rel_path);

        if (entry.kind == .directory) {
            if (isSkipDirectory(entry.name) or isFastSkipFile(entry.name, opts)) {
                continue;
            }
            if (shouldIgnorePath(ignore_rules.items, rel_path, true)) {
                continue;
            }

            const child_abs = try joinPath(allocator, abs_base, entry.name);
            defer allocator.free(child_abs);

            var child = try dir.openDir(entry.name, .{ .iterate = true });
            defer child.close();

            const previous_rule_len = ignore_rules.items.len;
            try loadIgnoreFile(allocator, child_abs, ".gitignore", rel_path, ignore_rules);
            try loadIgnoreFile(allocator, child_abs, ".cbmignore", rel_path, ignore_rules);
            defer while (ignore_rules.items.len > previous_rule_len) {
                allocator.free(ignore_rules.pop().?.pattern);
            };

            try discoverForDirectory(allocator, child, child_abs, rel_path, opts, ignore_rules, out);
            continue;
        }

        if (entry.kind != .file) {
            continue;
        }

        if (shouldIgnorePath(ignore_rules.items, rel_path, false)) {
            continue;
        }
        if (isSkipFileSuffix(entry.name) or isFastSkipFile(entry.name, opts)) {
            continue;
        }

        const stat = try dir.statFile(entry.name);
        if (opts.max_file_size > 0 and stat.size > 0 and @as(u64, @intCast(stat.size)) > opts.max_file_size) {
            continue;
        }

        const abs_path = try joinPath(allocator, abs_base, entry.name);
        defer allocator.free(abs_path);

        var language = languageForFileName(entry.name);
        if (language == null) {
            const ext = std.fs.path.extension(entry.name);
            if (std.mem.eql(u8, ext, ".m")) {
                language = try languageForMFile(abs_path);
            } else {
                language = languageForExtension(ext);
            }
        }
        if (language) |lang| {
            const rel_dup = try allocator.dupe(u8, rel_path);
            const abs_dup = try allocator.dupe(u8, abs_path);
            try out.append(allocator, .{
                .path = abs_dup,
                .rel_path = rel_dup,
                .language = lang,
                .size = @intCast(stat.size),
            });
        }
    }
}

pub fn discoverFiles(
    allocator: std.mem.Allocator,
    repo_path: []const u8,
    opts: DiscoverOptions,
) ![]FileInfo {
    const root_abs = try std.fs.cwd().realpathAlloc(allocator, repo_path);
    defer allocator.free(root_abs);

    var ignore_rules = std.ArrayList(IgnoreRule).empty;
    defer {
        for (ignore_rules.items) |item| {
            allocator.free(item.pattern);
        }
        ignore_rules.deinit(allocator);
    }

    // Repository root ignore files are supported, including filename-based overrides.
    try loadIgnoreFile(allocator, root_abs, ".gitignore", "", &ignore_rules);
    try loadIgnoreFile(allocator, root_abs, ".cbmignore", "", &ignore_rules);

    var out = std.ArrayList(FileInfo).empty;
    var root = try std.fs.openDirAbsolute(root_abs, .{ .iterate = true, .no_follow = true });
    defer root.close();

    try discoverForDirectory(allocator, root, root_abs, "", opts, &ignore_rules, &out);
    return try out.toOwnedSlice(allocator);
}

pub fn languageForPath(path: []const u8) ?Language {
    const file_name = std.fs.path.basename(path);
    if (languageForFileName(file_name)) |language| return language;
    return languageForExtension(std.fs.path.extension(file_name));
}

pub fn languageForExtension(ext: []const u8) ?Language {
    const map = std.StaticStringMap(Language).initComptime(.{
        .{ ".go", .go },
        .{ ".py", .python },
        .{ ".js", .javascript },
        .{ ".ts", .typescript },
        .{ ".tsx", .tsx },
        .{ ".rs", .rust },
        .{ ".java", .java },
        .{ ".cpp", .cpp },
        .{ ".cc", .cpp },
        .{ ".cxx", .cpp },
        .{ ".cs", .csharp },
        .{ ".php", .php },
        .{ ".lua", .lua },
        .{ ".scala", .scala },
        .{ ".kt", .kotlin },
        .{ ".rb", .ruby },
        .{ ".c", .c },
        .{ ".h", .c },
        .{ ".sh", .bash },
        .{ ".zig", .zig },
        .{ ".ex", .elixir },
        .{ ".exs", .elixir },
        .{ ".hs", .haskell },
        .{ ".ml", .ocaml },
        .{ ".mli", .ocaml },
        .{ ".m", .objc },
        .{ ".swift", .swift },
        .{ ".dart", .dart },
        .{ ".pl", .perl },
        .{ ".pm", .perl },
        .{ ".groovy", .groovy },
        .{ ".erl", .erlang },
        .{ ".r", .r },
        .{ ".html", .html },
        .{ ".css", .css },
        .{ ".scss", .scss },
        .{ ".yaml", .yaml },
        .{ ".yml", .yaml },
        .{ ".toml", .toml },
        .{ ".tf", .hcl },
        .{ ".sql", .sql },
        .{ ".clj", .clojure },
        .{ ".fs", .fsharp },
        .{ ".fsx", .fsharp },
        .{ ".jl", .julia },
        .{ ".vim", .vimscript },
        .{ ".nix", .nix },
        .{ ".lisp", .commonlisp },
        .{ ".cl", .commonlisp },
        .{ ".elm", .elm },
        .{ ".f90", .fortran },
        .{ ".f95", .fortran },
        .{ ".cu", .cuda },
        .{ ".cob", .cobol },
        .{ ".v", .verilog },
        .{ ".el", .emacslisp },
        .{ ".json", .json },
        .{ ".xml", .xml },
        .{ ".md", .markdown },
        .{ ".proto", .protobuf },
        .{ ".graphql", .graphql },
        .{ ".gql", .graphql },
        .{ ".vue", .vue },
        .{ ".svelte", .svelte },
        .{ ".glsl", .glsl },
        .{ ".ini", .ini },
        .{ ".mat", .matlab },
        .{ ".lean", .lean },
        .{ ".wl", .wolfram },
    });
    return map.get(ext);
}

test "language enum count" {
    // 66 languages in the C codebase (CBM_LANG_COUNT sentinel excluded).
    try std.testing.expectEqual(@as(usize, 66), Language.count);
}

test "extension detection" {
    try std.testing.expectEqual(Language.go, languageForExtension(".go").?);
    try std.testing.expectEqual(Language.zig, languageForExtension(".zig").?);
    try std.testing.expectEqual(Language.python, languageForExtension(".py").?);
    try std.testing.expect(languageForExtension(".xyz") == null);
}

test "discover skips shared js ts config files in full mode" {
    const allocator = std.testing.allocator;
    const root = try std.fmt.allocPrint(allocator, "/tmp/cbm-discover-skip-{x}", .{std.crypto.random.int(u64)});
    defer allocator.free(root);
    try std.fs.cwd().makePath(root);
    defer std.fs.cwd().deleteTree(root) catch {};

    {
        var dir = try std.fs.cwd().openDir(root, .{});
        defer dir.close();

        var index = try dir.createFile("index.js", .{});
        defer index.close();
        try index.writeAll("function boot() { return 1; }\n");

        var package = try dir.createFile("package.json", .{});
        defer package.close();
        try package.writeAll("{\"name\":\"demo\"}\n");

        var tsconfig = try dir.createFile("tsconfig.json", .{});
        defer tsconfig.close();
        try tsconfig.writeAll("{\"compilerOptions\":{}}\n");
    }

    const files = try discoverFiles(allocator, root, .{ .mode = .full });
    defer {
        for (files) |file| {
            allocator.free(file.path);
            allocator.free(file.rel_path);
        }
        allocator.free(files);
    }

    try std.testing.expectEqual(@as(usize, 1), files.len);
    try std.testing.expectEqualStrings("index.js", files[0].rel_path);
}

test "discover honors nested and negated ignore rules" {
    const allocator = std.testing.allocator;
    const root = try std.fmt.allocPrint(allocator, "/tmp/cbm-discover-ignore-{x}", .{std.crypto.random.int(u64)});
    defer allocator.free(root);
    try std.fs.cwd().makePath(root);
    defer std.fs.cwd().deleteTree(root) catch {};

    const nested_dir = try std.fs.path.join(allocator, &.{ root, "src", "nested" });
    defer allocator.free(nested_dir);
    try std.fs.cwd().makePath(nested_dir);

    {
        var dir = try std.fs.cwd().openDir(root, .{});
        defer dir.close();

        var ignore = try dir.createFile(".gitignore", .{});
        defer ignore.close();
        try ignore.writeAll(
            \\keep.js
            \\!keep.js
            \\ignored.js
            \\
        );

        var keep = try dir.createFile("keep.js", .{});
        defer keep.close();
        try keep.writeAll("export function keepHit() { return 1; }\n");

        var ignored = try dir.createFile("ignored.js", .{});
        defer ignored.close();
        try ignored.writeAll("export function ignoredHit() { return 1; }\n");

        var src = try dir.openDir("src", .{});
        defer src.close();

        var index = try src.createFile("index.ts", .{});
        defer index.close();
        try index.writeAll("export function visibleHit() { return 1; }\n");

        var nested = try src.openDir("nested", .{});
        defer nested.close();

        var nested_ignore = try nested.createFile(".gitignore", .{});
        defer nested_ignore.close();
        try nested_ignore.writeAll("ghost.js\n");

        var ghost = try nested.createFile("ghost.js", .{});
        defer ghost.close();
        try ghost.writeAll("export function ghostHit() { return 1; }\n");
    }

    const files = try discoverFiles(allocator, root, .{ .mode = .full });
    defer {
        for (files) |file| {
            allocator.free(file.path);
            allocator.free(file.rel_path);
        }
        allocator.free(files);
    }

    var found_keep = false;
    var found_index = false;
    for (files) |file| {
        if (std.mem.eql(u8, file.rel_path, "keep.js")) found_keep = true;
        if (std.mem.eql(u8, file.rel_path, "src/index.ts")) found_index = true;
        try std.testing.expect(!std.mem.eql(u8, file.rel_path, "ignored.js"));
        try std.testing.expect(!std.mem.eql(u8, file.rel_path, "src/nested/ghost.js"));
    }
    try std.testing.expect(found_keep);
    try std.testing.expect(found_index);
}

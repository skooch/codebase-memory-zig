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

pub fn discoverFiles(
    allocator: std.mem.Allocator,
    repo_path: []const u8,
    opts: DiscoverOptions,
) ![]FileInfo {
    _ = allocator;
    _ = repo_path;
    _ = opts;
    // TODO: walk directory tree, detect languages, respect .gitignore
    return &.{};
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

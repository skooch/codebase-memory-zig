const std = @import("std");

const required_vendored_inputs = [_][]const u8{
    "vendored/tree_sitter/tree_sitter/parser.h",
    "vendored/grammars/rust/parser.c",
    "vendored/grammars/rust/scanner.c",
    "vendored/grammars/python/parser.c",
    "vendored/grammars/python/scanner.c",
    "vendored/grammars/javascript/parser.c",
    "vendored/grammars/javascript/scanner.c",
    "vendored/grammars/typescript/parser.c",
    "vendored/grammars/typescript/scanner.c",
    "vendored/grammars/typescript/_common_scanner.h",
    "vendored/grammars/tsx/parser.c",
    "vendored/grammars/tsx/scanner.c",
    "vendored/grammars/tsx/_common_scanner.h",
    "vendored/grammars/zig/parser.c",
    "vendored/grammars/go/parser.c",
    "vendored/grammars/java/parser.c",
    "vendored/grammars/csharp/parser.c",
    "vendored/grammars/csharp/scanner.c",
    "vendored/grammars/powershell/parser.c",
    "vendored/grammars/powershell/scanner.c",
    "vendored/grammars/gdscript/parser.c",
    "vendored/grammars/gdscript/scanner.c",
};

fn ensureVendoredInputsPresent() void {
    for (required_vendored_inputs) |rel_path| {
        std.fs.cwd().access(rel_path, .{}) catch {
            std.debug.panic(
                "missing required vendored build input: {s}\n" ++
                    "run `mise install`, then `mise run bootstrap`, and retry\n" ++
                    "direct fallback: `bash scripts/fetch_grammars.sh`\n",
                .{rel_path},
            );
        };
    }
}

fn configureCbmModule(
    b: *std.Build,
    mod: *std.Build.Module,
    sqlite_flags: []const []const u8,
) void {
    mod.addIncludePath(b.path("vendored/sqlite3"));
    mod.addIncludePath(b.path("vendored/tree_sitter"));
    mod.addIncludePath(b.path("vendored/grammars/rust"));
    mod.addIncludePath(b.path("vendored/grammars/python"));
    mod.addIncludePath(b.path("vendored/grammars/javascript"));
    mod.addIncludePath(b.path("vendored/grammars/typescript"));
    mod.addIncludePath(b.path("vendored/grammars/tsx"));
    mod.addIncludePath(b.path("vendored/grammars/zig"));
    mod.addIncludePath(b.path("vendored/grammars/go"));
    mod.addIncludePath(b.path("vendored/grammars/java"));
    mod.addIncludePath(b.path("vendored/grammars/csharp"));
    mod.addIncludePath(b.path("vendored/grammars/powershell"));
    mod.addIncludePath(b.path("vendored/grammars/gdscript"));
    mod.addCSourceFile(.{
        .file = b.path("vendored/grammars/rust/parser.c"),
        .flags = &.{},
    });
    mod.addCSourceFile(.{
        .file = b.path("vendored/grammars/rust/scanner.c"),
        .flags = &.{},
    });
    mod.addCSourceFile(.{
        .file = b.path("vendored/grammars/python/parser.c"),
        .flags = &.{},
    });
    mod.addCSourceFile(.{
        .file = b.path("vendored/grammars/python/scanner.c"),
        .flags = &.{},
    });
    mod.addCSourceFile(.{
        .file = b.path("vendored/grammars/javascript/parser.c"),
        .flags = &.{},
    });
    mod.addCSourceFile(.{
        .file = b.path("vendored/grammars/javascript/scanner.c"),
        .flags = &.{},
    });
    mod.addCSourceFile(.{
        .file = b.path("vendored/grammars/typescript/parser.c"),
        .flags = &.{},
    });
    mod.addCSourceFile(.{
        .file = b.path("vendored/grammars/typescript/scanner.c"),
        .flags = &.{},
    });
    mod.addCSourceFile(.{
        .file = b.path("vendored/grammars/tsx/parser.c"),
        .flags = &.{},
    });
    mod.addCSourceFile(.{
        .file = b.path("vendored/grammars/tsx/scanner.c"),
        .flags = &.{},
    });
    mod.addCSourceFile(.{
        .file = b.path("vendored/grammars/zig/parser.c"),
        .flags = &.{},
    });
    mod.addCSourceFile(.{
        .file = b.path("vendored/grammars/go/parser.c"),
        .flags = &.{},
    });
    mod.addCSourceFile(.{
        .file = b.path("vendored/grammars/java/parser.c"),
        .flags = &.{},
    });
    mod.addCSourceFile(.{
        .file = b.path("vendored/grammars/csharp/parser.c"),
        .flags = &.{},
    });
    mod.addCSourceFile(.{
        .file = b.path("vendored/grammars/csharp/scanner.c"),
        .flags = &.{},
    });
    mod.addCSourceFile(.{
        .file = b.path("vendored/grammars/powershell/parser.c"),
        .flags = &.{},
    });
    mod.addCSourceFile(.{
        .file = b.path("vendored/grammars/powershell/scanner.c"),
        .flags = &.{},
    });
    mod.addCSourceFile(.{
        .file = b.path("vendored/grammars/gdscript/parser.c"),
        .flags = &.{},
    });
    mod.addCSourceFile(.{
        .file = b.path("vendored/grammars/gdscript/scanner.c"),
        .flags = &.{},
    });
    mod.addCSourceFile(.{
        .file = b.path("vendored/sqlite3/sqlite3.c"),
        .flags = sqlite_flags,
    });
    mod.link_libc = true;
}

fn createCbmModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    sqlite_flags: []const []const u8,
    public_name: ?[]const u8,
) *std.Build.Module {
    const ts_dep = b.dependency("tree_sitter", .{
        .target = target,
        .optimize = optimize,
    });
    const tree_sitter_mod = ts_dep.module("tree_sitter");

    const mod = if (public_name) |name|
        b.addModule(name, .{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "tree_sitter", .module = tree_sitter_mod },
            },
        })
    else
        b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "tree_sitter", .module = tree_sitter_mod },
            },
        });

    configureCbmModule(b, mod, sqlite_flags);
    return mod;
}

fn addCbmExecutable(
    b: *std.Build,
    mod: *std.Build.Module,
    options: *std.Build.Step.Options,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = "cbm",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "cbm", .module = mod },
            },
        }),
    });
    exe.root_module.addIncludePath(b.path("vendored/sqlite3"));
    exe.root_module.addOptions("build_options", options);
    return exe;
}

pub fn build(b: *std.Build) void {
    ensureVendoredInputsPresent();

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const version = b.option([]const u8, "version", "Application version string") orelse "dev";

    const options = b.addOptions();
    options.addOption([]const u8, "version", version);

    // -- Tree-sitter (zig package) -------------------------------------------

    // -- SQLite C flags -------------------------------------------------------

    const sqlite_flags: []const []const u8 = &.{
        "-DSQLITE_THREADSAFE=1",
        "-DSQLITE_ENABLE_FTS5=1",
        "-DSQLITE_OMIT_LOAD_EXTENSION=1",
        "-DSQLITE_DQS=0",
        "-DSQLITE_DEFAULT_MEMSTATUS=0",
        "-DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1",
    };

    // -- Library module: "cbm" -----------------------------------------------

    const mod = createCbmModule(b, target, optimize, sqlite_flags, "cbm");
    const release_mod = createCbmModule(b, target, .ReleaseSafe, sqlite_flags, null);

    // -- Executable -----------------------------------------------------------

    const exe = addCbmExecutable(b, mod, options, target, optimize);

    b.installArtifact(exe);

    const release_exe = addCbmExecutable(b, release_mod, options, target, .ReleaseSafe);
    const install_release = b.addInstallArtifact(release_exe, .{});
    const release_step = b.step("release", "Install the ReleaseSafe cbm binary");
    release_step.dependOn(&install_release.step);

    // -- Run step -------------------------------------------------------------

    const run_step = b.step("run", "Run the application");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // -- Tests ----------------------------------------------------------------

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}

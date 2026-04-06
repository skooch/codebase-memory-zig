const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const version = b.option([]const u8, "version", "Application version string") orelse "dev";

    const options = b.addOptions();
    options.addOption([]const u8, "version", version);

    // -- Tree-sitter (zig package) -------------------------------------------

    const ts_dep = b.dependency("tree_sitter", .{
        .target = target,
        .optimize = optimize,
    });

    // -- SQLite C flags -------------------------------------------------------

    const sqlite_flags: []const []const u8 = &.{
        "-DSQLITE_THREADSAFE=1",
        "-DSQLITE_OMIT_LOAD_EXTENSION=1",
        "-DSQLITE_DQS=0",
        "-DSQLITE_DEFAULT_MEMSTATUS=0",
        "-DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1",
    };

    // -- Library module: "cbm" -----------------------------------------------

    const mod = b.addModule("cbm", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "tree_sitter", .module = ts_dep.module("tree_sitter") },
        },
    });
    mod.addIncludePath(b.path("vendored/sqlite3"));
    mod.addCSourceFile(.{
        .file = b.path("vendored/sqlite3/sqlite3.c"),
        .flags = sqlite_flags,
    });
    mod.link_libc = true;

    // -- Executable -----------------------------------------------------------

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

    b.installArtifact(exe);

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

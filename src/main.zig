const std = @import("std");
const cbm = @import("cbm");
const build_options = @import("build_options");
const cli = @import("cli.zig");

const usage =
    \\Usage: cbm [COMMAND] [OPTIONS]
    \\
    \\Codebase knowledge graph — MCP server and CLI.
    \\
    \\Commands:
    \\  cli <tool> [json]       Run a single tool call
    \\  install [-y|-n]         Install MCP config for Codex CLI and Claude Code
    \\  uninstall [-y|-n]       Remove installed MCP config entries
    \\  update [-y|-n]          Refresh installed agent config to current binary path
    \\  config <list|get|set>   Manage runtime configuration
    \\
    \\Options:
    \\  --version               Print version and exit
    \\  --help                  Print this help message
    \\
    \\When run without a command, starts the MCP server on stdio.
    \\
;

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next(); // skip argv[0]

    const stdout_file = std.fs.File.stdout();

    // Check for subcommand / flags.
    if (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--version")) {
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "codebase-memory {s}\n", .{build_options.version}) catch "codebase-memory dev\n";
            try stdout_file.writeAll(msg);
            return;
        }
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try stdout_file.writeAll(usage);
            return;
        }
        if (std.mem.eql(u8, arg, "cli")) {
            try runCliToolCall(allocator);
            return;
        }
        if (std.mem.eql(u8, arg, "install")) {
            try runInstallCommand(allocator);
            return;
        }
        if (std.mem.eql(u8, arg, "uninstall")) {
            try runUninstallCommand(allocator);
            return;
        }
        if (std.mem.eql(u8, arg, "update")) {
            try runUpdateCommand(allocator);
            return;
        }
        if (std.mem.eql(u8, arg, "config")) {
            try runConfigCommand(allocator);
            return;
        }
        std.debug.print("Error: unknown command \"{s}\"\n", .{arg});
        std.debug.print("{s}", .{usage});
        std.process.exit(1);
    }

    // Default: run MCP server on stdio.
    try runMcpServer(allocator);
}

const RuntimeState = struct {
    allocator: std.mem.Allocator,
    db_path: []u8,
    index_busy: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    fn deinit(self: *RuntimeState) void {
        self.allocator.free(self.db_path);
    }

    fn tryAcquireIndex(self: *RuntimeState) bool {
        return self.index_busy.cmpxchgStrong(false, true, .acq_rel, .acquire) == null;
    }

    fn releaseIndex(self: *RuntimeState) void {
        self.index_busy.store(false, .release);
    }

    fn runIndex(self: *RuntimeState, root_path: []const u8, mode: cbm.IndexMode) !void {
        var db = try openStoreAtPath(self.allocator, self.db_path);
        defer db.deinit();

        var p = cbm.Pipeline.init(self.allocator, root_path, mode);
        defer p.deinit();
        try p.run(&db);
    }
};

fn runMcpServer(allocator: std.mem.Allocator) !void {
    _ = allocator;
    const runtime_allocator = std.heap.c_allocator;

    var runtime = RuntimeState{
        .allocator = runtime_allocator,
        .db_path = try runtimeDbPath(runtime_allocator),
    };
    defer runtime.deinit();

    var db = try openStoreAtPath(runtime_allocator, runtime.db_path);
    defer db.deinit();

    var watcher = cbm.watcher.Watcher.init(runtime_allocator, &runtime, watcherIndexFn);
    defer watcher.deinit();
    try registerIndexedProjects(&db, &watcher);
    try maybeAutoIndexOnStartup(runtime_allocator, &runtime, &db, &watcher);

    const watcher_thread = try std.Thread.spawn(.{}, watcherThreadMain, .{&watcher});
    defer {
        watcher.stop();
        watcher_thread.join();
    }

    var server = cbm.McpServer.init(runtime_allocator, &db);
    server.setWatcher(&watcher);
    server.setIndexGuard(&runtime.index_busy);
    defer server.deinit();

    const stdin_file = std.fs.File.stdin();
    const stdout_file = std.fs.File.stdout();

    try server.runFiles(stdin_file, stdout_file);
}

fn watcherThreadMain(watcher: *cbm.watcher.Watcher) void {
    watcher.run(5000) catch |err| {
        std.log.warn("watcher loop stopped: {}", .{err});
    };
}

fn watcherIndexFn(ctx: *anyopaque, project_name: []const u8, root_path: []const u8) !void {
    _ = project_name;
    const runtime: *RuntimeState = @ptrCast(@alignCast(ctx));
    if (!runtime.tryAcquireIndex()) return;
    defer runtime.releaseIndex();
    try runtime.runIndex(root_path, .full);
}

fn registerIndexedProjects(db: *cbm.Store, watcher: *cbm.watcher.Watcher) !void {
    const projects = try db.listProjects();
    defer db.freeProjects(projects);

    for (projects) |project| {
        if (project.root_path.len == 0) continue;
        try watcher.watch(project.name, project.root_path);
    }
}

fn maybeAutoIndexOnStartup(
    allocator: std.mem.Allocator,
    runtime: *RuntimeState,
    db: *cbm.Store,
    watcher: *cbm.watcher.Watcher,
) !void {
    var config = cli.loadConfig(allocator) catch cli.AppConfig{};
    defer config.deinit(allocator);
    const auto_index_enabled = config.auto_index or envFlagEnabled("CBM_AUTO_INDEX");
    if (!auto_index_enabled) return;

    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd);

    const project_name = std.fs.path.basename(cwd);
    if (project_name.len == 0) return;

    if (try db.getProject(project_name)) |existing| {
        defer db.freeProject(existing);
        try watcher.watch(project_name, cwd);
        return;
    }

    const limit = if (std.posix.getenv("CBM_AUTO_INDEX_LIMIT") != null)
        envUnsigned("CBM_AUTO_INDEX_LIMIT", config.auto_index_limit)
    else
        config.auto_index_limit;
    const discovered = discoverIndexableFileCount(allocator, cwd) catch |err| {
        std.log.warn("auto-index discovery failed for {s}: {}", .{ cwd, err });
        return;
    };
    if (discovered == 0 or discovered > limit) {
        return;
    }

    if (!runtime.tryAcquireIndex()) return;
    defer runtime.releaseIndex();
    try runtime.runIndex(cwd, .full);
    try watcher.watch(project_name, cwd);
}

fn discoverIndexableFileCount(allocator: std.mem.Allocator, root_path: []const u8) !usize {
    const files = try cbm.discover.discoverFiles(allocator, root_path, .{ .mode = .full });
    defer {
        for (files) |file| {
            allocator.free(file.path);
            allocator.free(file.rel_path);
        }
        allocator.free(files);
    }
    return files.len;
}

fn openStoreAtPath(allocator: std.mem.Allocator, db_path: []const u8) !cbm.Store {
    const db_path_z = try allocator.dupeZ(u8, db_path);
    defer allocator.free(db_path_z);
    return cbm.Store.openPath(allocator, db_path_z);
}

fn runtimeDbPath(allocator: std.mem.Allocator) ![]u8 {
    const cache_dir = try cli.runtimeCacheDir(allocator);
    defer allocator.free(cache_dir);
    try std.fs.cwd().makePath(cache_dir);
    return std.fs.path.join(allocator, &.{ cache_dir, "codebase-memory-zig.db" });
}

fn envFlagEnabled(name: []const u8) bool {
    const value = std.posix.getenv(name) orelse return false;
    return std.ascii.eqlIgnoreCase(value, "1") or
        std.ascii.eqlIgnoreCase(value, "true") or
        std.ascii.eqlIgnoreCase(value, "yes") or
        std.ascii.eqlIgnoreCase(value, "on");
}

fn envUnsigned(name: []const u8, default_value: usize) usize {
    const value = std.posix.getenv(name) orelse return default_value;
    return std.fmt.parseUnsigned(usize, value, 10) catch default_value;
}

const CliToolRequest = struct {
    jsonrpc: []const u8 = "2.0",
    id: i32 = 1,
    method: []const u8 = "tools/call",
    params: CliToolParams,
};

const CliToolParams = struct {
    name: []const u8,
    arguments: std.json.Value,
};

fn runCliToolCall(allocator: std.mem.Allocator) !void {
    const stdout_file = std.fs.File.stdout();
    const stderr_file = std.fs.File.stderr();

    var args_iter = try std.process.argsWithAllocator(allocator);
    defer args_iter.deinit();
    _ = args_iter.next(); // skip argv[0]
    _ = args_iter.next(); // skip "cli"

    var progress = false;
    var positional = std.ArrayList([]const u8).empty;
    defer positional.deinit(allocator);
    while (args_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--progress")) {
            progress = true;
            continue;
        }
        try positional.append(allocator, arg);
    }

    const tool_name = if (positional.items.len > 0) positional.items[0] else {
        try stdout_file.writeAll("Error: cli requires <tool>\n");
        std.process.exit(1);
    };
    const raw_args = if (positional.items.len > 1) positional.items[1] else "{}";
    if (positional.items.len > 2) {
        try stdout_file.writeAll("Error: too many cli arguments\n");
        std.process.exit(1);
    }

    const parsed_args = try std.json.parseFromSlice(std.json.Value, allocator, raw_args, .{});
    defer parsed_args.deinit();
    if (parsed_args.value != .object) {
        try stdout_file.writeAll("Error: cli arguments must be a JSON object\n");
        std.process.exit(1);
    }

    const request = CliToolRequest{
        .params = .{
            .name = tool_name,
            .arguments = parsed_args.value,
        },
    };

    var request_bytes = std.ArrayList(u8).empty;
    defer request_bytes.deinit(allocator);
    try request_bytes.writer(allocator).print("{f}", .{std.json.fmt(request, .{})});
    const request_payload = try request_bytes.toOwnedSlice(allocator);
    defer allocator.free(request_payload);

    const db_path = try runtimeDbPath(allocator);
    defer allocator.free(db_path);

    var db = try openStoreAtPath(allocator, db_path);
    defer db.deinit();
    var server = cbm.McpServer.init(allocator, &db);
    defer server.deinit();

    if (progress) {
        try printFile(stderr_file, "{{\"event\":\"tool_start\",\"tool\":{f}}}\n", .{
            std.json.fmt(tool_name, .{}),
        });
    }
    if (try server.handleRequest(request_payload)) |resp| {
        defer allocator.free(resp);
        try stdout_file.writeAll(resp);
        try stdout_file.writeAll("\n");
        if (progress) {
            try printFile(stderr_file, "{{\"event\":\"tool_done\",\"tool\":{f},\"ok\":true}}\n", .{
                std.json.fmt(tool_name, .{}),
            });
        }
    }
}

const AutoAnswer = enum { ask, yes, no };

fn runConfigCommand(allocator: std.mem.Allocator) !void {
    const stdout_file = std.fs.File.stdout();

    var args_iter = try std.process.argsWithAllocator(allocator);
    defer args_iter.deinit();
    _ = args_iter.next();
    _ = args_iter.next();

    const action = args_iter.next() orelse "list";
    var config = try cli.loadConfig(allocator);
    defer config.deinit(allocator);

    if (std.mem.eql(u8, action, "list") or std.mem.eql(u8, action, "ls")) {
        try printFile(
            stdout_file,
            "auto_index = {s}\nauto_index_limit = {d}\ndownload_url = {s}\n",
            .{
                if (config.auto_index) "true" else "false",
                config.auto_index_limit,
                config.download_url orelse "",
            },
        );
        return;
    }

    const key = args_iter.next() orelse {
        try stdout_file.writeAll("Usage: cbm config <list|get|set|reset> [key] [value]\n");
        std.process.exit(1);
    };

    if (std.mem.eql(u8, action, "get")) {
        try writeConfigValue(stdout_file, key, config);
        return;
    }

    if (std.mem.eql(u8, action, "reset")) {
        try resetConfigKey(allocator, &config, key);
        try cli.saveConfig(allocator, config);
        try printFile(stdout_file, "{s} reset to default\n", .{key});
        return;
    }

    if (std.mem.eql(u8, action, "set")) {
        const value = args_iter.next() orelse {
            try stdout_file.writeAll("Usage: cbm config set <key> <value>\n");
            std.process.exit(1);
        };
        try setConfigKey(allocator, &config, key, value);
        try cli.saveConfig(allocator, config);
        try writeConfigValue(stdout_file, key, config);
        return;
    }

    try printFile(stdout_file, "Unknown config command: {s}\n", .{action});
    std.process.exit(1);
}

fn runInstallCommand(allocator: std.mem.Allocator) !void {
    const stdout_file = std.fs.File.stdout();
    const args = try collectSubcommandArgs(allocator, "install");
    defer freeArgList(allocator, args);

    const parsed = parseActionFlags(args);
    if (!try confirmAction("Install MCP configs for detected agents?", parsed.answer)) {
        try stdout_file.writeAll("Install cancelled.\n");
        std.process.exit(1);
    }

    const home = try cli.homeDir(allocator);
    defer allocator.free(home);
    const binary_path = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(binary_path);

    const report = try cli.installAgentConfigs(allocator, home, .{
        .binary_path = binary_path,
        .dry_run = parsed.dry_run,
        .force = parsed.force,
    });
    try printInstallReport(stdout_file, "Install", report, parsed.dry_run);
    if (report.codex == .skipped and report.claude == .skipped and !parsed.force) {
        try stdout_file.writeAll("No supported agents detected. Use --force to create config files.\n");
        std.process.exit(1);
    }
}

fn runUninstallCommand(allocator: std.mem.Allocator) !void {
    const stdout_file = std.fs.File.stdout();
    const args = try collectSubcommandArgs(allocator, "uninstall");
    defer freeArgList(allocator, args);

    const parsed = parseActionFlags(args);
    if (!try confirmAction("Remove installed MCP configs from supported agents?", parsed.answer)) {
        try stdout_file.writeAll("Uninstall cancelled.\n");
        std.process.exit(1);
    }

    const home = try cli.homeDir(allocator);
    defer allocator.free(home);
    const report = try cli.uninstallAgentConfigs(allocator, home, parsed.dry_run);
    try printInstallReport(stdout_file, "Uninstall", report, parsed.dry_run);
}

fn runUpdateCommand(allocator: std.mem.Allocator) !void {
    const stdout_file = std.fs.File.stdout();
    const args = try collectSubcommandArgs(allocator, "update");
    defer freeArgList(allocator, args);

    const parsed = parseActionFlags(args);
    if (!try confirmAction("Refresh installed MCP configs to the current binary path?", parsed.answer)) {
        try stdout_file.writeAll("Update cancelled.\n");
        std.process.exit(1);
    }

    var config = try cli.loadConfig(allocator);
    defer config.deinit(allocator);
    const home = try cli.homeDir(allocator);
    defer allocator.free(home);
    const binary_path = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(binary_path);

    const report = try cli.installAgentConfigs(allocator, home, .{
        .binary_path = binary_path,
        .dry_run = parsed.dry_run,
        .force = false,
    });
    try printInstallReport(stdout_file, "Update", report, parsed.dry_run);
    if (config.download_url) |_| {
        try stdout_file.writeAll("download_url is configured, but binary self-replacement is intentionally deferred for source builds.\n");
    } else {
        try stdout_file.writeAll("Agent configs were refreshed to the current binary path.\n");
    }
}

const ParsedActionFlags = struct {
    answer: AutoAnswer = .ask,
    dry_run: bool = false,
    force: bool = false,
};

fn parseActionFlags(args: []const []const u8) ParsedActionFlags {
    var parsed = ParsedActionFlags{};
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "-y") or std.mem.eql(u8, arg, "--yes")) parsed.answer = .yes;
        if (std.mem.eql(u8, arg, "-n") or std.mem.eql(u8, arg, "--no")) parsed.answer = .no;
        if (std.mem.eql(u8, arg, "--dry-run")) parsed.dry_run = true;
        if (std.mem.eql(u8, arg, "--force")) parsed.force = true;
    }
    return parsed;
}

fn collectSubcommandArgs(allocator: std.mem.Allocator, command_name: []const u8) ![][]const u8 {
    var args_iter = try std.process.argsWithAllocator(allocator);
    defer args_iter.deinit();

    var found = false;
    var collected = std.ArrayList([]const u8).empty;
    errdefer {
        for (collected.items) |arg| allocator.free(arg);
        collected.deinit(allocator);
    }

    while (args_iter.next()) |arg| {
        if (!found) {
            if (std.mem.eql(u8, arg, command_name)) {
                found = true;
            }
            continue;
        }
        try collected.append(allocator, try allocator.dupe(u8, arg));
    }
    return collected.toOwnedSlice(allocator);
}

fn freeArgList(allocator: std.mem.Allocator, args: [][]const u8) void {
    for (args) |arg| allocator.free(arg);
    allocator.free(args);
}

fn confirmAction(question: []const u8, answer: AutoAnswer) !bool {
    const stdout_file = std.fs.File.stdout();
    const stderr_file = std.fs.File.stderr();
    switch (answer) {
        .yes => {
            try printFile(stdout_file, "{s} (y/n): y (auto)\n", .{question});
            return true;
        },
        .no => {
            try printFile(stdout_file, "{s} (y/n): n (auto)\n", .{question});
            return false;
        },
        .ask => {},
    }

    if (!std.posix.isatty(std.posix.STDIN_FILENO)) {
        try stderr_file.writeAll("error: interactive prompt requires a terminal. Use -y or -n.\n");
        return false;
    }

    try printFile(stdout_file, "{s} (y/n): ", .{question});
    var buf: [32]u8 = undefined;
    const stdin_file = std.fs.File.stdin();
    const bytes = try stdin_file.read(&buf);
    const response = std.mem.trim(u8, buf[0..bytes], " \t\r\n");
    return response.len > 0 and (response[0] == 'y' or response[0] == 'Y');
}

fn printInstallReport(
    stdout_file: std.fs.File,
    label: []const u8,
    report: cli.InstallReport,
    dry_run: bool,
) !void {
    try printFile(
        stdout_file,
        "{s}{s}\n  Codex CLI: {s}\n  Claude Code: {s}\n",
        .{
            label,
            if (dry_run) " (dry run)" else "",
            @tagName(report.codex),
            @tagName(report.claude),
        },
    );
}

fn writeConfigValue(stdout_file: std.fs.File, key: []const u8, config: cli.AppConfig) !void {
    if (std.mem.eql(u8, key, "auto_index")) {
        try printFile(stdout_file, "{s}\n", .{if (config.auto_index) "true" else "false"});
        return;
    }
    if (std.mem.eql(u8, key, "auto_index_limit")) {
        try printFile(stdout_file, "{d}\n", .{config.auto_index_limit});
        return;
    }
    if (std.mem.eql(u8, key, "download_url")) {
        try printFile(stdout_file, "{s}\n", .{config.download_url orelse ""});
        return;
    }
    try printFile(stdout_file, "Unknown config key: {s}\n", .{key});
    std.process.exit(1);
}

fn setConfigKey(allocator: std.mem.Allocator, config: *cli.AppConfig, key: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, key, "auto_index")) {
        config.auto_index = parseBool(value) orelse {
            std.process.exit(1);
        };
        return;
    }
    if (std.mem.eql(u8, key, "auto_index_limit")) {
        config.auto_index_limit = std.fmt.parseUnsigned(usize, value, 10) catch {
            std.process.exit(1);
        };
        return;
    }
    if (std.mem.eql(u8, key, "download_url")) {
        if (config.download_url) |existing| allocator.free(existing);
        config.download_url = if (value.len == 0) null else try allocator.dupe(u8, value);
        return;
    }
    std.process.exit(1);
}

fn resetConfigKey(allocator: std.mem.Allocator, config: *cli.AppConfig, key: []const u8) !void {
    if (std.mem.eql(u8, key, "auto_index")) {
        config.auto_index = false;
        return;
    }
    if (std.mem.eql(u8, key, "auto_index_limit")) {
        config.auto_index_limit = 50_000;
        return;
    }
    if (std.mem.eql(u8, key, "download_url")) {
        if (config.download_url) |existing| allocator.free(existing);
        config.download_url = null;
        return;
    }
    std.process.exit(1);
}

fn parseBool(value: []const u8) ?bool {
    if (std.ascii.eqlIgnoreCase(value, "true") or std.ascii.eqlIgnoreCase(value, "1") or std.ascii.eqlIgnoreCase(value, "yes") or std.ascii.eqlIgnoreCase(value, "on")) return true;
    if (std.ascii.eqlIgnoreCase(value, "false") or std.ascii.eqlIgnoreCase(value, "0") or std.ascii.eqlIgnoreCase(value, "no") or std.ascii.eqlIgnoreCase(value, "off")) return false;
    return null;
}

fn printFile(file: std.fs.File, comptime fmt: []const u8, args: anytype) !void {
    var buf: [4096]u8 = undefined;
    const rendered = try std.fmt.bufPrint(&buf, fmt, args);
    try file.writeAll(rendered);
}

const std = @import("std");
const cbm = @import("cbm");
const build_options = @import("build_options");
const cli = @import("cli.zig");
const runtime_lifecycle = cbm.runtime_lifecycle;

const usage =
    \\Usage: cbm [COMMAND] [OPTIONS]
    \\
    \\Codebase knowledge graph — MCP server and CLI.
    \\
    \\Commands:
    \\  cli <tool> [json]       Run a single tool call
    \\  install [-y|-n] [--scope shipped|detected] [--mcp-only]
    \\                         Install MCP config for the selected agent scope
    \\  uninstall [-y|-n] [--scope shipped|detected] [--mcp-only]
    \\                         Remove installed MCP config entries for the selected scope
    \\  update [-y|-n] [--scope shipped|detected] [--mcp-only]
    \\                         Refresh installed agent config to current binary path
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
    runtime_lifecycle.installSignalHandlers();

    var config = cli.loadConfig(runtime_allocator) catch cli.AppConfig{};
    defer config.deinit(runtime_allocator);

    var runtime = RuntimeState{
        .allocator = runtime_allocator,
        .db_path = try runtimeDbPath(runtime_allocator),
    };
    defer runtime.deinit();

    var lifecycle = runtime_lifecycle.RuntimeLifecycle.init(runtime_allocator, build_options.version);
    lifecycle.setUpdateCheckDisabled(config.update_check_disable);
    defer lifecycle.deinit();

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
    server.setRuntimeLifecycle(&lifecycle);
    server.setRuntimeStorePath(runtime.db_path);
    const idle_store_timeout_ms = envUnsigned("CBM_IDLE_STORE_TIMEOUT_MS", config.idle_store_timeout_ms);
    server.setIdleStoreTimeoutMs(idle_store_timeout_ms);
    defer server.deinit();

    const stdin_file = std.fs.File.stdin();
    const stdout_file = std.fs.File.stdout();

    server.runFiles(stdin_file, stdout_file) catch |err| {
        if (runtime_lifecycle.shutdownRequested()) return;
        return err;
    };
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

    const limit = envUnsigned("CBM_AUTO_INDEX_LIMIT", config.auto_index_limit);
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
    if (std.fs.path.dirname(db_path)) |dir_name| {
        try std.fs.cwd().makePath(dir_name);
    }
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

fn envVarOwnedOrNull(name: []const u8) ?[]u8 {
    return std.process.getEnvVarOwned(std.heap.c_allocator, name) catch null;
}

fn envFlagEnabled(name: []const u8) bool {
    const value = envVarOwnedOrNull(name) orelse return false;
    defer std.heap.c_allocator.free(value);
    return std.ascii.eqlIgnoreCase(value, "1") or
        std.ascii.eqlIgnoreCase(value, "true") or
        std.ascii.eqlIgnoreCase(value, "yes") or
        std.ascii.eqlIgnoreCase(value, "on");
}

fn envUnsigned(name: []const u8, default_value: usize) usize {
    const value = envVarOwnedOrNull(name) orelse return default_value;
    defer std.heap.c_allocator.free(value);
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
        try emitCliProgressStart(allocator, stderr_file, tool_name, parsed_args.value);
    }
    if (try server.handleRequest(request_payload)) |resp| {
        defer allocator.free(resp);
        try stdout_file.writeAll(resp);
        try stdout_file.writeAll("\n");
        if (progress) {
            try emitCliProgressDone(allocator, stderr_file, tool_name, resp);
        }
    }
}

fn emitCliProgressStart(
    allocator: std.mem.Allocator,
    stderr_file: std.fs.File,
    tool_name: []const u8,
    args: std.json.Value,
) !void {
    if (!std.mem.eql(u8, tool_name, "index_repository")) return;
    const project_path = if (args == .object)
        (args.object.get("project_path") orelse .null)
    else
        .null;
    if (project_path != .string) return;

    const files = cbm.discover.discoverFiles(allocator, project_path.string, .{ .mode = .full }) catch {
        try stderr_file.writeAll("  Discovering files...\n");
        try stderr_file.writeAll("  Starting full index\n");
        return;
    };
    defer {
        for (files) |file| {
            allocator.free(file.path);
            allocator.free(file.rel_path);
        }
        allocator.free(files);
    }

    try printFile(stderr_file, "  Discovering files ({d} found)\n", .{files.len});
    try stderr_file.writeAll("  Starting full index\n");
    try stderr_file.writeAll("[1/9] Building file structure\n");
    try stderr_file.writeAll("[5/9] Detecting tests\n");
    try stderr_file.writeAll("[7/9] Analyzing git history\n");
    try stderr_file.writeAll("[8/9] Linking config files\n");
    try stderr_file.writeAll("[9/9] Writing database\n");
}

fn emitCliProgressDone(
    allocator: std.mem.Allocator,
    stderr_file: std.fs.File,
    tool_name: []const u8,
    response: []const u8,
) !void {
    if (!std.mem.eql(u8, tool_name, "index_repository")) return;

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, response, .{}) catch {
        try stderr_file.writeAll("Done.\n");
        return;
    };
    defer parsed.deinit();

    const result = parsed.value.object.get("result") orelse {
        try stderr_file.writeAll("Done.\n");
        return;
    };
    if (result != .object) {
        try stderr_file.writeAll("Done.\n");
        return;
    }

    const nodes = result.object.get("nodes");
    const edges = result.object.get("edges");
    if (nodes != null and edges != null and nodes.? == .integer and edges.? == .integer) {
        try printFile(stderr_file, "Done: {d} nodes, {d} edges\n", .{ nodes.?.integer, edges.?.integer });
        return;
    }
    try stderr_file.writeAll("Done.\n");
}

test "openStoreAtPath creates missing parent directories" {
    const allocator = std.testing.allocator;
    const root = try std.fmt.allocPrint(allocator, "/tmp/cbm-open-store-{x}", .{std.crypto.random.int(u64)});
    defer allocator.free(root);
    defer std.fs.cwd().deleteTree(root) catch {};

    const db_path = try std.fs.path.join(allocator, &.{ root, "cache", "nested", "runtime.db" });
    defer allocator.free(db_path);

    var db = try openStoreAtPath(allocator, db_path);
    defer db.deinit();

    try std.fs.cwd().access(db_path, .{});
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
            "auto_index = {s}\nauto_index_limit = {d}\nidle_store_timeout_ms = {d}\nupdate_check_disable = {s}\ninstall_scope = {s}\ninstall_extras = {s}\ndownload_url = {s}\n",
            .{
                if (config.auto_index) "true" else "false",
                config.auto_index_limit,
                config.idle_store_timeout_ms,
                if (config.update_check_disable) "true" else "false",
                @tagName(config.install_scope),
                if (config.install_extras) "true" else "false",
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

    const parsed = parseActionFlags(args) catch {
        try stdout_file.writeAll("Usage: cbm install [-y|-n] [--dry-run] [--force] [--scope shipped|detected] [--mcp-only]\n");
        std.process.exit(1);
    };
    if (!try confirmAction("Install MCP configs for detected agents?", parsed.answer)) {
        try stdout_file.writeAll("Install cancelled.\n");
        std.process.exit(1);
    }

    const home = try cli.homeDir(allocator);
    defer allocator.free(home);
    const binary_path = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(binary_path);
    var config = try cli.loadConfig(allocator);
    defer config.deinit(allocator);

    const report = try cli.installAgentConfigs(allocator, home, .{
        .binary_path = binary_path,
        .dry_run = parsed.dry_run,
        .force = parsed.force,
        .scope = parsed.scope orelse config.install_scope,
        .include_extras = parsed.include_extras orelse config.install_extras,
    });
    const scope = parsed.scope orelse config.install_scope;
    const include_extras = parsed.include_extras orelse config.install_extras;
    try printInstallReport(allocator, stdout_file, home, binary_path, "Install", report, parsed.dry_run, scope, include_extras);
    if (!cli.hasDetectedAgentsInScope(report.detected, scope) and !parsed.force) {
        if (scope == .shipped) {
            try stdout_file.writeAll("No shipped agents detected. Use --scope detected or --force to create config files.\n");
        } else {
            try stdout_file.writeAll("No supported agents detected. Use --force to create config files.\n");
        }
        std.process.exit(1);
    }
}

fn runUninstallCommand(allocator: std.mem.Allocator) !void {
    const stdout_file = std.fs.File.stdout();
    const args = try collectSubcommandArgs(allocator, "uninstall");
    defer freeArgList(allocator, args);

    const parsed = parseActionFlags(args) catch {
        try stdout_file.writeAll("Usage: cbm uninstall [-y|-n] [--dry-run] [--scope shipped|detected] [--mcp-only]\n");
        std.process.exit(1);
    };
    if (!try confirmAction("Remove installed MCP configs from supported agents?", parsed.answer)) {
        try stdout_file.writeAll("Uninstall cancelled.\n");
        std.process.exit(1);
    }

    const home = try cli.homeDir(allocator);
    defer allocator.free(home);
    var config = try cli.loadConfig(allocator);
    defer config.deinit(allocator);
    const scope = parsed.scope orelse config.install_scope;
    const include_extras = parsed.include_extras orelse config.install_extras;
    const report = try cli.uninstallAgentConfigs(allocator, home, .{
        .dry_run = parsed.dry_run,
        .scope = scope,
        .include_extras = include_extras,
    });
    try printInstallReport(allocator, stdout_file, home, null, "Uninstall", report, parsed.dry_run, scope, include_extras);
}

fn runUpdateCommand(allocator: std.mem.Allocator) !void {
    const stdout_file = std.fs.File.stdout();
    const args = try collectSubcommandArgs(allocator, "update");
    defer freeArgList(allocator, args);

    const parsed = parseActionFlags(args) catch {
        try stdout_file.writeAll("Usage: cbm update [-y|-n] [--dry-run] [--force] [--scope shipped|detected] [--mcp-only]\n");
        std.process.exit(1);
    };
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
        .force = parsed.force,
        .scope = parsed.scope orelse config.install_scope,
        .include_extras = parsed.include_extras orelse config.install_extras,
    });
    const scope = parsed.scope orelse config.install_scope;
    const include_extras = parsed.include_extras orelse config.install_extras;
    try printInstallReport(allocator, stdout_file, home, binary_path, "Update", report, parsed.dry_run, scope, include_extras);
    if (!cli.hasDetectedAgentsInScope(report.detected, scope) and !parsed.force) {
        if (scope == .shipped) {
            try stdout_file.writeAll("No shipped agents detected. Use --scope detected or --force to create config files.\n");
        } else {
            try stdout_file.writeAll("No supported agents detected. Use --force to create config files.\n");
        }
        std.process.exit(1);
    }
    if (config.download_url) |download_url| {
        const artifact = cli.currentSelfUpdateArtifact() catch |err| {
            try printFile(stdout_file, "Configured self-update is not available on this platform: {}\n", .{err});
            std.process.exit(1);
        };
        if (parsed.dry_run) {
            try printFile(
                stdout_file,
                "Dry run complete. Binary would be replaced from the configured release archive ({s}) and agent configs would be refreshed.\n",
                .{artifact.archive_name},
            );
        } else {
            cli.selfReplaceBinaryFromDownloadRoot(allocator, binary_path, download_url) catch |err| {
                try printFile(stdout_file, "Binary self-replacement failed: {}\n", .{err});
                std.process.exit(1);
            };
            try printFile(
                stdout_file,
                "Binary replaced from the configured release archive ({s}). Agent configs were refreshed to the current binary path.\n",
                .{artifact.archive_name},
            );
            try stdout_file.writeAll("Restart your MCP client to pick up the new binary.\n");
        }
    } else {
        if (parsed.dry_run) {
            try stdout_file.writeAll("Dry run complete. Agent configs would be refreshed to the current binary path.\n");
        } else {
            try stdout_file.writeAll("Agent configs were refreshed to the current binary path.\n");
        }
    }
}

const ParsedActionFlags = struct {
    answer: AutoAnswer = .ask,
    dry_run: bool = false,
    force: bool = false,
    scope: ?cli.InstallScope = null,
    include_extras: ?bool = null,
};

fn parseActionFlags(args: []const []const u8) !ParsedActionFlags {
    var parsed = ParsedActionFlags{};
    var idx: usize = 0;
    while (idx < args.len) : (idx += 1) {
        const arg = args[idx];
        if (std.mem.eql(u8, arg, "-y") or std.mem.eql(u8, arg, "--yes")) parsed.answer = .yes;
        if (std.mem.eql(u8, arg, "-n") or std.mem.eql(u8, arg, "--no")) parsed.answer = .no;
        if (std.mem.eql(u8, arg, "--dry-run")) parsed.dry_run = true;
        if (std.mem.eql(u8, arg, "--force")) parsed.force = true;
        if (std.mem.eql(u8, arg, "--mcp-only")) parsed.include_extras = false;
        if (std.mem.eql(u8, arg, "--scope")) {
            idx += 1;
            if (idx >= args.len) return error.InvalidArguments;
            parsed.scope = cli.parseInstallScopeName(args[idx]) orelse return error.InvalidArguments;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--scope=")) {
            parsed.scope = cli.parseInstallScopeName(arg["--scope=".len..]) orelse return error.InvalidArguments;
        }
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

    const stdin_file = std.fs.File.stdin();
    if (!stdin_file.isTty()) {
        try stderr_file.writeAll("error: interactive prompt requires a terminal. Use -y or -n.\n");
        return false;
    }

    try printFile(stdout_file, "{s} (y/n): ", .{question});
    var buf: [32]u8 = undefined;
    const bytes = try stdin_file.read(&buf);
    const response = std.mem.trim(u8, buf[0..bytes], " \t\r\n");
    return response.len > 0 and (response[0] == 'y' or response[0] == 'Y');
}

fn printInstallReport(
    allocator: std.mem.Allocator,
    stdout_file: std.fs.File,
    home: []const u8,
    binary_path: ?[]const u8,
    label: []const u8,
    report: cli.InstallReport,
    dry_run: bool,
    scope: cli.InstallScope,
    include_extras: bool,
) !void {
    const codex_path = try cli.codexConfigPath(allocator, home);
    defer allocator.free(codex_path);
    const claude_nested_path = try cli.claudeNestedConfigPath(allocator, home);
    defer allocator.free(claude_nested_path);
    const claude_legacy_path = try cli.claudeLegacyConfigPath(allocator, home);
    defer allocator.free(claude_legacy_path);

    try printFile(stdout_file, "{s}{s}\n", .{ label, if (dry_run) " (dry run)" else "" });
    try printFile(stdout_file, "Scope: {s}\n", .{@tagName(scope)});
    try printFile(stdout_file, "Extras: {s}\n", .{if (include_extras) "managed" else "mcp-only"});
    try stdout_file.writeAll("Detected agents:");
    if (!cli.hasAnyDetectedAgents(report.detected)) {
        try stdout_file.writeAll(" none\n");
    } else {
        if (report.detected.claude) try stdout_file.writeAll(" Claude Code");
        if (report.detected.codex) try stdout_file.writeAll(" Codex CLI");
        if (report.detected.gemini) try stdout_file.writeAll(" Gemini CLI");
        if (report.detected.zed) try stdout_file.writeAll(" Zed");
        if (report.detected.opencode) try stdout_file.writeAll(" OpenCode");
        if (report.detected.antigravity) try stdout_file.writeAll(" Antigravity");
        if (report.detected.aider) try stdout_file.writeAll(" Aider");
        if (report.detected.kilocode) try stdout_file.writeAll(" KiloCode");
        if (report.detected.vscode) try stdout_file.writeAll(" VS Code");
        if (report.detected.openclaw) try stdout_file.writeAll(" OpenClaw");
        try stdout_file.writeAll("\n");
    }
    if (binary_path) |path| {
        try printFile(stdout_file, "Binary path: {s}\n", .{path});
    }
    try printFile(stdout_file, "  Codex CLI: {s} ({s})\n", .{ @tagName(report.codex), codex_path });
    try printFile(
        stdout_file,
        "  Claude Code: {s} ({s}, {s})\n",
        .{ @tagName(report.claude), claude_nested_path, claude_legacy_path },
    );
    try printActionLine(stdout_file, "Gemini CLI", report.gemini);
    try printActionLine(stdout_file, "Zed", report.zed);
    try printActionLine(stdout_file, "OpenCode", report.opencode);
    try printActionLine(stdout_file, "Antigravity", report.antigravity);
    try printActionLine(stdout_file, "Aider", report.aider);
    try printActionLine(stdout_file, "KiloCode", report.kilocode);
    try printActionLine(stdout_file, "VS Code", report.vscode);
    try printActionLine(stdout_file, "OpenClaw", report.openclaw);
    try printActionLine(stdout_file, "Claude skills", report.skills);
    try printActionLine(stdout_file, "Hooks", report.hooks);
    if (dry_run) {
        try stdout_file.writeAll("(dry-run - no files were modified)\n");
    }
}

fn printActionLine(stdout_file: std.fs.File, label: []const u8, action: cli.InstallReport.Action) !void {
    try printFile(stdout_file, "  {s}: {s}\n", .{ label, @tagName(action) });
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
    if (std.mem.eql(u8, key, "idle_store_timeout_ms")) {
        try printFile(stdout_file, "{d}\n", .{config.idle_store_timeout_ms});
        return;
    }
    if (std.mem.eql(u8, key, "update_check_disable")) {
        try printFile(stdout_file, "{s}\n", .{if (config.update_check_disable) "true" else "false"});
        return;
    }
    if (std.mem.eql(u8, key, "install_scope")) {
        try printFile(stdout_file, "{s}\n", .{@tagName(config.install_scope)});
        return;
    }
    if (std.mem.eql(u8, key, "install_extras")) {
        try printFile(stdout_file, "{s}\n", .{if (config.install_extras) "true" else "false"});
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
    if (std.mem.eql(u8, key, "idle_store_timeout_ms")) {
        config.idle_store_timeout_ms = std.fmt.parseUnsigned(usize, value, 10) catch {
            std.process.exit(1);
        };
        return;
    }
    if (std.mem.eql(u8, key, "update_check_disable")) {
        config.update_check_disable = parseBool(value) orelse {
            std.process.exit(1);
        };
        return;
    }
    if (std.mem.eql(u8, key, "install_scope")) {
        config.install_scope = cli.parseInstallScopeName(value) orelse {
            std.process.exit(1);
        };
        return;
    }
    if (std.mem.eql(u8, key, "install_extras")) {
        config.install_extras = parseBool(value) orelse {
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
    if (std.mem.eql(u8, key, "idle_store_timeout_ms")) {
        config.idle_store_timeout_ms = 60_000;
        return;
    }
    if (std.mem.eql(u8, key, "update_check_disable")) {
        config.update_check_disable = false;
        return;
    }
    if (std.mem.eql(u8, key, "install_scope")) {
        config.install_scope = .shipped;
        return;
    }
    if (std.mem.eql(u8, key, "install_extras")) {
        config.install_extras = true;
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

test "cli progress emits phase-style output for index_repository" {
    const allocator = std.testing.allocator;
    const project_id = std.crypto.random.int(u64);
    const project_dir = try std.fmt.allocPrint(allocator, "/tmp/cbm-cli-progress-{x}", .{project_id});
    defer allocator.free(project_dir);
    try std.fs.cwd().makePath(project_dir);
    defer std.fs.cwd().deleteTree(project_dir) catch {};

    const main_path = try std.fs.path.join(allocator, &.{ project_dir, "main.py" });
    defer allocator.free(main_path);
    var main_file = try std.fs.cwd().createFile(main_path, .{});
    defer main_file.close();
    try main_file.writeAll(
        \\def run():
        \\    return 1
        \\
    );

    const progress_path = try std.fmt.allocPrint(allocator, "/tmp/cbm-cli-progress-output-{x}.log", .{project_id});
    defer allocator.free(progress_path);

    {
        var progress_file = try std.fs.cwd().createFile(progress_path, .{ .truncate = true });
        defer progress_file.close();

        const args_json = try std.fmt.allocPrint(allocator, "{{\"project_path\":\"{s}\"}}", .{project_dir});
        defer allocator.free(args_json);
        const args = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
        defer args.deinit();
        try emitCliProgressStart(allocator, progress_file, "index_repository", args.value);
        try emitCliProgressDone(allocator, progress_file, "index_repository", "{\"result\":{\"nodes\":3,\"edges\":5}}");
    }

    const output = try std.fs.cwd().readFileAlloc(allocator, progress_path, 64 * 1024);
    defer allocator.free(output);
    defer std.fs.cwd().deleteFile(progress_path) catch {};

    try std.testing.expect(std.mem.indexOf(u8, output, "Discovering files") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[1/9] Building file structure") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[5/9] Detecting tests") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[8/9] Linking config files") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Done: 3 nodes, 5 edges") != null);
}

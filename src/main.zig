const std = @import("std");
const cbm = @import("cbm");
const build_options = @import("build_options");

const usage =
    \\Usage: cbm [COMMAND] [OPTIONS]
    \\
    \\Codebase knowledge graph — MCP server and CLI.
    \\
    \\Commands:
    \\  cli <tool> [json]       Run a single tool call
    \\  install [-y|-n]         Install MCP server config for supported agents
    \\  uninstall [-y|-n]       Remove MCP server config
    \\  update [-y|-n]          Update to latest version
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
            std.debug.print("install not yet implemented\n", .{});
            return;
        }
        if (std.mem.eql(u8, arg, "uninstall")) {
            std.debug.print("uninstall not yet implemented\n", .{});
            return;
        }
        if (std.mem.eql(u8, arg, "update")) {
            std.debug.print("update not yet implemented\n", .{});
            return;
        }
        if (std.mem.eql(u8, arg, "config")) {
            std.debug.print("config not yet implemented\n", .{});
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
    if (!envFlagEnabled("CBM_AUTO_INDEX")) return;

    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd);

    const project_name = std.fs.path.basename(cwd);
    if (project_name.len == 0) return;

    if (try db.getProject(project_name)) |existing| {
        defer db.freeProject(existing);
        try watcher.watch(project_name, cwd);
        return;
    }

    const limit = envUnsigned("CBM_AUTO_INDEX_LIMIT", 50_000);
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
    const cache_dir = try runtimeCacheDir(allocator);
    defer allocator.free(cache_dir);
    try std.fs.cwd().makePath(cache_dir);
    return std.fs.path.join(allocator, &.{ cache_dir, "codebase-memory-zig.db" });
}

fn runtimeCacheDir(allocator: std.mem.Allocator) ![]u8 {
    if (std.process.getEnvVarOwned(allocator, "CBM_CACHE_DIR")) |value| {
        return value;
    } else |_| {}

    if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
        defer allocator.free(home);
        return std.fs.path.join(allocator, &.{ home, ".cache", "codebase-memory-zig" });
    } else |_| {}

    return std.fs.path.join(allocator, &.{ ".cache", "codebase-memory-zig" });
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

    var args_iter = try std.process.argsWithAllocator(allocator);
    defer args_iter.deinit();
    _ = args_iter.next(); // skip argv[0]
    _ = args_iter.next(); // skip "cli"

    const tool_name = args_iter.next() orelse {
        try stdout_file.writeAll("Error: cli requires <tool>\n");
        std.process.exit(1);
    };

    const raw_args = args_iter.next() orelse "{}";
    if (args_iter.next()) |_| {
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

    if (try server.handleRequest(request_payload)) |resp| {
        defer allocator.free(resp);
        try stdout_file.writeAll(resp);
        try stdout_file.writeAll("\n");
    }
}

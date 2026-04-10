const std = @import("std");

pub const server_name = "codebase-memory-zig";

const codex_begin_marker = "# BEGIN codebase-memory-zig";
const codex_end_marker = "# END codebase-memory-zig";

pub const AppConfig = struct {
    auto_index: bool = false,
    auto_index_limit: usize = 50_000,
    download_url: ?[]u8 = null,

    pub fn deinit(self: *AppConfig, allocator: std.mem.Allocator) void {
        if (self.download_url) |value| {
            allocator.free(value);
            self.download_url = null;
        }
    }
};

pub const AgentSet = struct {
    codex: bool = false,
    claude: bool = false,
};

pub const InstallOptions = struct {
    binary_path: []const u8,
    dry_run: bool = false,
    force: bool = false,
};

pub const InstallReport = struct {
    codex: Action = .skipped,
    claude: Action = .skipped,

    pub const Action = enum {
        updated,
        removed,
        skipped,
        unchanged,
    };
};

pub fn runtimeCacheDir(allocator: std.mem.Allocator) ![]u8 {
    if (std.process.getEnvVarOwned(allocator, "CBM_CACHE_DIR")) |value| {
        return value;
    } else |_| {}

    if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
        defer allocator.free(home);
        return std.fs.path.join(allocator, &.{ home, ".cache", "codebase-memory-zig" });
    } else |_| {}

    return std.fs.path.join(allocator, &.{ ".cache", "codebase-memory-zig" });
}

pub fn configPath(allocator: std.mem.Allocator) ![]u8 {
    const cache_dir = try runtimeCacheDir(allocator);
    defer allocator.free(cache_dir);
    try std.fs.cwd().makePath(cache_dir);
    return std.fs.path.join(allocator, &.{ cache_dir, "config.json" });
}

pub fn homeDir(allocator: std.mem.Allocator) ![]u8 {
    return try std.process.getEnvVarOwned(allocator, "HOME");
}

pub fn loadConfig(allocator: std.mem.Allocator) !AppConfig {
    const path = try configPath(allocator);
    defer allocator.free(path);
    return loadConfigAtPath(allocator, path);
}

pub fn loadConfigAtPath(allocator: std.mem.Allocator, path: []const u8) !AppConfig {
    const bytes = std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return .{},
        else => return err,
    };
    defer allocator.free(bytes);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, bytes, .{}) catch return .{};
    defer parsed.deinit();
    if (parsed.value != .object) return .{};

    var config = AppConfig{};
    if (parsed.value.object.get("auto_index")) |value| {
        if (value == .bool) config.auto_index = value.bool;
    }
    if (parsed.value.object.get("auto_index_limit")) |value| {
        switch (value) {
            .integer => |v| {
                if (v > 0) config.auto_index_limit = @intCast(v);
            },
            .string => |v| config.auto_index_limit = std.fmt.parseUnsigned(usize, v, 10) catch config.auto_index_limit,
            else => {},
        }
    }
    if (parsed.value.object.get("download_url")) |value| {
        if (value == .string and value.string.len > 0) {
            config.download_url = try allocator.dupe(u8, value.string);
        }
    }
    return config;
}

pub fn saveConfig(allocator: std.mem.Allocator, config: AppConfig) !void {
    const path = try configPath(allocator);
    defer allocator.free(path);
    try saveConfigAtPath(allocator, path, config);
}

pub fn saveConfigAtPath(allocator: std.mem.Allocator, path: []const u8, config: AppConfig) !void {
    if (std.fs.path.dirname(path)) |dir_name| {
        try std.fs.cwd().makePath(dir_name);
    }
    var payload = std.ArrayList(u8).empty;
    defer payload.deinit(allocator);
    try payload.appendSlice(allocator, "{\n");
    try payload.writer(allocator).print("  \"auto_index\": {s},\n", .{if (config.auto_index) "true" else "false"});
    try payload.writer(allocator).print("  \"auto_index_limit\": {d},\n", .{config.auto_index_limit});
    try payload.appendSlice(allocator, "  \"download_url\": ");
    if (config.download_url) |download_url| {
        try payload.writer(allocator).print("{f}", .{std.json.fmt(download_url, .{})});
    } else {
        try payload.appendSlice(allocator, "null");
    }
    try payload.appendSlice(allocator, "\n}\n");

    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(payload.items);
}

pub fn detectAgents(home: []const u8) AgentSet {
    return .{
        .codex = pathExists(home, ".codex"),
        .claude = pathExists(home, ".claude"),
    };
}

pub fn installAgentConfigs(
    allocator: std.mem.Allocator,
    home: []const u8,
    options: InstallOptions,
) !InstallReport {
    const detected = detectAgents(home);
    var report = InstallReport{};

    if (detected.codex or options.force) {
        report.codex = try installCodexConfig(allocator, home, options);
    }
    if (detected.claude or options.force) {
        report.claude = try installClaudeConfig(allocator, home, options);
    }
    return report;
}

pub fn uninstallAgentConfigs(
    allocator: std.mem.Allocator,
    home: []const u8,
    dry_run: bool,
) !InstallReport {
    var report = InstallReport{};
    report.codex = try uninstallCodexConfig(allocator, home, dry_run);
    report.claude = try uninstallClaudeConfig(allocator, home, dry_run);
    return report;
}

fn installCodexConfig(
    allocator: std.mem.Allocator,
    home: []const u8,
    options: InstallOptions,
) !InstallReport.Action {
    const codex_dir = try std.fs.path.join(allocator, &.{ home, ".codex" });
    defer allocator.free(codex_dir);
    const config_path = try std.fs.path.join(allocator, &.{ codex_dir, "config.toml" });
    defer allocator.free(config_path);

    const block = try std.fmt.allocPrint(
        allocator,
        "{s}\n[mcp_servers.{s}]\ncommand = {f}\n{s}\n",
        .{ codex_begin_marker, server_name, std.json.fmt(options.binary_path, .{}), codex_end_marker },
    );
    defer allocator.free(block);

    const existing = std.fs.cwd().readFileAlloc(allocator, config_path, 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    defer if (existing) |contents| allocator.free(contents);

    const updated = try replaceManagedBlock(allocator, existing, block);
    defer allocator.free(updated);

    if (existing != null and std.mem.eql(u8, existing.?, updated)) return .unchanged;
    if (options.dry_run) return .updated;

    try std.fs.cwd().makePath(codex_dir);
    var file = try std.fs.cwd().createFile(config_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(updated);
    return .updated;
}

fn uninstallCodexConfig(
    allocator: std.mem.Allocator,
    home: []const u8,
    dry_run: bool,
) !InstallReport.Action {
    const config_path = try std.fs.path.join(allocator, &.{ home, ".codex", "config.toml" });
    defer allocator.free(config_path);

    const existing = std.fs.cwd().readFileAlloc(allocator, config_path, 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return .skipped,
        else => return err,
    };
    defer allocator.free(existing);

    const updated = try removeManagedBlock(allocator, existing);
    defer allocator.free(updated);
    if (std.mem.eql(u8, existing, updated)) return .skipped;
    if (dry_run) return .removed;

    var file = try std.fs.cwd().createFile(config_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(updated);
    return .removed;
}

fn installClaudeConfig(
    allocator: std.mem.Allocator,
    home: []const u8,
    options: InstallOptions,
) !InstallReport.Action {
    const claude_dir = try std.fs.path.join(allocator, &.{ home, ".claude" });
    defer allocator.free(claude_dir);
    const config_path = try std.fs.path.join(allocator, &.{ claude_dir, ".mcp.json" });
    defer allocator.free(config_path);

    const updated = try updateClaudeConfigJson(allocator, config_path, options.binary_path, true);
    defer allocator.free(updated);
    if (updated.len == 0) return .unchanged;
    if (options.dry_run) return .updated;

    try std.fs.cwd().makePath(claude_dir);
    var file = try std.fs.cwd().createFile(config_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(updated);
    return .updated;
}

fn uninstallClaudeConfig(
    allocator: std.mem.Allocator,
    home: []const u8,
    dry_run: bool,
) !InstallReport.Action {
    const config_path = try std.fs.path.join(allocator, &.{ home, ".claude", ".mcp.json" });
    defer allocator.free(config_path);

    const updated = try updateClaudeConfigJson(allocator, config_path, "", false);
    defer allocator.free(updated);
    if (updated.len == 0) return .skipped;
    if (dry_run) return .removed;

    var file = try std.fs.cwd().createFile(config_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(updated);
    return .removed;
}

fn updateClaudeConfigJson(
    allocator: std.mem.Allocator,
    config_path: []const u8,
    binary_path: []const u8,
    install_entry: bool,
) ![]u8 {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const existing = std.fs.cwd().readFileAlloc(allocator, config_path, 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    defer if (existing) |contents| allocator.free(contents);

    var parsed = if (existing) |contents|
        std.json.parseFromSlice(std.json.Value, arena, contents, .{}) catch null
    else
        null;
    defer if (parsed) |*value| value.deinit();

    var root = if (parsed) |value| value.value else std.json.Value{ .object = std.json.ObjectMap.init(arena) };
    if (root != .object) {
        root = .{ .object = std.json.ObjectMap.init(arena) };
    }

    const servers_ptr = blk: {
        if (root.object.getPtr("mcpServers")) |existing_servers| {
            if (existing_servers.* != .object) {
                existing_servers.* = .{ .object = std.json.ObjectMap.init(arena) };
            }
            break :blk &existing_servers.*.object;
        }
        try root.object.put(try arena.dupe(u8, "mcpServers"), .{ .object = std.json.ObjectMap.init(arena) });
        break :blk &root.object.getPtr("mcpServers").?.*.object;
    };

    if (install_entry) {
        var entry = std.json.ObjectMap.init(arena);
        try entry.put(try arena.dupe(u8, "command"), .{ .string = try arena.dupe(u8, binary_path) });
        if (servers_ptr.getPtr(server_name)) |existing_entry| {
            existing_entry.* = .{ .object = entry };
        } else {
            try servers_ptr.put(try arena.dupe(u8, server_name), .{ .object = entry });
        }
    } else {
        if (!servers_ptr.orderedRemove(server_name)) {
            return allocator.dupe(u8, "");
        }
    }

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    try out.writer(allocator).print("{f}", .{std.json.fmt(root, .{ .whitespace = .indent_2 })});
    try out.append(allocator, '\n');
    return out.toOwnedSlice(allocator);
}

fn replaceManagedBlock(
    allocator: std.mem.Allocator,
    existing: ?[]const u8,
    block: []const u8,
) ![]u8 {
    if (existing) |contents| {
        const begin_idx = std.mem.indexOf(u8, contents, codex_begin_marker);
        const end_idx = std.mem.indexOf(u8, contents, codex_end_marker);
        if (begin_idx != null and end_idx != null and end_idx.? >= begin_idx.?) {
            const after_end = advancePastLine(contents, end_idx.? + codex_end_marker.len);
            return std.mem.concat(allocator, u8, &.{ contents[0..begin_idx.?], block, contents[after_end..] });
        }
        if (contents.len == 0) return allocator.dupe(u8, block);
        if (contents[contents.len - 1] == '\n') {
            return std.mem.concat(allocator, u8, &.{ contents, block });
        }
        return std.mem.concat(allocator, u8, &.{ contents, "\n", block });
    }
    return allocator.dupe(u8, block);
}

fn removeManagedBlock(allocator: std.mem.Allocator, existing: []const u8) ![]u8 {
    const begin_idx = std.mem.indexOf(u8, existing, codex_begin_marker) orelse return allocator.dupe(u8, existing);
    const end_idx = std.mem.indexOf(u8, existing, codex_end_marker) orelse return allocator.dupe(u8, existing);
    const after_end = advancePastLine(existing, end_idx + codex_end_marker.len);
    return std.mem.concat(allocator, u8, &.{ existing[0..begin_idx], existing[after_end..] });
}

fn advancePastLine(text: []const u8, idx: usize) usize {
    var cursor = idx;
    while (cursor < text.len and text[cursor] != '\n') : (cursor += 1) {}
    if (cursor < text.len and text[cursor] == '\n') cursor += 1;
    return cursor;
}

fn pathExists(root: []const u8, relative: []const u8) bool {
    const path = std.fs.path.join(std.heap.page_allocator, &.{ root, relative }) catch return false;
    defer std.heap.page_allocator.free(path);
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

test "config roundtrip preserves values" {
    const allocator = std.testing.allocator;
    const path = try std.fmt.allocPrint(allocator, "/tmp/cbm-config-{x}.json", .{std.crypto.random.int(u64)});
    defer allocator.free(path);
    defer std.fs.cwd().deleteFile(path) catch {};

    var config = AppConfig{
        .auto_index = true,
        .auto_index_limit = 123,
        .download_url = try allocator.dupe(u8, "https://example.com/cbm"),
    };
    defer config.deinit(allocator);
    try saveConfigAtPath(allocator, path, config);

    var loaded = try loadConfigAtPath(allocator, path);
    defer loaded.deinit(allocator);
    try std.testing.expect(loaded.auto_index);
    try std.testing.expectEqual(@as(usize, 123), loaded.auto_index_limit);
    try std.testing.expectEqualStrings("https://example.com/cbm", loaded.download_url.?);
}

test "codex install and uninstall use managed block" {
    const allocator = std.testing.allocator;
    const home = try std.fmt.allocPrint(allocator, "/tmp/cbm-home-codex-{x}", .{std.crypto.random.int(u64)});
    defer allocator.free(home);
    defer std.fs.cwd().deleteTree(home) catch {};
    const codex_dir = try std.fs.path.join(allocator, &.{ home, ".codex" });
    defer allocator.free(codex_dir);
    try std.fs.cwd().makePath(codex_dir);

    const report = try installAgentConfigs(allocator, home, .{
        .binary_path = "/tmp/cbm",
        .force = true,
    });
    try std.testing.expectEqual(InstallReport.Action.updated, report.codex);

    const config_path = try std.fs.path.join(allocator, &.{ home, ".codex", "config.toml" });
    defer allocator.free(config_path);
    const contents = try std.fs.cwd().readFileAlloc(allocator, config_path, 1024 * 1024);
    defer allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, codex_begin_marker) != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, server_name) != null);

    const uninstall = try uninstallAgentConfigs(allocator, home, false);
    try std.testing.expectEqual(InstallReport.Action.removed, uninstall.codex);
    const updated = try std.fs.cwd().readFileAlloc(allocator, config_path, 1024 * 1024);
    defer allocator.free(updated);
    try std.testing.expect(std.mem.indexOf(u8, updated, codex_begin_marker) == null);
}

test "claude install and uninstall manage mcp json entry" {
    const allocator = std.testing.allocator;
    const home = try std.fmt.allocPrint(allocator, "/tmp/cbm-home-claude-{x}", .{std.crypto.random.int(u64)});
    defer allocator.free(home);
    defer std.fs.cwd().deleteTree(home) catch {};
    const claude_dir = try std.fs.path.join(allocator, &.{ home, ".claude" });
    defer allocator.free(claude_dir);
    try std.fs.cwd().makePath(claude_dir);

    const report = try installAgentConfigs(allocator, home, .{
        .binary_path = "/tmp/cbm",
        .force = true,
    });
    try std.testing.expectEqual(InstallReport.Action.updated, report.claude);

    const config_path = try std.fs.path.join(allocator, &.{ home, ".claude", ".mcp.json" });
    defer allocator.free(config_path);
    const contents = try std.fs.cwd().readFileAlloc(allocator, config_path, 1024 * 1024);
    defer allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, server_name) != null);

    const uninstall = try uninstallAgentConfigs(allocator, home, false);
    try std.testing.expectEqual(InstallReport.Action.removed, uninstall.claude);
    const updated = try std.fs.cwd().readFileAlloc(allocator, config_path, 1024 * 1024);
    defer allocator.free(updated);
    try std.testing.expect(std.mem.indexOf(u8, updated, server_name) == null);
}

const builtin = @import("builtin");
const std = @import("std");

pub const server_name = "codebase-memory-zig";

const codex_begin_marker = "# BEGIN codebase-memory-zig";
const codex_end_marker = "# END codebase-memory-zig";

pub const AppConfig = struct {
    auto_index: bool = false,
    auto_index_limit: usize = 50_000,
    idle_store_timeout_ms: usize = 60_000,
    update_check_disable: bool = false,
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
    gemini: bool = false,
    zed: bool = false,
    opencode: bool = false,
    antigravity: bool = false,
    aider: bool = false,
    kilocode: bool = false,
    vscode: bool = false,
    openclaw: bool = false,
};

pub const InstallOptions = struct {
    binary_path: []const u8,
    dry_run: bool = false,
    force: bool = false,
    scope: InstallScope = .detected,
};

pub const UninstallOptions = struct {
    dry_run: bool = false,
    scope: InstallScope = .detected,
};

pub const InstallScope = enum {
    detected,
    shipped,
};

pub const InstallReport = struct {
    detected: AgentSet = .{},
    codex: Action = .skipped,
    claude: Action = .skipped,
    gemini: Action = .skipped,
    zed: Action = .skipped,
    opencode: Action = .skipped,
    antigravity: Action = .skipped,
    aider: Action = .skipped,
    kilocode: Action = .skipped,
    vscode: Action = .skipped,
    openclaw: Action = .skipped,
    skills: Action = .skipped,
    hooks: Action = .skipped,

    pub const Action = enum {
        updated,
        removed,
        skipped,
        unchanged,
    };
};

const AgentTarget = enum {
    codex,
    claude,
    gemini,
    zed,
    opencode,
    antigravity,
    aider,
    kilocode,
    vscode,
    openclaw,
};

const ConfigPlatform = enum {
    windows,
    macos,
    unix,
};

fn currentConfigPlatform() ConfigPlatform {
    if (std.posix.getenv("CBM_CONFIG_PLATFORM")) |override| {
        if (std.ascii.eqlIgnoreCase(override, "windows")) return .windows;
        if (std.ascii.eqlIgnoreCase(override, "macos")) return .macos;
        if (std.ascii.eqlIgnoreCase(override, "linux")) return .unix;
        if (std.ascii.eqlIgnoreCase(override, "unix")) return .unix;
    }
    return switch (builtin.os.tag) {
        .windows => .windows,
        .macos => .macos,
        else => .unix,
    };
}

fn scopeAllowsTarget(scope: InstallScope, target: AgentTarget) bool {
    return switch (scope) {
        .detected => true,
        .shipped => switch (target) {
            .codex, .claude => true,
            else => false,
        },
    };
}

fn runtimeCacheDirForPlatform(
    allocator: std.mem.Allocator,
    home: ?[]const u8,
    platform: ConfigPlatform,
    cache_override: ?[]const u8,
    local_appdata: ?[]const u8,
    xdg_cache_home: ?[]const u8,
) ![]u8 {
    if (cache_override) |value| return allocator.dupe(u8, value);
    if (home) |home_dir| {
        return switch (platform) {
            .windows => if (local_appdata) |value|
                std.fs.path.join(allocator, &.{ value, server_name })
            else
                std.fs.path.join(allocator, &.{ home_dir, "AppData", "Local", server_name }),
            .macos => std.fs.path.join(allocator, &.{ home_dir, ".cache", server_name }),
            .unix => if (xdg_cache_home) |value|
                std.fs.path.join(allocator, &.{ value, server_name })
            else
                std.fs.path.join(allocator, &.{ home_dir, ".cache", server_name }),
        };
    }
    return std.fs.path.join(allocator, &.{ ".cache", server_name });
}

fn appConfigPrefixForPlatform(
    allocator: std.mem.Allocator,
    home: []const u8,
    platform: ConfigPlatform,
    appdata: ?[]const u8,
    xdg_config_home: ?[]const u8,
) ![]u8 {
    return switch (platform) {
        .windows => if (appdata) |value|
            allocator.dupe(u8, value)
        else
            std.fs.path.join(allocator, &.{ home, "AppData", "Roaming" }),
        .macos => std.fs.path.join(allocator, &.{ home, "Library", "Application Support" }),
        .unix => if (xdg_config_home) |value|
            allocator.dupe(u8, value)
        else
            std.fs.path.join(allocator, &.{ home, ".config" }),
    };
}

fn zedConfigPathForPlatform(
    allocator: std.mem.Allocator,
    home: []const u8,
    platform: ConfigPlatform,
    appdata: ?[]const u8,
    xdg_config_home: ?[]const u8,
) ![]u8 {
    const prefix = try appConfigPrefixForPlatform(allocator, home, platform, appdata, xdg_config_home);
    defer allocator.free(prefix);
    const zed_dir = switch (platform) {
        .unix => "zed",
        .macos, .windows => "Zed",
    };
    return std.fs.path.join(allocator, &.{ prefix, zed_dir, "settings.json" });
}

fn vscodeConfigPathForPlatform(
    allocator: std.mem.Allocator,
    home: []const u8,
    platform: ConfigPlatform,
    appdata: ?[]const u8,
    xdg_config_home: ?[]const u8,
) ![]u8 {
    const prefix = try appConfigPrefixForPlatform(allocator, home, platform, appdata, xdg_config_home);
    defer allocator.free(prefix);
    return std.fs.path.join(allocator, &.{ prefix, "Code", "User", "mcp.json" });
}

fn kilocodeConfigPathForPlatform(
    allocator: std.mem.Allocator,
    home: []const u8,
    platform: ConfigPlatform,
    appdata: ?[]const u8,
    xdg_config_home: ?[]const u8,
) ![]u8 {
    const prefix = try appConfigPrefixForPlatform(allocator, home, platform, appdata, xdg_config_home);
    defer allocator.free(prefix);
    return std.fs.path.join(allocator, &.{ prefix, "Code", "User", "globalStorage", "kilocode.kilo-code", "settings", "mcp_settings.json" });
}

pub fn runtimeCacheDir(allocator: std.mem.Allocator) ![]u8 {
    return runtimeCacheDirForPlatform(
        allocator,
        std.posix.getenv("HOME"),
        currentConfigPlatform(),
        std.posix.getenv("CBM_CACHE_DIR"),
        std.posix.getenv("LOCALAPPDATA"),
        std.posix.getenv("XDG_CACHE_HOME"),
    );
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
    if (parsed.value.object.get("idle_store_timeout_ms")) |value| {
        switch (value) {
            .integer => |v| {
                if (v >= 0) config.idle_store_timeout_ms = @intCast(v);
            },
            .string => |v| config.idle_store_timeout_ms = std.fmt.parseUnsigned(usize, v, 10) catch config.idle_store_timeout_ms,
            else => {},
        }
    }
    if (parsed.value.object.get("update_check_disable")) |value| {
        if (value == .bool) config.update_check_disable = value.bool;
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
    try payload.writer(allocator).print("  \"idle_store_timeout_ms\": {d},\n", .{config.idle_store_timeout_ms});
    try payload.writer(allocator).print("  \"update_check_disable\": {s},\n", .{if (config.update_check_disable) "true" else "false"});
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

/// Check if a named executable exists on PATH.
fn executableOnPath(allocator: std.mem.Allocator, name: []const u8) bool {
    const path_env = std.process.getEnvVarOwned(allocator, "PATH") catch return false;
    defer allocator.free(path_env);

    var it = std.mem.splitScalar(u8, path_env, ':');
    while (it.next()) |dir| {
        if (dir.len == 0) continue;
        const full = std.fs.path.join(allocator, &.{ dir, name }) catch continue;
        defer allocator.free(full);
        std.fs.cwd().access(full, .{}) catch continue;
        return true;
    }
    return false;
}

/// Return the platform-specific application config directory prefix.
fn appConfigPrefix(allocator: std.mem.Allocator, home: []const u8) ?[]u8 {
    return appConfigPrefixForPlatform(
        allocator,
        home,
        currentConfigPlatform(),
        std.posix.getenv("APPDATA"),
        std.posix.getenv("XDG_CONFIG_HOME"),
    ) catch null;
}

pub fn detectAgents(allocator: std.mem.Allocator, home: []const u8) AgentSet {
    var agents = AgentSet{};
    const platform = currentConfigPlatform();

    agents.claude = pathExists(home, ".claude");
    agents.codex = pathExists(home, ".codex");
    agents.gemini = pathExists(home, ".gemini");
    agents.openclaw = pathExists(home, ".openclaw");

    // Antigravity: ~/.gemini/antigravity/ — also implies gemini
    if (std.fs.path.join(allocator, &.{ home, ".gemini", "antigravity" })) |ag_path| {
        defer allocator.free(ag_path);
        if (dirExists(ag_path)) {
            agents.antigravity = true;
            agents.gemini = true;
        }
    } else |_| {}

    // Platform-specific agent dirs
    if (appConfigPrefix(allocator, home)) |prefix| {
        defer allocator.free(prefix);

        const zed_sub = switch (platform) {
            .unix => "zed",
            .macos, .windows => "Zed",
        };
        if (std.fs.path.join(allocator, &.{ prefix, zed_sub })) |zed_path| {
            defer allocator.free(zed_path);
            agents.zed = dirExists(zed_path);
        } else |_| {}

        // VS Code: macOS ~/Library/Application Support/Code/User, Linux ~/.config/Code/User
        if (std.fs.path.join(allocator, &.{ prefix, "Code", "User" })) |vscode_path| {
            defer allocator.free(vscode_path);
            agents.vscode = dirExists(vscode_path);
        } else |_| {}

        // KiloCode: macOS ~/Library/Application Support/Code/User/globalStorage/kilocode.kilo-code
        //           Linux ~/.config/Code/User/globalStorage/kilocode.kilo-code
        if (std.fs.path.join(allocator, &.{ prefix, "Code", "User", "globalStorage", "kilocode.kilo-code" })) |kc_path| {
            defer allocator.free(kc_path);
            agents.kilocode = dirExists(kc_path);
        } else |_| {}
    }

    // PATH-based detection
    agents.opencode = executableOnPath(allocator, "opencode");
    agents.aider = executableOnPath(allocator, "aider");

    return agents;
}

/// Detect agents using only home-directory checks (no allocator needed).
/// Used by tests that do not need PATH or platform-specific detection.
pub fn detectAgentsSimple(home: []const u8) AgentSet {
    return .{
        .codex = pathExists(home, ".codex"),
        .claude = pathExists(home, ".claude"),
        .gemini = pathExists(home, ".gemini"),
        .openclaw = pathExists(home, ".openclaw"),
    };
}

pub fn codexConfigPath(allocator: std.mem.Allocator, home: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ home, ".codex", "config.toml" });
}

pub fn claudeNestedConfigPath(allocator: std.mem.Allocator, home: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ home, ".claude", ".mcp.json" });
}

pub fn claudeLegacyConfigPath(allocator: std.mem.Allocator, home: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ home, ".claude.json" });
}

// ── Embedded content ─────────────────────────────────────────────

const skill_name = "codebase-memory";

const skill_content =
    \\---
    \\name: codebase-memory
    \\description: Use the codebase knowledge graph for structural code queries. Triggers on: explore the codebase, understand the architecture, what functions exist, show me the structure, who calls this function, what does X call, trace the call chain, find callers of, show dependencies, impact analysis, dead code, unused functions, high fan-out, refactor candidates, code quality audit, graph query syntax, Cypher query examples, edge types, how to use search_graph.
    \\---
    \\
    \\# Codebase Memory — Knowledge Graph Tools
    \\
    \\Graph tools return precise structural results in ~500 tokens vs ~80K for grep.
    \\
    \\## Quick Decision Matrix
    \\
    \\| Question | Tool call |
    \\|----------|----------|
    \\| Who calls X? | `trace_path(direction="inbound")` |
    \\| What does X call? | `trace_path(direction="outbound")` |
    \\| Full call context | `trace_path(direction="both")` |
    \\| Find by name pattern | `search_graph(name_pattern="...")` |
    \\| Dead code | `search_graph(max_degree=0, exclude_entry_points=true)` |
    \\| Cross-service edges | `query_graph` with Cypher |
    \\| Impact of local changes | `detect_changes()` |
    \\| Risk-classified trace | `trace_path(risk_labels=true)` |
    \\| Text search | `search_code` or Grep |
    \\
    \\## Exploration Workflow
    \\1. `list_projects` — check if project is indexed
    \\2. `get_graph_schema` — understand node/edge types
    \\3. `search_graph(label="Function", name_pattern=".*Pattern.*")` — find code
    \\4. `get_code_snippet(qualified_name="project.path.FuncName")` — read source
    \\
    \\## Tracing Workflow
    \\1. `search_graph(name_pattern=".*FuncName.*")` — discover exact name
    \\2. `trace_path(function_name="FuncName", direction="both", depth=3)` — trace
    \\3. `detect_changes()` — map git diff to affected symbols
    \\
    \\## Quality Analysis
    \\- Dead code: `search_graph(max_degree=0, exclude_entry_points=true)`
    \\- High fan-out: `search_graph(min_degree=10, relationship="CALLS", direction="outbound")`
    \\- High fan-in: `search_graph(min_degree=10, relationship="CALLS", direction="inbound")`
    \\
    \\## 14 MCP Tools
    \\`index_repository`, `index_status`, `list_projects`, `delete_project`,
    \\`search_graph`, `search_code`, `trace_path`, `detect_changes`,
    \\`query_graph`, `get_graph_schema`, `get_code_snippet`, `get_architecture`,
    \\`manage_adr`, `ingest_traces`
    \\
    \\## Edge Types
    \\CALLS, HTTP_CALLS, ASYNC_CALLS, IMPORTS, DEFINES, DEFINES_METHOD,
    \\HANDLES, IMPLEMENTS, OVERRIDE, USAGE, FILE_CHANGES_WITH,
    \\CONTAINS_FILE, CONTAINS_FOLDER, CONTAINS_PACKAGE
    \\
    \\## Cypher Examples (for query_graph)
    \\```
    \\MATCH (a)-[r:HTTP_CALLS]->(b) RETURN a.name, b.name, r.url_path, r.confidence LIMIT 20
    \\MATCH (f:Function) WHERE f.name =~ '.*Handler.*' RETURN f.name, f.file_path
    \\MATCH (a)-[r:CALLS]->(b) WHERE a.name = 'main' RETURN b.name
    \\```
    \\
    \\## Gotchas
    \\1. `search_graph(relationship="HTTP_CALLS")` filters nodes by degree — use `query_graph` with Cypher to see actual edges.
    \\2. `query_graph` has a 200-row cap — use `search_graph` with degree filters for counting.
    \\3. `trace_path` needs exact names — use `search_graph(name_pattern=...)` first.
    \\4. `direction="outbound"` misses cross-service callers — use `direction="both"`.
    \\5. Results default to 10 per page — check `has_more` and use `offset`.
    \\
;

const old_skill_names: []const []const u8 = &.{
    "codebase-memory-exploring",
    "codebase-memory-tracing",
    "codebase-memory-quality",
    "codebase-memory-reference",
};

pub const SkillsResult = struct {
    installed: u32,
    old_removed: bool,
};

/// Install skills to the given skills directory.
/// Writes SKILL.md under skills_dir/codebase-memory/.
/// Cleans up old monolithic skill directories.
pub fn installSkills(
    allocator: std.mem.Allocator,
    skills_dir: []const u8,
    force: bool,
    dry_run: bool,
) !SkillsResult {
    var result = SkillsResult{ .installed = 0, .old_removed = false };

    // Clean up old monolithic skill directories
    for (old_skill_names) |old_name| {
        const old_path = try std.fs.path.join(allocator, &.{ skills_dir, old_name });
        defer allocator.free(old_path);
        if (dirExists(old_path)) {
            result.old_removed = true;
            if (!dry_run) {
                std.fs.cwd().deleteTree(old_path) catch {};
            }
        }
    }

    // Install the consolidated skill
    const skill_dir = try std.fs.path.join(allocator, &.{ skills_dir, skill_name });
    defer allocator.free(skill_dir);
    const file_path = try std.fs.path.join(allocator, &.{ skill_dir, "SKILL.md" });
    defer allocator.free(file_path);

    // Check if already exists (skip unless force)
    if (!force) {
        if (std.fs.cwd().access(file_path, .{})) |_| {
            return result; // file exists and no force
        } else |_| {}
    }

    result.installed = 1;
    if (dry_run) return result;

    try std.fs.cwd().makePath(skill_dir);
    var file = try std.fs.cwd().createFile(file_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(skill_content);

    return result;
}

/// Remove installed skills from the skills directory.
pub fn removeSkills(
    allocator: std.mem.Allocator,
    skills_dir: []const u8,
    dry_run: bool,
) !u32 {
    const skill_dir = try std.fs.path.join(allocator, &.{ skills_dir, skill_name });
    defer allocator.free(skill_dir);

    if (!dirExists(skill_dir)) return 0;
    if (dry_run) return 1;

    std.fs.cwd().deleteTree(skill_dir) catch return 0;
    return 1;
}

// ── Instructions file upsert ─────────────────────────────────────

const instr_marker_start = "<!-- codebase-memory-mcp:start -->";
const instr_marker_end = "<!-- codebase-memory-mcp:end -->";

const agent_instructions_content =
    \\# Codebase Knowledge Graph (codebase-memory-mcp)
    \\
    \\This project uses codebase-memory-mcp to maintain a knowledge graph of the codebase.
    \\ALWAYS prefer MCP graph tools over grep/glob/file-search for code discovery.
    \\
    \\## Priority Order
    \\1. `search_graph` — find functions, classes, routes, variables by pattern
    \\2. `trace_path` — trace who calls a function or what it calls
    \\3. `get_code_snippet` — read specific function/class source code
    \\4. `query_graph` — run Cypher queries for complex patterns
    \\5. `get_architecture` — high-level project summary
    \\
    \\## When to fall back to grep/glob
    \\- Searching for string literals, error messages, config values
    \\- Searching non-code files (Dockerfiles, shell scripts, configs)
    \\- When MCP tools return insufficient results
    \\
    \\## Examples
    \\- Find a handler: `search_graph(name_pattern=".*OrderHandler.*")`
    \\- Who calls it: `trace_path(function_name="OrderHandler", direction="inbound")`
    \\- Read source: `get_code_snippet(qualified_name="pkg/orders.OrderHandler")`
    \\
;

/// Upsert a managed section into a markdown instructions file.
/// If markers exist, replace between them. Otherwise append.
/// Creates the file if it does not exist.
/// Returns true if the file was changed.
pub fn upsertInstructions(
    allocator: std.mem.Allocator,
    path: []const u8,
    content: []const u8,
    dry_run: bool,
) !bool {
    // Build marker-wrapped section
    const section = try std.mem.concat(allocator, u8, &.{
        instr_marker_start, "\n", content, instr_marker_end, "\n",
    });
    defer allocator.free(section);

    const existing = std.fs.cwd().readFileAlloc(allocator, path, 10 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    defer if (existing) |contents| allocator.free(contents);

    const updated = try buildInstructionsUpsert(allocator, existing, section);
    defer allocator.free(updated);

    if (existing) |contents| {
        if (std.mem.eql(u8, contents, updated)) return false;
    }
    if (dry_run) return true;

    // Ensure parent directory exists
    if (std.fs.path.dirname(path)) |dir| {
        try std.fs.cwd().makePath(dir);
    }
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(updated);
    return true;
}

/// Remove the managed section from a markdown instructions file.
/// Returns true if the section was found and removed.
pub fn removeInstructions(
    allocator: std.mem.Allocator,
    path: []const u8,
    dry_run: bool,
) !bool {
    const existing = std.fs.cwd().readFileAlloc(allocator, path, 10 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer allocator.free(existing);

    const start_idx = std.mem.indexOf(u8, existing, instr_marker_start) orelse return false;
    const end_idx = std.mem.indexOf(u8, existing[start_idx..], instr_marker_end) orelse return false;
    const abs_end = start_idx + end_idx + instr_marker_end.len;

    // Skip trailing newline after end marker
    var after_end = abs_end;
    if (after_end < existing.len and existing[after_end] == '\n') after_end += 1;

    // Also remove leading newline before start marker if present
    var before_start = start_idx;
    if (before_start > 0 and existing[before_start - 1] == '\n') before_start -= 1;

    if (dry_run) return true;

    const result = try std.mem.concat(allocator, u8, &.{
        existing[0..before_start],
        existing[after_end..],
    });
    defer allocator.free(result);

    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(result);
    return true;
}

fn buildInstructionsUpsert(
    allocator: std.mem.Allocator,
    existing: ?[]const u8,
    section: []const u8,
) ![]u8 {
    if (existing) |contents| {
        const start_idx = std.mem.indexOf(u8, contents, instr_marker_start);
        if (start_idx) |si| {
            const rest = contents[si..];
            const end_rel = std.mem.indexOf(u8, rest, instr_marker_end);
            if (end_rel) |ei| {
                var abs_end = si + ei + instr_marker_end.len;
                // Skip trailing newline
                if (abs_end < contents.len and contents[abs_end] == '\n') abs_end += 1;
                return std.mem.concat(allocator, u8, &.{
                    contents[0..si], section, contents[abs_end..],
                });
            }
        }
        // No markers found — append
        if (contents.len == 0) return allocator.dupe(u8, section);
        if (contents[contents.len - 1] == '\n') {
            return std.mem.concat(allocator, u8, &.{ contents, section });
        }
        return std.mem.concat(allocator, u8, &.{ contents, "\n", section });
    }
    return allocator.dupe(u8, section);
}

// ── Hook management ─────────────────────────────────────────────

const claude_hook_matcher = "Grep|Glob|Read|Search";
const claude_hook_command = "~/.claude/hooks/cbm-code-discovery-gate";
const session_hook_command = "~/.claude/hooks/cbm-session-reminder";
const session_matchers: []const []const u8 = &.{ "startup", "resume", "clear", "compact" };

const gemini_hook_matcher = "google_search|read_file|grep_search";
const gemini_hook_command =
    "echo 'Reminder: prefer codebase-memory-mcp search_graph/trace_path/" ++
    "get_code_snippet over grep/file search for code discovery.' >&2";

// Old matchers from previous versions (for upgrade compatibility)
const old_hook_matchers: []const []const u8 = &.{"Grep|Glob|Read"};

const gate_script_content =
    \\#!/bin/bash
    \\# Gate hook: nudges Claude toward codebase-memory-mcp for code discovery.
    \\# First Grep/Glob/Read/Search per session -> block. Subsequent -> allow.
    \\# PPID = Claude Code process PID, unique per session.
    \\GATE=/tmp/cbm-code-discovery-gate-$PPID
    \\find /tmp -name 'cbm-code-discovery-gate-*' -mtime +1 -delete 2>/dev/null
    \\if [ -f "$GATE" ]; then
    \\    exit 0
    \\fi
    \\touch "$GATE"
    \\echo 'BLOCKED: For code discovery, use codebase-memory-mcp tools first: search_graph(name_pattern) to find functions/classes, trace_path() for call chains, get_code_snippet(qualified_name) to read source. If the graph is not indexed yet, call index_repository first. Fall back to Grep/Glob/Read only for text content search. If you need Grep, retry.' >&2
    \\exit 2
    \\
;

const session_reminder_content =
    \\#!/bin/bash
    \\# SessionStart hook: remind agent to use codebase-memory-mcp tools.
    \\# Installed by codebase-memory-mcp. Fires on startup/resume/clear/compact.
    \\cat << 'REMINDER'
    \\CRITICAL - Code Discovery Protocol:
    \\1. ALWAYS use codebase-memory-mcp tools FIRST for ANY code exploration:
    \\   - search_graph(name_pattern/label/qn_pattern) to find functions/classes/routes
    \\   - trace_path(function_name, mode=calls|data_flow|cross_service) for call chains
    \\   - get_code_snippet(qualified_name) to read source (NOT Read/cat)
    \\   - query_graph(query) for complex Cypher patterns
    \\   - get_architecture(aspects) for project structure
    \\   - search_code(pattern) for text search (graph-augmented grep)
    \\2. Fall back to Grep/Glob/Read ONLY for text content, config values, non-code files.
    \\3. If a project is not indexed yet, run index_repository FIRST.
    \\REMINDER
    \\
;

/// Check if a hook entry in the JSON array matches our hook (current or old matcher).
fn isCmmHookEntry(
    arena: std.mem.Allocator,
    entry: std.json.Value,
    matcher_str: []const u8,
) bool {
    _ = arena;
    if (entry != .object) return false;
    const matcher_val = entry.object.get("matcher") orelse return false;
    if (matcher_val != .string) return false;
    const val = matcher_val.string;
    if (std.mem.eql(u8, val, matcher_str)) return true;
    // Check old matchers for upgrade compatibility
    for (old_hook_matchers) |old| {
        if (std.mem.eql(u8, val, old)) return true;
    }
    return false;
}

/// Upsert a hook entry into a settings JSON file.
/// Structure: { "hooks": { event: [ { "matcher": m, "hooks": [{ "type": "command", "command": c }] } ] } }
pub fn upsertHooksJson(
    allocator: std.mem.Allocator,
    settings_path: []const u8,
    hook_event: []const u8,
    matcher: []const u8,
    command: []const u8,
    dry_run: bool,
) !bool {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const existing = std.fs.cwd().readFileAlloc(allocator, settings_path, 10 * 1024 * 1024) catch |err| switch (err) {
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

    // Get or create hooks object
    const hooks_ptr = blk: {
        if (root.object.getPtr("hooks")) |h| {
            if (h.* != .object) {
                h.* = .{ .object = std.json.ObjectMap.init(arena) };
            }
            break :blk &h.*.object;
        }
        try root.object.put(try arena.dupe(u8, "hooks"), .{ .object = std.json.ObjectMap.init(arena) });
        break :blk &root.object.getPtr("hooks").?.*.object;
    };

    // Get or create event array
    const event_arr = blk: {
        if (hooks_ptr.getPtr(hook_event)) |ea| {
            if (ea.* != .array) {
                ea.* = .{ .array = std.json.Array.init(arena) };
            }
            break :blk &ea.*.array;
        }
        try hooks_ptr.put(try arena.dupe(u8, hook_event), .{ .array = std.json.Array.init(arena) });
        break :blk &hooks_ptr.getPtr(hook_event).?.*.array;
    };

    // Remove existing CMM entry if present
    var i: usize = 0;
    while (i < event_arr.items.len) {
        if (isCmmHookEntry(arena, event_arr.items[i], matcher)) {
            _ = event_arr.orderedRemove(i);
        } else {
            i += 1;
        }
    }

    // Build our hook entry
    var hook_obj = std.json.ObjectMap.init(arena);
    try hook_obj.put(try arena.dupe(u8, "type"), .{ .string = try arena.dupe(u8, "command") });
    try hook_obj.put(try arena.dupe(u8, "command"), .{ .string = try arena.dupe(u8, command) });

    var hooks_arr = std.json.Array.init(arena);
    try hooks_arr.append(.{ .object = hook_obj });

    var entry = std.json.ObjectMap.init(arena);
    try entry.put(try arena.dupe(u8, "matcher"), .{ .string = try arena.dupe(u8, matcher) });
    try entry.put(try arena.dupe(u8, "hooks"), .{ .array = hooks_arr });

    try event_arr.append(.{ .object = entry });

    // Render
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    try out.writer(allocator).print("{f}", .{std.json.fmt(root, .{ .whitespace = .indent_2 })});
    try out.append(allocator, '\n');
    const rendered = try out.toOwnedSlice(allocator);
    defer allocator.free(rendered);

    if (existing) |contents| {
        if (std.mem.eql(u8, contents, rendered)) return false;
    }
    if (dry_run) return true;

    if (std.fs.path.dirname(settings_path)) |dir| {
        try std.fs.cwd().makePath(dir);
    }
    var file = try std.fs.cwd().createFile(settings_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(rendered);
    return true;
}

/// Remove a hook entry from a settings JSON file.
pub fn removeHooksJson(
    allocator: std.mem.Allocator,
    settings_path: []const u8,
    hook_event: []const u8,
    matcher: []const u8,
    dry_run: bool,
) !bool {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const existing = std.fs.cwd().readFileAlloc(allocator, settings_path, 10 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer allocator.free(existing);

    var parsed = std.json.parseFromSlice(std.json.Value, arena, existing, .{}) catch return false;
    defer parsed.deinit();

    var root = parsed.value;
    if (root != .object) return false;

    const hooks_obj = root.object.getPtr("hooks") orelse return false;
    if (hooks_obj.* != .object) return false;

    const event_arr_val = hooks_obj.object.getPtr(hook_event) orelse return false;
    if (event_arr_val.* != .array) return false;

    var found = false;
    var i: usize = 0;
    while (i < event_arr_val.array.items.len) {
        if (isCmmHookEntry(arena, event_arr_val.array.items[i], matcher)) {
            _ = event_arr_val.array.orderedRemove(i);
            found = true;
        } else {
            i += 1;
        }
    }
    if (!found) return false;
    if (dry_run) return true;

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    try out.writer(allocator).print("{f}", .{std.json.fmt(root, .{ .whitespace = .indent_2 })});
    try out.append(allocator, '\n');

    var file = try std.fs.cwd().createFile(settings_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(out.items);
    return true;
}

/// Install the code discovery gate script to ~/.claude/hooks/.
pub fn installHookGateScript(
    allocator: std.mem.Allocator,
    home: []const u8,
    dry_run: bool,
) !void {
    if (dry_run) return;
    const hooks_dir = try std.fs.path.join(allocator, &.{ home, ".claude", "hooks" });
    defer allocator.free(hooks_dir);
    try std.fs.cwd().makePath(hooks_dir);

    const script_path = try std.fs.path.join(allocator, &.{ hooks_dir, "cbm-code-discovery-gate" });
    defer allocator.free(script_path);

    var file = try std.fs.cwd().createFile(script_path, .{ .truncate = true, .mode = 0o755 });
    defer file.close();
    try file.writeAll(gate_script_content);
}

/// Install the session reminder script to ~/.claude/hooks/.
pub fn installSessionReminderScript(
    allocator: std.mem.Allocator,
    home: []const u8,
    dry_run: bool,
) !void {
    if (dry_run) return;
    const hooks_dir = try std.fs.path.join(allocator, &.{ home, ".claude", "hooks" });
    defer allocator.free(hooks_dir);
    try std.fs.cwd().makePath(hooks_dir);

    const script_path = try std.fs.path.join(allocator, &.{ hooks_dir, "cbm-session-reminder" });
    defer allocator.free(script_path);

    var file = try std.fs.cwd().createFile(script_path, .{ .truncate = true, .mode = 0o755 });
    defer file.close();
    try file.writeAll(session_reminder_content);
}

/// Upsert Claude hooks: PreToolUse gate + SessionStart reminders.
pub fn upsertClaudeHooks(
    allocator: std.mem.Allocator,
    home: []const u8,
    dry_run: bool,
) !bool {
    const settings_path = try std.fs.path.join(allocator, &.{ home, ".claude", "settings.json" });
    defer allocator.free(settings_path);

    var changed = false;

    // PreToolUse hook
    if (try upsertHooksJson(allocator, settings_path, "PreToolUse", claude_hook_matcher, claude_hook_command, dry_run))
        changed = true;
    try installHookGateScript(allocator, home, dry_run);

    // SessionStart hooks
    for (session_matchers) |m| {
        if (try upsertHooksJson(allocator, settings_path, "SessionStart", m, session_hook_command, dry_run))
            changed = true;
    }
    try installSessionReminderScript(allocator, home, dry_run);

    return changed;
}

/// Remove Claude hooks from settings.json.
pub fn removeClaudeHooks(
    allocator: std.mem.Allocator,
    home: []const u8,
    dry_run: bool,
) !void {
    const settings_path = try std.fs.path.join(allocator, &.{ home, ".claude", "settings.json" });
    defer allocator.free(settings_path);

    _ = try removeHooksJson(allocator, settings_path, "PreToolUse", claude_hook_matcher, dry_run);
    for (session_matchers) |m| {
        _ = try removeHooksJson(allocator, settings_path, "SessionStart", m, dry_run);
    }
}

/// Upsert Gemini BeforeTool hook.
pub fn upsertGeminiHooks(
    allocator: std.mem.Allocator,
    settings_path: []const u8,
    dry_run: bool,
) !void {
    _ = try upsertHooksJson(allocator, settings_path, "BeforeTool", gemini_hook_matcher, gemini_hook_command, dry_run);
}

/// Remove Gemini BeforeTool hook.
pub fn removeGeminiHooks(
    allocator: std.mem.Allocator,
    settings_path: []const u8,
    dry_run: bool,
) !void {
    _ = try removeHooksJson(allocator, settings_path, "BeforeTool", gemini_hook_matcher, dry_run);
}

pub fn installAgentConfigs(
    allocator: std.mem.Allocator,
    home: []const u8,
    options: InstallOptions,
) !InstallReport {
    const detected = detectAgents(allocator, home);
    var report = InstallReport{ .detected = detected };

    // Claude Code: MCP + skills + hooks + instructions (no instructions file in C ref for Claude itself)
    if (scopeAllowsTarget(options.scope, .claude) and (detected.claude or options.force)) {
        report.claude = try installClaudeConfig(allocator, home, options);
        // Skills
        const skills_dir = try std.fs.path.join(allocator, &.{ home, ".claude", "skills" });
        defer allocator.free(skills_dir);
        const sr = try installSkills(allocator, skills_dir, options.force, options.dry_run);
        if (sr.installed > 0 or sr.old_removed) report.skills = .updated;
        // Hooks
        if (try upsertClaudeHooks(allocator, home, options.dry_run))
            report.hooks = .updated;
    }

    // Codex: MCP + instructions
    if (scopeAllowsTarget(options.scope, .codex) and (detected.codex or options.force)) {
        report.codex = try installCodexConfig(allocator, home, options);
        const ip = try std.fs.path.join(allocator, &.{ home, ".codex", "AGENTS.md" });
        defer allocator.free(ip);
        _ = try upsertInstructions(allocator, ip, agent_instructions_content, options.dry_run);
    }

    // Gemini: MCP + hooks + instructions
    if (scopeAllowsTarget(options.scope, .gemini) and (detected.gemini or options.force)) {
        report.gemini = try installGenericJsonConfig(allocator, home, options, .{
            .config_parts = &.{ ".gemini", "settings.json" },
            .format = .mcp_servers,
        });
        const ip = try std.fs.path.join(allocator, &.{ home, ".gemini", "GEMINI.md" });
        defer allocator.free(ip);
        _ = try upsertInstructions(allocator, ip, agent_instructions_content, options.dry_run);
        const cp = try std.fs.path.join(allocator, &.{ home, ".gemini", "settings.json" });
        defer allocator.free(cp);
        try upsertGeminiHooks(allocator, cp, options.dry_run);
    }

    // Zed: MCP only (platform-specific path)
    if (scopeAllowsTarget(options.scope, .zed) and (detected.zed or options.force)) {
        report.zed = try installZedConfig(allocator, home, options);
    }

    // VS Code: MCP only (platform-specific path)
    if (scopeAllowsTarget(options.scope, .vscode) and (detected.vscode or options.force)) {
        report.vscode = try installVscodeConfig(allocator, home, options);
    }

    // OpenCode: MCP + instructions
    if (scopeAllowsTarget(options.scope, .opencode) and (detected.opencode or options.force)) {
        report.opencode = try installGenericJsonConfig(allocator, home, options, .{
            .config_parts = &.{ ".config", "opencode", "opencode.json" },
            .format = .opencode,
        });
        const ip = try std.fs.path.join(allocator, &.{ home, ".config", "opencode", "AGENTS.md" });
        defer allocator.free(ip);
        _ = try upsertInstructions(allocator, ip, agent_instructions_content, options.dry_run);
    }

    // Antigravity: MCP + instructions
    if (scopeAllowsTarget(options.scope, .antigravity) and (detected.antigravity or options.force)) {
        report.antigravity = try installGenericJsonConfig(allocator, home, options, .{
            .config_parts = &.{ ".gemini", "antigravity", "mcp_config.json" },
            .format = .mcp_servers,
        });
        const ip = try std.fs.path.join(allocator, &.{ home, ".gemini", "antigravity", "AGENTS.md" });
        defer allocator.free(ip);
        _ = try upsertInstructions(allocator, ip, agent_instructions_content, options.dry_run);
    }

    // KiloCode: MCP + instructions (platform-specific config path)
    if (scopeAllowsTarget(options.scope, .kilocode) and (detected.kilocode or options.force)) {
        report.kilocode = try installKilocodeConfig(allocator, home, options);
        const ip = try std.fs.path.join(allocator, &.{ home, ".kilocode", "rules", "codebase-memory-mcp.md" });
        defer allocator.free(ip);
        _ = try upsertInstructions(allocator, ip, agent_instructions_content, options.dry_run);
    }

    // Aider: instructions only (no MCP config)
    if (scopeAllowsTarget(options.scope, .aider) and (detected.aider or options.force)) {
        const ip = try std.fs.path.join(allocator, &.{ home, "CONVENTIONS.md" });
        defer allocator.free(ip);
        if (try upsertInstructions(allocator, ip, agent_instructions_content, options.dry_run)) {
            report.aider = .updated;
        } else {
            report.aider = .unchanged;
        }
    }

    // OpenClaw: MCP only
    if (scopeAllowsTarget(options.scope, .openclaw) and (detected.openclaw or options.force)) {
        report.openclaw = try installGenericJsonConfig(allocator, home, options, .{
            .config_parts = &.{ ".openclaw", "openclaw.json" },
            .format = .mcp_servers,
        });
    }

    return report;
}

pub fn uninstallAgentConfigs(
    allocator: std.mem.Allocator,
    home: []const u8,
    options: UninstallOptions,
) !InstallReport {
    const detected = detectAgents(allocator, home);
    var report = InstallReport{ .detected = detected };

    // Claude Code
    if (scopeAllowsTarget(options.scope, .claude)) {
        report.claude = try uninstallClaudeConfig(allocator, home, options.dry_run);
    }
    if (scopeAllowsTarget(options.scope, .claude) and detected.claude) {
        const skills_dir = try std.fs.path.join(allocator, &.{ home, ".claude", "skills" });
        defer allocator.free(skills_dir);
        const removed = try removeSkills(allocator, skills_dir, options.dry_run);
        if (removed > 0) report.skills = .removed;
        try removeClaudeHooks(allocator, home, options.dry_run);
        report.hooks = .removed;
    }

    // Codex
    if (scopeAllowsTarget(options.scope, .codex)) {
        report.codex = try uninstallCodexConfig(allocator, home, options.dry_run);
    }
    if (scopeAllowsTarget(options.scope, .codex) and detected.codex) {
        const ip = try std.fs.path.join(allocator, &.{ home, ".codex", "AGENTS.md" });
        defer allocator.free(ip);
        _ = try removeInstructions(allocator, ip, options.dry_run);
    }

    // Gemini
    if (scopeAllowsTarget(options.scope, .gemini) and detected.gemini) {
        const cp = try std.fs.path.join(allocator, &.{ home, ".gemini", "settings.json" });
        defer allocator.free(cp);
        if (try removeJsonMcpEntry(allocator, cp, "mcpServers", options.dry_run)) {
            report.gemini = .removed;
        }
        try removeGeminiHooks(allocator, cp, options.dry_run);
        const ip = try std.fs.path.join(allocator, &.{ home, ".gemini", "GEMINI.md" });
        defer allocator.free(ip);
        _ = try removeInstructions(allocator, ip, options.dry_run);
    }

    // Zed
    if (scopeAllowsTarget(options.scope, .zed) and detected.zed) {
        report.zed = try uninstallZedConfig(allocator, home, options.dry_run);
    }

    // VS Code
    if (scopeAllowsTarget(options.scope, .vscode) and detected.vscode) {
        report.vscode = try uninstallVscodeConfig(allocator, home, options.dry_run);
    }

    // OpenCode
    if (scopeAllowsTarget(options.scope, .opencode) and detected.opencode) {
        const cp = try std.fs.path.join(allocator, &.{ home, ".config", "opencode", "opencode.json" });
        defer allocator.free(cp);
        if (try removeJsonMcpEntry(allocator, cp, "mcp", options.dry_run)) {
            report.opencode = .removed;
        }
        const ip = try std.fs.path.join(allocator, &.{ home, ".config", "opencode", "AGENTS.md" });
        defer allocator.free(ip);
        _ = try removeInstructions(allocator, ip, options.dry_run);
    }

    // Antigravity
    if (scopeAllowsTarget(options.scope, .antigravity) and detected.antigravity) {
        const cp = try std.fs.path.join(allocator, &.{ home, ".gemini", "antigravity", "mcp_config.json" });
        defer allocator.free(cp);
        if (try removeJsonMcpEntry(allocator, cp, "mcpServers", options.dry_run)) {
            report.antigravity = .removed;
        }
        const ip = try std.fs.path.join(allocator, &.{ home, ".gemini", "antigravity", "AGENTS.md" });
        defer allocator.free(ip);
        _ = try removeInstructions(allocator, ip, options.dry_run);
    }

    // KiloCode
    if (scopeAllowsTarget(options.scope, .kilocode) and detected.kilocode) {
        report.kilocode = try uninstallKilocodeConfig(allocator, home, options.dry_run);
        const ip = try std.fs.path.join(allocator, &.{ home, ".kilocode", "rules", "codebase-memory-mcp.md" });
        defer allocator.free(ip);
        _ = try removeInstructions(allocator, ip, options.dry_run);
    }

    // Aider
    if (scopeAllowsTarget(options.scope, .aider) and detected.aider) {
        const ip = try std.fs.path.join(allocator, &.{ home, "CONVENTIONS.md" });
        defer allocator.free(ip);
        if (try removeInstructions(allocator, ip, options.dry_run)) {
            report.aider = .removed;
        }
    }

    // OpenClaw
    if (scopeAllowsTarget(options.scope, .openclaw) and detected.openclaw) {
        const cp = try std.fs.path.join(allocator, &.{ home, ".openclaw", "openclaw.json" });
        defer allocator.free(cp);
        if (try removeJsonMcpEntry(allocator, cp, "mcpServers", options.dry_run)) {
            report.openclaw = .removed;
        }
    }

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
    const nested_path = try claudeNestedConfigPath(allocator, home);
    defer allocator.free(nested_path);
    const legacy_path = try claudeLegacyConfigPath(allocator, home);
    defer allocator.free(legacy_path);

    const nested_changed = try syncClaudeConfigPath(allocator, claude_dir, nested_path, options);
    const legacy_changed = try syncClaudeConfigPath(allocator, home, legacy_path, options);
    if (!nested_changed and !legacy_changed) return .unchanged;
    return .updated;
}

fn uninstallClaudeConfig(
    allocator: std.mem.Allocator,
    home: []const u8,
    dry_run: bool,
) !InstallReport.Action {
    const nested_path = try claudeNestedConfigPath(allocator, home);
    defer allocator.free(nested_path);
    const legacy_path = try claudeLegacyConfigPath(allocator, home);
    defer allocator.free(legacy_path);

    const nested_removed = try removeClaudeConfigPath(allocator, nested_path, dry_run);
    const legacy_removed = try removeClaudeConfigPath(allocator, legacy_path, dry_run);
    if (!nested_removed and !legacy_removed) return .skipped;
    return .removed;
}

fn syncClaudeConfigPath(
    allocator: std.mem.Allocator,
    dir_path: []const u8,
    config_path: []const u8,
    options: InstallOptions,
) !bool {
    const updated = try updateClaudeConfigJson(allocator, config_path, options.binary_path, true);
    defer allocator.free(updated);
    if (updated.len == 0) return false;
    if (options.dry_run) return true;

    try std.fs.cwd().makePath(dir_path);
    var file = try std.fs.cwd().createFile(config_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(updated);
    return true;
}

fn removeClaudeConfigPath(
    allocator: std.mem.Allocator,
    config_path: []const u8,
    dry_run: bool,
) !bool {
    const updated = try updateClaudeConfigJson(allocator, config_path, "", false);
    defer allocator.free(updated);
    if (updated.len == 0) return false;
    if (dry_run) return true;

    var file = try std.fs.cwd().createFile(config_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(updated);
    return true;
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
    const rendered = try out.toOwnedSlice(allocator);
    if (existing) |contents| {
        if (std.mem.eql(u8, contents, rendered)) {
            allocator.free(rendered);
            return allocator.dupe(u8, "");
        }
    }
    return rendered;
}

// ── Generic JSON MCP config ──────────────────────────────────────

/// JSON config format variants for different agents.
const McpConfigFormat = enum {
    /// mcpServers: { "command": path } — Claude, Gemini, Antigravity, KiloCode, OpenClaw
    mcp_servers,
    /// context_servers: { "command": path, "args": [""] } — Zed
    context_servers,
    /// servers: { "type": "stdio", "command": path } — VS Code
    vscode_servers,
    /// mcp: { "enabled": true, "type": "local", "command": [path] } — OpenCode
    opencode,
};

const GenericAgentConfig = struct {
    config_parts: []const []const u8,
    format: McpConfigFormat,
};

/// The MCP server key name in JSON config files.
/// Uses server_name ("codebase-memory-zig") consistently across all agents,
/// matching the Codex TOML section and Claude JSON configs.
const mcp_server_key = server_name;

/// Build the JSON entry value for a given format.
fn buildMcpEntry(arena: std.mem.Allocator, binary_path: []const u8, format: McpConfigFormat) !std.json.Value {
    var entry = std.json.ObjectMap.init(arena);
    switch (format) {
        .mcp_servers => {
            try entry.put(try arena.dupe(u8, "command"), .{ .string = try arena.dupe(u8, binary_path) });
        },
        .context_servers => {
            try entry.put(try arena.dupe(u8, "command"), .{ .string = try arena.dupe(u8, binary_path) });
            var args = std.json.Array.init(arena);
            try args.append(.{ .string = try arena.dupe(u8, "") });
            try entry.put(try arena.dupe(u8, "args"), .{ .array = args });
        },
        .vscode_servers => {
            try entry.put(try arena.dupe(u8, "type"), .{ .string = try arena.dupe(u8, "stdio") });
            try entry.put(try arena.dupe(u8, "command"), .{ .string = try arena.dupe(u8, binary_path) });
        },
        .opencode => {
            try entry.put(try arena.dupe(u8, "enabled"), .{ .bool = true });
            try entry.put(try arena.dupe(u8, "type"), .{ .string = try arena.dupe(u8, "local") });
            var cmd_arr = std.json.Array.init(arena);
            try cmd_arr.append(.{ .string = try arena.dupe(u8, binary_path) });
            try entry.put(try arena.dupe(u8, "command"), .{ .array = cmd_arr });
        },
    }
    return .{ .object = entry };
}

/// Get the top-level JSON key name for a given format.
fn formatKeyName(format: McpConfigFormat) []const u8 {
    return switch (format) {
        .mcp_servers => "mcpServers",
        .context_servers => "context_servers",
        .vscode_servers => "servers",
        .opencode => "mcp",
    };
}

/// Generic JSON MCP config installer.
fn installGenericJsonConfig(
    allocator: std.mem.Allocator,
    home: []const u8,
    options: InstallOptions,
    agent: GenericAgentConfig,
) !InstallReport.Action {
    const config_path = try joinHomePath(allocator, home, agent.config_parts);
    defer allocator.free(config_path);

    const updated = try updateGenericMcpJson(allocator, config_path, options.binary_path, agent.format, true);
    defer allocator.free(updated);
    if (updated.len == 0) return .unchanged;
    if (options.dry_run) return .updated;

    if (std.fs.path.dirname(config_path)) |dir| {
        try std.fs.cwd().makePath(dir);
    }
    var file = try std.fs.cwd().createFile(config_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(updated);
    return .updated;
}

/// Generic MCP entry removal from a JSON config file.
fn removeJsonMcpEntry(
    allocator: std.mem.Allocator,
    config_path: []const u8,
    key_name: []const u8,
    dry_run: bool,
) !bool {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const existing = std.fs.cwd().readFileAlloc(allocator, config_path, 10 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer allocator.free(existing);

    var parsed = std.json.parseFromSlice(std.json.Value, arena, existing, .{}) catch return false;
    defer parsed.deinit();

    if (parsed.value != .object) return false;
    const servers = parsed.value.object.getPtr(key_name) orelse return false;
    if (servers.* != .object) return false;
    if (!servers.object.orderedRemove(mcp_server_key)) return false;

    if (dry_run) return true;

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    try out.writer(allocator).print("{f}", .{std.json.fmt(parsed.value, .{ .whitespace = .indent_2 })});
    try out.append(allocator, '\n');

    var file = try std.fs.cwd().createFile(config_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(out.items);
    return true;
}

/// Generic JSON MCP config update (parameterized by format).
fn updateGenericMcpJson(
    allocator: std.mem.Allocator,
    config_path: []const u8,
    binary_path: []const u8,
    format: McpConfigFormat,
    install_entry: bool,
) ![]u8 {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const existing = std.fs.cwd().readFileAlloc(allocator, config_path, 10 * 1024 * 1024) catch |err| switch (err) {
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

    const key_name = formatKeyName(format);

    const servers_ptr = blk: {
        if (root.object.getPtr(key_name)) |existing_servers| {
            if (existing_servers.* != .object) {
                existing_servers.* = .{ .object = std.json.ObjectMap.init(arena) };
            }
            break :blk &existing_servers.*.object;
        }
        try root.object.put(try arena.dupe(u8, key_name), .{ .object = std.json.ObjectMap.init(arena) });
        break :blk &root.object.getPtr(key_name).?.*.object;
    };

    if (install_entry) {
        const entry_val = try buildMcpEntry(arena, binary_path, format);
        if (servers_ptr.getPtr(mcp_server_key)) |existing_entry| {
            existing_entry.* = entry_val;
        } else {
            try servers_ptr.put(try arena.dupe(u8, mcp_server_key), entry_val);
        }
    } else {
        if (!servers_ptr.orderedRemove(mcp_server_key)) {
            return allocator.dupe(u8, "");
        }
    }

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    try out.writer(allocator).print("{f}", .{std.json.fmt(root, .{ .whitespace = .indent_2 })});
    try out.append(allocator, '\n');
    const rendered = try out.toOwnedSlice(allocator);
    if (existing) |contents| {
        if (std.mem.eql(u8, contents, rendered)) {
            allocator.free(rendered);
            return allocator.dupe(u8, "");
        }
    }
    return rendered;
}

// ── Platform-specific agent config installers ────────────────────

fn installZedConfig(
    allocator: std.mem.Allocator,
    home: []const u8,
    options: InstallOptions,
) !InstallReport.Action {
    const config_path = try zedConfigPathForPlatform(
        allocator,
        home,
        currentConfigPlatform(),
        std.posix.getenv("APPDATA"),
        std.posix.getenv("XDG_CONFIG_HOME"),
    );
    defer allocator.free(config_path);

    const updated = try updateGenericMcpJson(allocator, config_path, options.binary_path, .context_servers, true);
    defer allocator.free(updated);
    if (updated.len == 0) return .unchanged;
    if (options.dry_run) return .updated;

    if (std.fs.path.dirname(config_path)) |dir| {
        try std.fs.cwd().makePath(dir);
    }
    var file = try std.fs.cwd().createFile(config_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(updated);
    return .updated;
}

fn uninstallZedConfig(
    allocator: std.mem.Allocator,
    home: []const u8,
    dry_run: bool,
) !InstallReport.Action {
    const config_path = try zedConfigPathForPlatform(
        allocator,
        home,
        currentConfigPlatform(),
        std.posix.getenv("APPDATA"),
        std.posix.getenv("XDG_CONFIG_HOME"),
    );
    defer allocator.free(config_path);

    if (try removeJsonMcpEntry(allocator, config_path, "context_servers", dry_run)) {
        return .removed;
    }
    return .skipped;
}

fn installVscodeConfig(
    allocator: std.mem.Allocator,
    home: []const u8,
    options: InstallOptions,
) !InstallReport.Action {
    const config_path = try vscodeConfigPathForPlatform(
        allocator,
        home,
        currentConfigPlatform(),
        std.posix.getenv("APPDATA"),
        std.posix.getenv("XDG_CONFIG_HOME"),
    );
    defer allocator.free(config_path);

    const updated = try updateGenericMcpJson(allocator, config_path, options.binary_path, .vscode_servers, true);
    defer allocator.free(updated);
    if (updated.len == 0) return .unchanged;
    if (options.dry_run) return .updated;

    if (std.fs.path.dirname(config_path)) |dir| {
        try std.fs.cwd().makePath(dir);
    }
    var file = try std.fs.cwd().createFile(config_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(updated);
    return .updated;
}

fn uninstallVscodeConfig(
    allocator: std.mem.Allocator,
    home: []const u8,
    dry_run: bool,
) !InstallReport.Action {
    const config_path = try vscodeConfigPathForPlatform(
        allocator,
        home,
        currentConfigPlatform(),
        std.posix.getenv("APPDATA"),
        std.posix.getenv("XDG_CONFIG_HOME"),
    );
    defer allocator.free(config_path);

    if (try removeJsonMcpEntry(allocator, config_path, "servers", dry_run)) {
        return .removed;
    }
    return .skipped;
}

fn installKilocodeConfig(
    allocator: std.mem.Allocator,
    home: []const u8,
    options: InstallOptions,
) !InstallReport.Action {
    const config_path = try kilocodeConfigPathForPlatform(
        allocator,
        home,
        currentConfigPlatform(),
        std.posix.getenv("APPDATA"),
        std.posix.getenv("XDG_CONFIG_HOME"),
    );
    defer allocator.free(config_path);

    const updated = try updateGenericMcpJson(allocator, config_path, options.binary_path, .mcp_servers, true);
    defer allocator.free(updated);
    if (updated.len == 0) return .unchanged;
    if (options.dry_run) return .updated;

    if (std.fs.path.dirname(config_path)) |dir| {
        try std.fs.cwd().makePath(dir);
    }
    var file = try std.fs.cwd().createFile(config_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(updated);
    return .updated;
}

fn uninstallKilocodeConfig(
    allocator: std.mem.Allocator,
    home: []const u8,
    dry_run: bool,
) !InstallReport.Action {
    const config_path = try kilocodeConfigPathForPlatform(
        allocator,
        home,
        currentConfigPlatform(),
        std.posix.getenv("APPDATA"),
        std.posix.getenv("XDG_CONFIG_HOME"),
    );
    defer allocator.free(config_path);

    if (try removeJsonMcpEntry(allocator, config_path, "mcpServers", dry_run)) {
        return .removed;
    }
    return .skipped;
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
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const path = std.fs.path.join(fba.allocator(), &.{ root, relative }) catch return false;
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn dirExists(path: []const u8) bool {
    const stat = std.fs.cwd().statFile(path) catch return false;
    return stat.kind == .directory;
}

/// Join home dir with a slice of path components.
fn joinHomePath(allocator: std.mem.Allocator, home: []const u8, parts: []const []const u8) ![]u8 {
    var result = try allocator.dupe(u8, home);
    for (parts) |part| {
        const next = try std.fs.path.join(allocator, &.{ result, part });
        allocator.free(result);
        result = next;
    }
    return result;
}

test "config roundtrip preserves values" {
    const allocator = std.testing.allocator;
    const path = try std.fmt.allocPrint(allocator, "/tmp/cbm-config-{x}.json", .{std.crypto.random.int(u64)});
    defer allocator.free(path);
    defer std.fs.cwd().deleteFile(path) catch {};

    var config = AppConfig{
        .auto_index = true,
        .auto_index_limit = 123,
        .idle_store_timeout_ms = 4321,
        .update_check_disable = true,
        .download_url = try allocator.dupe(u8, "https://example.com/cbm"),
    };
    defer config.deinit(allocator);
    try saveConfigAtPath(allocator, path, config);

    var loaded = try loadConfigAtPath(allocator, path);
    defer loaded.deinit(allocator);
    try std.testing.expect(loaded.auto_index);
    try std.testing.expectEqual(@as(usize, 123), loaded.auto_index_limit);
    try std.testing.expectEqual(@as(usize, 4321), loaded.idle_store_timeout_ms);
    try std.testing.expect(loaded.update_check_disable);
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

    const legacy_path = try std.fs.path.join(allocator, &.{ home, ".claude.json" });
    defer allocator.free(legacy_path);
    const legacy = try std.fs.cwd().readFileAlloc(allocator, legacy_path, 1024 * 1024);
    defer allocator.free(legacy);
    try std.testing.expect(std.mem.indexOf(u8, legacy, server_name) != null);

    const uninstall = try uninstallAgentConfigs(allocator, home, false);
    try std.testing.expectEqual(InstallReport.Action.removed, uninstall.claude);
    const updated = try std.fs.cwd().readFileAlloc(allocator, config_path, 1024 * 1024);
    defer allocator.free(updated);
    try std.testing.expect(std.mem.indexOf(u8, updated, server_name) == null);
    const legacy_updated = try std.fs.cwd().readFileAlloc(allocator, legacy_path, 1024 * 1024);
    defer allocator.free(legacy_updated);
    try std.testing.expect(std.mem.indexOf(u8, legacy_updated, server_name) == null);
}

test "detect agents matches supported directories" {
    const allocator = std.testing.allocator;
    const home = try std.fmt.allocPrint(allocator, "/tmp/cbm-home-detect-{x}", .{std.crypto.random.int(u64)});
    defer allocator.free(home);
    defer std.fs.cwd().deleteTree(home) catch {};

    try std.fs.cwd().makePath(home);
    var detected = detectAgents(allocator, home);
    try std.testing.expect(!detected.codex);
    try std.testing.expect(!detected.claude);

    const codex_dir = try std.fs.path.join(allocator, &.{ home, ".codex" });
    defer allocator.free(codex_dir);
    const claude_dir = try std.fs.path.join(allocator, &.{ home, ".claude" });
    defer allocator.free(claude_dir);
    try std.fs.cwd().makePath(codex_dir);
    try std.fs.cwd().makePath(claude_dir);

    detected = detectAgents(allocator, home);
    try std.testing.expect(detected.codex);
    try std.testing.expect(detected.claude);
}

test "runtime cache dir uses windows local appdata when platform is overridden" {
    const allocator = std.testing.allocator;
    const path = try runtimeCacheDirForPlatform(
        allocator,
        "/tmp/cbm-home",
        .windows,
        null,
        "C:/Users/test/AppData/Local",
        null,
    );
    defer allocator.free(path);

    try std.testing.expectEqualStrings(
        "C:/Users/test/AppData/Local/codebase-memory-zig",
        path,
    );
}

test "windows client config paths use roaming appdata roots" {
    const allocator = std.testing.allocator;

    const zed_path = try zedConfigPathForPlatform(
        allocator,
        "/tmp/cbm-home",
        .windows,
        "C:/Users/test/AppData/Roaming",
        null,
    );
    defer allocator.free(zed_path);
    try std.testing.expectEqualStrings(
        "C:/Users/test/AppData/Roaming/Zed/settings.json",
        zed_path,
    );

    const vscode_path = try vscodeConfigPathForPlatform(
        allocator,
        "/tmp/cbm-home",
        .windows,
        "C:/Users/test/AppData/Roaming",
        null,
    );
    defer allocator.free(vscode_path);
    try std.testing.expectEqualStrings(
        "C:/Users/test/AppData/Roaming/Code/User/mcp.json",
        vscode_path,
    );

    const kilocode_path = try kilocodeConfigPathForPlatform(
        allocator,
        "/tmp/cbm-home",
        .windows,
        "C:/Users/test/AppData/Roaming",
        null,
    );
    defer allocator.free(kilocode_path);
    try std.testing.expectEqualStrings(
        "C:/Users/test/AppData/Roaming/Code/User/globalStorage/kilocode.kilo-code/settings/mcp_settings.json",
        kilocode_path,
    );
}

test "install dry run preserves filesystem for supported agents" {
    const allocator = std.testing.allocator;
    const home = try std.fmt.allocPrint(allocator, "/tmp/cbm-home-dry-run-{x}", .{std.crypto.random.int(u64)});
    defer allocator.free(home);
    defer std.fs.cwd().deleteTree(home) catch {};

    const codex_dir = try std.fs.path.join(allocator, &.{ home, ".codex" });
    defer allocator.free(codex_dir);
    const claude_dir = try std.fs.path.join(allocator, &.{ home, ".claude" });
    defer allocator.free(claude_dir);
    try std.fs.cwd().makePath(codex_dir);
    try std.fs.cwd().makePath(claude_dir);

    const report = try installAgentConfigs(allocator, home, .{
        .binary_path = "/tmp/cbm",
        .dry_run = true,
    });
    try std.testing.expectEqual(InstallReport.Action.updated, report.codex);
    try std.testing.expectEqual(InstallReport.Action.updated, report.claude);

    const codex_path = try codexConfigPath(allocator, home);
    defer allocator.free(codex_path);
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().access(codex_path, .{}));

    const claude_nested = try claudeNestedConfigPath(allocator, home);
    defer allocator.free(claude_nested);
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().access(claude_nested, .{}));

    const claude_legacy = try claudeLegacyConfigPath(allocator, home);
    defer allocator.free(claude_legacy);
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().access(claude_legacy, .{}));
}

test "claude install is unchanged when both config files already match" {
    const allocator = std.testing.allocator;
    const home = try std.fmt.allocPrint(allocator, "/tmp/cbm-home-claude-unchanged-{x}", .{std.crypto.random.int(u64)});
    defer allocator.free(home);
    defer std.fs.cwd().deleteTree(home) catch {};
    const claude_dir = try std.fs.path.join(allocator, &.{ home, ".claude" });
    defer allocator.free(claude_dir);
    try std.fs.cwd().makePath(claude_dir);

    _ = try installAgentConfigs(allocator, home, .{
        .binary_path = "/tmp/cbm",
        .force = true,
    });

    const report = try installAgentConfigs(allocator, home, .{
        .binary_path = "/tmp/cbm",
        .force = true,
    });
    try std.testing.expectEqual(InstallReport.Action.unchanged, report.claude);
}

test "uninstall dry run keeps supported agent config entries" {
    const allocator = std.testing.allocator;
    const home = try std.fmt.allocPrint(allocator, "/tmp/cbm-home-uninstall-dry-{x}", .{std.crypto.random.int(u64)});
    defer allocator.free(home);
    defer std.fs.cwd().deleteTree(home) catch {};
    const codex_dir = try std.fs.path.join(allocator, &.{ home, ".codex" });
    defer allocator.free(codex_dir);
    const claude_dir = try std.fs.path.join(allocator, &.{ home, ".claude" });
    defer allocator.free(claude_dir);
    try std.fs.cwd().makePath(codex_dir);
    try std.fs.cwd().makePath(claude_dir);

    _ = try installAgentConfigs(allocator, home, .{
        .binary_path = "/tmp/cbm",
        .force = true,
    });

    const report = try uninstallAgentConfigs(allocator, home, .{ .dry_run = true });
    try std.testing.expectEqual(InstallReport.Action.removed, report.codex);
    try std.testing.expectEqual(InstallReport.Action.removed, report.claude);

    const codex_path = try codexConfigPath(allocator, home);
    defer allocator.free(codex_path);
    const codex_contents = try std.fs.cwd().readFileAlloc(allocator, codex_path, 1024 * 1024);
    defer allocator.free(codex_contents);
    try std.testing.expect(std.mem.indexOf(u8, codex_contents, server_name) != null);

    const claude_nested = try claudeNestedConfigPath(allocator, home);
    defer allocator.free(claude_nested);
    const nested_contents = try std.fs.cwd().readFileAlloc(allocator, claude_nested, 1024 * 1024);
    defer allocator.free(nested_contents);
    try std.testing.expect(std.mem.indexOf(u8, nested_contents, server_name) != null);

    const claude_legacy = try claudeLegacyConfigPath(allocator, home);
    defer allocator.free(claude_legacy);
    const legacy_contents = try std.fs.cwd().readFileAlloc(allocator, claude_legacy, 1024 * 1024);
    defer allocator.free(legacy_contents);
    try std.testing.expect(std.mem.indexOf(u8, legacy_contents, server_name) != null);
}

test "detect agents finds gemini and openclaw directories" {
    const allocator = std.testing.allocator;
    const home = try std.fmt.allocPrint(allocator, "/tmp/cbm-home-detect-new-{x}", .{std.crypto.random.int(u64)});
    defer allocator.free(home);
    defer std.fs.cwd().deleteTree(home) catch {};

    try std.fs.cwd().makePath(home);

    // Create gemini and openclaw dirs
    const gemini_dir = try std.fs.path.join(allocator, &.{ home, ".gemini" });
    defer allocator.free(gemini_dir);
    try std.fs.cwd().makePath(gemini_dir);

    const openclaw_dir = try std.fs.path.join(allocator, &.{ home, ".openclaw" });
    defer allocator.free(openclaw_dir);
    try std.fs.cwd().makePath(openclaw_dir);

    const detected = detectAgents(allocator, home);
    try std.testing.expect(detected.gemini);
    try std.testing.expect(detected.openclaw);
    try std.testing.expect(!detected.codex);
    try std.testing.expect(!detected.claude);
    try std.testing.expect(!detected.aider);
    try std.testing.expect(!detected.opencode);
}

test "detect agents antigravity implies gemini" {
    const allocator = std.testing.allocator;
    const home = try std.fmt.allocPrint(allocator, "/tmp/cbm-home-detect-ag-{x}", .{std.crypto.random.int(u64)});
    defer allocator.free(home);
    defer std.fs.cwd().deleteTree(home) catch {};

    // Create antigravity dir (nested under .gemini)
    const ag_dir = try std.fs.path.join(allocator, &.{ home, ".gemini", "antigravity" });
    defer allocator.free(ag_dir);
    try std.fs.cwd().makePath(ag_dir);

    const detected = detectAgents(allocator, home);
    try std.testing.expect(detected.antigravity);
    try std.testing.expect(detected.gemini); // implied by antigravity
}

test "skills install and remove roundtrip" {
    const allocator = std.testing.allocator;
    const skills_dir = try std.fmt.allocPrint(allocator, "/tmp/cbm-skills-{x}", .{std.crypto.random.int(u64)});
    defer allocator.free(skills_dir);
    defer std.fs.cwd().deleteTree(skills_dir) catch {};
    try std.fs.cwd().makePath(skills_dir);

    // Install
    const result = try installSkills(allocator, skills_dir, false, false);
    try std.testing.expectEqual(@as(u32, 1), result.installed);

    // Check file exists
    const file_path = try std.fs.path.join(allocator, &.{ skills_dir, skill_name, "SKILL.md" });
    defer allocator.free(file_path);
    const contents = try std.fs.cwd().readFileAlloc(allocator, file_path, 1024 * 1024);
    defer allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, "Codebase Memory") != null);

    // Install again without force = no change
    const result2 = try installSkills(allocator, skills_dir, false, false);
    try std.testing.expectEqual(@as(u32, 0), result2.installed);

    // Install with force = reinstall
    const result3 = try installSkills(allocator, skills_dir, true, false);
    try std.testing.expectEqual(@as(u32, 1), result3.installed);

    // Remove
    const removed = try removeSkills(allocator, skills_dir, false);
    try std.testing.expectEqual(@as(u32, 1), removed);
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().access(file_path, .{}));
}

test "skills install dry run does not write" {
    const allocator = std.testing.allocator;
    const skills_dir = try std.fmt.allocPrint(allocator, "/tmp/cbm-skills-dry-{x}", .{std.crypto.random.int(u64)});
    defer allocator.free(skills_dir);
    defer std.fs.cwd().deleteTree(skills_dir) catch {};
    try std.fs.cwd().makePath(skills_dir);

    const result = try installSkills(allocator, skills_dir, false, true);
    try std.testing.expectEqual(@as(u32, 1), result.installed);

    const file_path = try std.fs.path.join(allocator, &.{ skills_dir, skill_name, "SKILL.md" });
    defer allocator.free(file_path);
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().access(file_path, .{}));
}

test "skills install removes old monolithic skill dirs" {
    const allocator = std.testing.allocator;
    const skills_dir = try std.fmt.allocPrint(allocator, "/tmp/cbm-skills-old-{x}", .{std.crypto.random.int(u64)});
    defer allocator.free(skills_dir);
    defer std.fs.cwd().deleteTree(skills_dir) catch {};
    try std.fs.cwd().makePath(skills_dir);

    // Create old skill directories
    for (old_skill_names) |old_name| {
        const old_path = try std.fs.path.join(allocator, &.{ skills_dir, old_name });
        defer allocator.free(old_path);
        try std.fs.cwd().makePath(old_path);
    }

    const result = try installSkills(allocator, skills_dir, false, false);
    try std.testing.expect(result.old_removed);

    // Verify old dirs are gone
    for (old_skill_names) |old_name| {
        const old_path = try std.fs.path.join(allocator, &.{ skills_dir, old_name });
        defer allocator.free(old_path);
        try std.testing.expectError(error.FileNotFound, std.fs.cwd().access(old_path, .{}));
    }
}

test "instructions upsert creates file when missing" {
    const allocator = std.testing.allocator;
    const path = try std.fmt.allocPrint(allocator, "/tmp/cbm-instr-create-{x}.md", .{std.crypto.random.int(u64)});
    defer allocator.free(path);
    defer std.fs.cwd().deleteFile(path) catch {};

    const changed = try upsertInstructions(allocator, path, "test content\n", false);
    try std.testing.expect(changed);

    const contents = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, instr_marker_start) != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "test content") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, instr_marker_end) != null);
}

test "instructions upsert is idempotent" {
    const allocator = std.testing.allocator;
    const path = try std.fmt.allocPrint(allocator, "/tmp/cbm-instr-idem-{x}.md", .{std.crypto.random.int(u64)});
    defer allocator.free(path);
    defer std.fs.cwd().deleteFile(path) catch {};

    _ = try upsertInstructions(allocator, path, "content\n", false);
    const first = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(first);

    const changed = try upsertInstructions(allocator, path, "content\n", false);
    try std.testing.expect(!changed);

    const second = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(second);
    try std.testing.expectEqualStrings(first, second);
}

test "instructions upsert replaces existing section" {
    const allocator = std.testing.allocator;
    const path = try std.fmt.allocPrint(allocator, "/tmp/cbm-instr-replace-{x}.md", .{std.crypto.random.int(u64)});
    defer allocator.free(path);
    defer std.fs.cwd().deleteFile(path) catch {};

    _ = try upsertInstructions(allocator, path, "old content\n", false);
    const changed = try upsertInstructions(allocator, path, "new content\n", false);
    try std.testing.expect(changed);

    const contents = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, "new content") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "old content") == null);
    // Only one pair of markers
    const start_count = std.mem.count(u8, contents, instr_marker_start);
    try std.testing.expectEqual(@as(usize, 1), start_count);
}

test "instructions remove strips managed section" {
    const allocator = std.testing.allocator;
    const path = try std.fmt.allocPrint(allocator, "/tmp/cbm-instr-remove-{x}.md", .{std.crypto.random.int(u64)});
    defer allocator.free(path);
    defer std.fs.cwd().deleteFile(path) catch {};

    // Write a file with prefix + managed section
    {
        var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
        defer file.close();
        try file.writeAll("# My File\nSome content\n");
    }
    _ = try upsertInstructions(allocator, path, "managed\n", false);

    const removed = try removeInstructions(allocator, path, false);
    try std.testing.expect(removed);

    const contents = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, instr_marker_start) == null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "My File") != null);
}

test "instructions remove from nonexistent file returns false" {
    const allocator = std.testing.allocator;
    const removed = try removeInstructions(allocator, "/tmp/cbm-nonexistent-instr-file.md", false);
    try std.testing.expect(!removed);
}

test "hook json upsert creates settings with hook entry" {
    const allocator = std.testing.allocator;
    const path = try std.fmt.allocPrint(allocator, "/tmp/cbm-hooks-{x}.json", .{std.crypto.random.int(u64)});
    defer allocator.free(path);
    defer std.fs.cwd().deleteFile(path) catch {};

    const changed = try upsertHooksJson(allocator, path, "PreToolUse", "Grep|Glob", "~/.claude/hooks/test", false);
    try std.testing.expect(changed);

    const contents = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, "PreToolUse") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "Grep|Glob") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "~/.claude/hooks/test") != null);
}

test "hook json upsert replaces existing entry with same matcher" {
    const allocator = std.testing.allocator;
    const path = try std.fmt.allocPrint(allocator, "/tmp/cbm-hooks-replace-{x}.json", .{std.crypto.random.int(u64)});
    defer allocator.free(path);
    defer std.fs.cwd().deleteFile(path) catch {};

    _ = try upsertHooksJson(allocator, path, "PreToolUse", "Grep|Glob", "old-command", false);
    _ = try upsertHooksJson(allocator, path, "PreToolUse", "Grep|Glob", "new-command", false);

    const contents = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, "new-command") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "old-command") == null);
}

test "hook json remove strips entry" {
    const allocator = std.testing.allocator;
    const path = try std.fmt.allocPrint(allocator, "/tmp/cbm-hooks-rm-{x}.json", .{std.crypto.random.int(u64)});
    defer allocator.free(path);
    defer std.fs.cwd().deleteFile(path) catch {};

    _ = try upsertHooksJson(allocator, path, "PreToolUse", "Grep|Glob", "test-cmd", false);
    const removed = try removeHooksJson(allocator, path, "PreToolUse", "Grep|Glob", false);
    try std.testing.expect(removed);

    const contents = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, "Grep|Glob") == null);
}

test "hook json remove from nonexistent file returns false" {
    const allocator = std.testing.allocator;
    const removed = try removeHooksJson(allocator, "/tmp/cbm-nonexistent-hooks.json", "PreToolUse", "Grep|Glob", false);
    try std.testing.expect(!removed);
}

test "gemini install and uninstall roundtrip" {
    const allocator = std.testing.allocator;
    const home = try std.fmt.allocPrint(allocator, "/tmp/cbm-home-gemini-{x}", .{std.crypto.random.int(u64)});
    defer allocator.free(home);
    defer std.fs.cwd().deleteTree(home) catch {};

    const gemini_dir = try std.fs.path.join(allocator, &.{ home, ".gemini" });
    defer allocator.free(gemini_dir);
    try std.fs.cwd().makePath(gemini_dir);

    const report = try installAgentConfigs(allocator, home, .{
        .binary_path = "/tmp/cbm",
        .force = true,
    });
    try std.testing.expectEqual(InstallReport.Action.updated, report.gemini);

    // Check settings.json has mcpServers entry
    const settings_path = try std.fs.path.join(allocator, &.{ home, ".gemini", "settings.json" });
    defer allocator.free(settings_path);
    const contents = try std.fs.cwd().readFileAlloc(allocator, settings_path, 1024 * 1024);
    defer allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, "mcpServers") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, mcp_server_key) != null);

    // Check instructions file
    const instr_path = try std.fs.path.join(allocator, &.{ home, ".gemini", "GEMINI.md" });
    defer allocator.free(instr_path);
    const instr = try std.fs.cwd().readFileAlloc(allocator, instr_path, 1024 * 1024);
    defer allocator.free(instr);
    try std.testing.expect(std.mem.indexOf(u8, instr, instr_marker_start) != null);

    // Check hooks
    try std.testing.expect(std.mem.indexOf(u8, contents, "BeforeTool") != null);

    // Uninstall
    const uninstall = try uninstallAgentConfigs(allocator, home, .{});
    try std.testing.expectEqual(InstallReport.Action.removed, uninstall.gemini);
}

test "opencode install uses mcp key format" {
    const allocator = std.testing.allocator;
    const home = try std.fmt.allocPrint(allocator, "/tmp/cbm-home-opencode-{x}", .{std.crypto.random.int(u64)});
    defer allocator.free(home);
    defer std.fs.cwd().deleteTree(home) catch {};

    // OpenCode is PATH-detected, so use force
    const report = try installAgentConfigs(allocator, home, .{
        .binary_path = "/tmp/cbm",
        .force = true,
    });
    try std.testing.expectEqual(InstallReport.Action.updated, report.opencode);

    const config_path = try std.fs.path.join(allocator, &.{ home, ".config", "opencode", "opencode.json" });
    defer allocator.free(config_path);
    const contents = try std.fs.cwd().readFileAlloc(allocator, config_path, 1024 * 1024);
    defer allocator.free(contents);
    // OpenCode uses "mcp" key with "enabled", "type", "command" array
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"mcp\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"enabled\": true") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"local\"") != null);
}

test "openclaw install uses mcpServers format" {
    const allocator = std.testing.allocator;
    const home = try std.fmt.allocPrint(allocator, "/tmp/cbm-home-openclaw-{x}", .{std.crypto.random.int(u64)});
    defer allocator.free(home);
    defer std.fs.cwd().deleteTree(home) catch {};

    const openclaw_dir = try std.fs.path.join(allocator, &.{ home, ".openclaw" });
    defer allocator.free(openclaw_dir);
    try std.fs.cwd().makePath(openclaw_dir);

    const report = try installAgentConfigs(allocator, home, .{
        .binary_path = "/tmp/cbm",
        .force = true,
    });
    try std.testing.expectEqual(InstallReport.Action.updated, report.openclaw);

    const config_path = try std.fs.path.join(allocator, &.{ home, ".openclaw", "openclaw.json" });
    defer allocator.free(config_path);
    const contents = try std.fs.cwd().readFileAlloc(allocator, config_path, 1024 * 1024);
    defer allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, "mcpServers") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, mcp_server_key) != null);
}

test "antigravity install uses mcpServers format" {
    const allocator = std.testing.allocator;
    const home = try std.fmt.allocPrint(allocator, "/tmp/cbm-home-antigrav-{x}", .{std.crypto.random.int(u64)});
    defer allocator.free(home);
    defer std.fs.cwd().deleteTree(home) catch {};

    const ag_dir = try std.fs.path.join(allocator, &.{ home, ".gemini", "antigravity" });
    defer allocator.free(ag_dir);
    try std.fs.cwd().makePath(ag_dir);

    const report = try installAgentConfigs(allocator, home, .{
        .binary_path = "/tmp/cbm",
        .force = true,
    });
    try std.testing.expectEqual(InstallReport.Action.updated, report.antigravity);

    const config_path = try std.fs.path.join(allocator, &.{ home, ".gemini", "antigravity", "mcp_config.json" });
    defer allocator.free(config_path);
    const contents = try std.fs.cwd().readFileAlloc(allocator, config_path, 1024 * 1024);
    defer allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, "mcpServers") != null);

    // Check instructions
    const instr_path = try std.fs.path.join(allocator, &.{ home, ".gemini", "antigravity", "AGENTS.md" });
    defer allocator.free(instr_path);
    const instr = try std.fs.cwd().readFileAlloc(allocator, instr_path, 1024 * 1024);
    defer allocator.free(instr);
    try std.testing.expect(std.mem.indexOf(u8, instr, instr_marker_start) != null);
}

test "aider install is instructions only" {
    const allocator = std.testing.allocator;
    const home = try std.fmt.allocPrint(allocator, "/tmp/cbm-home-aider-{x}", .{std.crypto.random.int(u64)});
    defer allocator.free(home);
    defer std.fs.cwd().deleteTree(home) catch {};
    try std.fs.cwd().makePath(home);

    // Aider is PATH-detected, so use force
    const report = try installAgentConfigs(allocator, home, .{
        .binary_path = "/tmp/cbm",
        .force = true,
    });
    try std.testing.expectEqual(InstallReport.Action.updated, report.aider);

    // Check CONVENTIONS.md exists with instructions
    const conventions_path = try std.fs.path.join(allocator, &.{ home, "CONVENTIONS.md" });
    defer allocator.free(conventions_path);
    const contents = try std.fs.cwd().readFileAlloc(allocator, conventions_path, 1024 * 1024);
    defer allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, instr_marker_start) != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "Knowledge Graph") != null);

    // Uninstall
    const uninstall = try uninstallAgentConfigs(allocator, home, .{});
    // Aider is not detected (PATH check, not home dir), so removal is skipped
    try std.testing.expectEqual(InstallReport.Action.skipped, uninstall.aider);
}

test "claude install writes skills and hooks" {
    const allocator = std.testing.allocator;
    const home = try std.fmt.allocPrint(allocator, "/tmp/cbm-home-claude-full-{x}", .{std.crypto.random.int(u64)});
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
    try std.testing.expectEqual(InstallReport.Action.updated, report.skills);
    try std.testing.expectEqual(InstallReport.Action.updated, report.hooks);

    // Skills file exists
    const skill_path = try std.fs.path.join(allocator, &.{ home, ".claude", "skills", skill_name, "SKILL.md" });
    defer allocator.free(skill_path);
    std.fs.cwd().access(skill_path, .{}) catch |err| {
        std.debug.print("skill path not found: {s}\n", .{skill_path});
        return err;
    };

    // Hook scripts exist
    const gate_path = try std.fs.path.join(allocator, &.{ home, ".claude", "hooks", "cbm-code-discovery-gate" });
    defer allocator.free(gate_path);
    std.fs.cwd().access(gate_path, .{}) catch |err| {
        std.debug.print("gate script not found: {s}\n", .{gate_path});
        return err;
    };

    const reminder_path = try std.fs.path.join(allocator, &.{ home, ".claude", "hooks", "cbm-session-reminder" });
    defer allocator.free(reminder_path);
    std.fs.cwd().access(reminder_path, .{}) catch |err| {
        std.debug.print("reminder script not found: {s}\n", .{reminder_path});
        return err;
    };

    // Settings.json has hook entries
    const settings_path = try std.fs.path.join(allocator, &.{ home, ".claude", "settings.json" });
    defer allocator.free(settings_path);
    const settings = try std.fs.cwd().readFileAlloc(allocator, settings_path, 1024 * 1024);
    defer allocator.free(settings);
    try std.testing.expect(std.mem.indexOf(u8, settings, "PreToolUse") != null);
    try std.testing.expect(std.mem.indexOf(u8, settings, "SessionStart") != null);
}

test "install scope shipped skips non-shipped agents even with force" {
    const allocator = std.testing.allocator;
    const home = try std.fmt.allocPrint(allocator, "/tmp/cbm-home-scope-shipped-{x}", .{std.crypto.random.int(u64)});
    defer allocator.free(home);
    defer std.fs.cwd().deleteTree(home) catch {};

    const gemini_dir = try std.fs.path.join(allocator, &.{ home, ".gemini" });
    defer allocator.free(gemini_dir);
    try std.fs.cwd().makePath(gemini_dir);

    const report = try installAgentConfigs(allocator, home, .{
        .binary_path = "/tmp/cbm",
        .force = true,
        .scope = .shipped,
    });
    try std.testing.expectEqual(InstallReport.Action.updated, report.codex);
    try std.testing.expectEqual(InstallReport.Action.updated, report.claude);
    try std.testing.expectEqual(InstallReport.Action.skipped, report.gemini);

    const gemini_settings = try std.fs.path.join(allocator, &.{ home, ".gemini", "settings.json" });
    defer allocator.free(gemini_settings);
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().access(gemini_settings, .{}));
}

test "generic mcp json formats produce correct structure" {
    const allocator = std.testing.allocator;

    // Test VS Code format (servers + type:stdio)
    {
        const path = try std.fmt.allocPrint(allocator, "/tmp/cbm-vscode-{x}.json", .{std.crypto.random.int(u64)});
        defer allocator.free(path);
        defer std.fs.cwd().deleteFile(path) catch {};

        const updated = try updateGenericMcpJson(allocator, path, "/usr/bin/cbm", .vscode_servers, true);
        defer allocator.free(updated);
        try std.testing.expect(updated.len > 0);
        try std.testing.expect(std.mem.indexOf(u8, updated, "\"servers\"") != null);
        try std.testing.expect(std.mem.indexOf(u8, updated, "\"stdio\"") != null);
    }

    // Test context_servers format (Zed)
    {
        const path = try std.fmt.allocPrint(allocator, "/tmp/cbm-zed-{x}.json", .{std.crypto.random.int(u64)});
        defer allocator.free(path);
        defer std.fs.cwd().deleteFile(path) catch {};

        const updated = try updateGenericMcpJson(allocator, path, "/usr/bin/cbm", .context_servers, true);
        defer allocator.free(updated);
        try std.testing.expect(updated.len > 0);
        try std.testing.expect(std.mem.indexOf(u8, updated, "\"context_servers\"") != null);
        try std.testing.expect(std.mem.indexOf(u8, updated, "\"args\"") != null);
    }

    // Test OpenCode format (mcp + enabled + local + command array)
    {
        const path = try std.fmt.allocPrint(allocator, "/tmp/cbm-opencode-{x}.json", .{std.crypto.random.int(u64)});
        defer allocator.free(path);
        defer std.fs.cwd().deleteFile(path) catch {};

        const updated = try updateGenericMcpJson(allocator, path, "/usr/bin/cbm", .opencode, true);
        defer allocator.free(updated);
        try std.testing.expect(updated.len > 0);
        try std.testing.expect(std.mem.indexOf(u8, updated, "\"mcp\"") != null);
        try std.testing.expect(std.mem.indexOf(u8, updated, "\"enabled\": true") != null);
        try std.testing.expect(std.mem.indexOf(u8, updated, "\"local\"") != null);
    }
}

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
/// macOS: home/Library/Application Support, Linux: home/.config
fn appConfigPrefix(allocator: std.mem.Allocator, home: []const u8) ?[]u8 {
    const builtin = @import("builtin");
    return switch (builtin.os.tag) {
        .macos => std.fs.path.join(allocator, &.{ home, "Library", "Application Support" }) catch null,
        else => std.fs.path.join(allocator, &.{ home, ".config" }) catch null,
    };
}

pub fn detectAgents(allocator: std.mem.Allocator, home: []const u8) AgentSet {
    var agents = AgentSet{};

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

        // Zed: macOS ~/Library/Application Support/Zed, Linux ~/.config/zed
        const builtin = @import("builtin");
        const zed_sub = if (builtin.os.tag == .macos) "Zed" else "zed";
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

pub fn installAgentConfigs(
    allocator: std.mem.Allocator,
    home: []const u8,
    options: InstallOptions,
) !InstallReport {
    const detected = detectAgents(allocator, home);
    var report = InstallReport{ .detected = detected };

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
    var report = InstallReport{ .detected = detectAgents(allocator, home) };
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

    const report = try uninstallAgentConfigs(allocator, home, true);
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

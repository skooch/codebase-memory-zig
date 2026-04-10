// store.zig — SQLite graph store for code knowledge graphs.
//
// Provides a small CRUD layer used by the pipeline and MCP tools.

const std = @import("std");
const c = @cImport(@cInclude("sqlite3.h"));

pub const StoreError = error{
    OpenFailed,
    SqlError,
    NotFound,
};

pub const Node = struct {
    id: i64 = 0,
    project: []const u8 = "",
    label: []const u8 = "",
    name: []const u8 = "",
    qualified_name: []const u8 = "",
    file_path: []const u8 = "",
    start_line: i32 = 0,
    end_line: i32 = 0,
    properties_json: []const u8 = "{}",
};

pub const Edge = struct {
    id: i64 = 0,
    project: []const u8 = "",
    source_id: i64 = 0,
    target_id: i64 = 0,
    edge_type: []const u8 = "",
    properties_json: []const u8 = "{}",
};

pub const Project = struct {
    name: []const u8,
    indexed_at: []const u8 = "",
    root_path: []const u8 = "",
};

pub const ProjectStatus = struct {
    project: []const u8,
    indexed_at: []const u8 = "",
    root_path: []const u8 = "",
    nodes: i32 = 0,
    edges: i32 = 0,
    status: Status,

    pub const Status = enum {
        ready,
        empty,
        no_project,
        not_found,
    };
};

pub const NodeDegree = struct {
    callers: i32 = 0,
    callees: i32 = 0,
};

pub const NodeSearchFilter = struct {
    project: []const u8 = "",
    label_pattern: ?[]const u8 = null,
    name_pattern: ?[]const u8 = null,
    qn_pattern: ?[]const u8 = null,
    file_pattern: ?[]const u8 = null,
    limit: usize = 100,
};

pub const TraversalDirection = enum {
    outbound,
    inbound,
    both,
};

pub const TraversalEdge = struct {
    id: i64 = 0,
    project: []const u8 = "",
    source_id: i64 = 0,
    target_id: i64 = 0,
    edge_type: []const u8 = "",
    properties_json: []const u8 = "{}",
    depth: u32 = 0,
};

pub const SchemaSummary = struct {
    labels: []const LabelCount,
    edge_types: []const EdgeTypeCount,
    languages: []const LanguageCount,
};

pub const LabelCount = struct { label: []const u8, count: i64 };
pub const EdgeTypeCount = struct { edge_type: []const u8, count: i64 };
pub const LanguageCount = struct { language: []const u8, count: i64 };

pub const Store = struct {
    db: ?*c.sqlite3 = null,
    allocator: std.mem.Allocator,

    pub fn openMemory(allocator: std.mem.Allocator) StoreError!Store {
        var db: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open(":memory:", &db);
        if (rc != c.SQLITE_OK) {
            if (db) |d| _ = c.sqlite3_close(d);
            return StoreError.OpenFailed;
        }
        var s = Store{ .db = db, .allocator = allocator };
        try s.configurePragmas();
        try s.createSchema();
        return s;
    }

    pub fn openPath(allocator: std.mem.Allocator, path: [*:0]const u8) StoreError!Store {
        var db: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open(path, &db);
        if (rc != c.SQLITE_OK) {
            if (db) |d| _ = c.sqlite3_close(d);
            return StoreError.OpenFailed;
        }
        var s = Store{ .db = db, .allocator = allocator };
        try s.configurePragmas();
        try s.createSchema();
        return s;
    }

    pub fn deinit(self: *Store) void {
        if (self.db) |db| {
            _ = c.sqlite3_close(db);
            self.db = null;
        }
    }

    // --- Schema / lifecycle ------------------------------------------------

    fn configurePragmas(self: *Store) !void {
        const pragmas = [_][*:0]const u8{
            "PRAGMA foreign_keys = ON",
            "PRAGMA journal_mode = WAL",
            "PRAGMA synchronous = NORMAL",
            "PRAGMA temp_store = MEMORY",
            "PRAGMA busy_timeout = 10000",
            "PRAGMA mmap_size = 67108864",
        };
        for (pragmas) |sql| {
            try self.exec(sql);
        }
    }

    fn createSchema(self: *Store) !void {
        const ddl = [_][*:0]const u8{
            "CREATE TABLE IF NOT EXISTS projects (" ++
                "name TEXT PRIMARY KEY, " ++
                "indexed_at TEXT, " ++
                "root_path TEXT" ++
                ")",
            "CREATE TABLE IF NOT EXISTS nodes (" ++
                "id INTEGER PRIMARY KEY AUTOINCREMENT, " ++
                "project TEXT NOT NULL REFERENCES projects(name) ON DELETE CASCADE, " ++
                "label TEXT NOT NULL, " ++
                "name TEXT NOT NULL, " ++
                "qualified_name TEXT NOT NULL, " ++
                "file_path TEXT DEFAULT '', " ++
                "start_line INTEGER DEFAULT 0, " ++
                "end_line INTEGER DEFAULT 0, " ++
                "properties TEXT DEFAULT '{}', " ++
                "UNIQUE(project, qualified_name)" ++
                ")",
            "CREATE TABLE IF NOT EXISTS edges (" ++
                "id INTEGER PRIMARY KEY AUTOINCREMENT, " ++
                "project TEXT NOT NULL REFERENCES projects(name) ON DELETE CASCADE, " ++
                "source_id INTEGER NOT NULL REFERENCES nodes(id) ON DELETE CASCADE, " ++
                "target_id INTEGER NOT NULL REFERENCES nodes(id) ON DELETE CASCADE, " ++
                "type TEXT NOT NULL, " ++
                "properties TEXT DEFAULT '{}', " ++
                "UNIQUE(source_id, target_id, type, project)" ++
                ")",
            "CREATE TABLE IF NOT EXISTS file_hashes (" ++
                "project TEXT NOT NULL REFERENCES projects(name) ON DELETE CASCADE, " ++
                "rel_path TEXT NOT NULL, " ++
                "sha256 TEXT NOT NULL, " ++
                "mtime_ns INTEGER DEFAULT 0, " ++
                "size INTEGER DEFAULT 0, " ++
                "PRIMARY KEY (project, rel_path)" ++
                ")",
            "CREATE INDEX IF NOT EXISTS idx_nodes_label ON nodes(project, label)",
            "CREATE INDEX IF NOT EXISTS idx_nodes_name ON nodes(project, name)",
            "CREATE INDEX IF NOT EXISTS idx_nodes_file ON nodes(project, file_path)",
            "CREATE INDEX IF NOT EXISTS idx_nodes_qn ON nodes(project, qualified_name)",
            "CREATE INDEX IF NOT EXISTS idx_edges_source ON edges(project, source_id)",
            "CREATE INDEX IF NOT EXISTS idx_edges_target ON edges(project, target_id)",
            "CREATE INDEX IF NOT EXISTS idx_edges_type ON edges(project, type)",
        };
        for (ddl) |sql| {
            try self.exec(sql);
        }
    }

    // --- Project CRUD -----------------------------------------------------

    pub fn upsertProject(self: *Store, name: []const u8, root_path: []const u8) !void {
        var now_buf: [64]u8 = undefined;
        const now = std.time.timestamp();
        const indexed_at = std.fmt.bufPrint(&now_buf, "{d}", .{now}) catch "0";

        const stmt = try self.prepare(
            "INSERT INTO projects(name, indexed_at, root_path) VALUES(?1, ?2, ?3) " ++
                "ON CONFLICT(name) DO UPDATE SET indexed_at = excluded.indexed_at, root_path = excluded.root_path",
        );
        defer self.finalize(stmt);

        try self.bindText(stmt, 1, name);
        try self.bindText(stmt, 2, indexed_at);
        try self.bindText(stmt, 3, root_path);
        try self.stepDone(stmt);
    }

    pub fn getProject(self: *Store, name: []const u8) !?Project {
        const stmt = try self.prepare(
            "SELECT name, indexed_at, root_path FROM projects WHERE name = ?1 LIMIT 1",
        );
        defer self.finalize(stmt);

        try self.bindText(stmt, 1, name);
        const rc = c.sqlite3_step(stmt);
        if (rc == c.SQLITE_DONE) {
            return null;
        }
        if (rc != c.SQLITE_ROW) return StoreError.SqlError;

        const result = Project{
            .name = try self.copyColumnText(stmt, 0),
            .indexed_at = try self.copyColumnText(stmt, 1),
            .root_path = try self.copyColumnText(stmt, 2),
        };
        return result;
    }

    pub fn listProjects(self: *Store) ![]Project {
        const stmt = try self.prepare("SELECT name, indexed_at, root_path FROM projects ORDER BY name");
        defer self.finalize(stmt);

        var out = std.ArrayList(Project).empty;
        while (true) {
            const rc = c.sqlite3_step(stmt);
            if (rc == c.SQLITE_DONE) break;
            if (rc != c.SQLITE_ROW) return StoreError.SqlError;
            try out.append(self.allocator, .{
                .name = try self.copyColumnText(stmt, 0),
                .indexed_at = try self.copyColumnText(stmt, 1),
                .root_path = try self.copyColumnText(stmt, 2),
            });
        }
        return out.toOwnedSlice(self.allocator);
    }

    pub fn freeProject(self: *Store, project: Project) void {
        self.allocator.free(project.name);
        self.allocator.free(project.indexed_at);
        self.allocator.free(project.root_path);
    }

    pub fn freeProjects(self: *Store, projects: []Project) void {
        for (projects) |p| {
            self.freeProject(p);
        }
        self.allocator.free(projects);
    }

    pub fn deleteProject(self: *Store, name: []const u8) !void {
        const stmt = try self.prepare("DELETE FROM projects WHERE name = ?1");
        defer self.finalize(stmt);
        try self.bindText(stmt, 1, name);
        _ = try self.stepNoResult(stmt);
    }

    pub fn getProjectStatus(self: *Store, name: ?[]const u8) !ProjectStatus {
        if (name == null or name.?.len == 0) {
            return .{
                .project = try self.allocator.dupe(u8, ""),
                .status = .no_project,
            };
        }

        const project_name = name.?;
        const project = try self.getProject(project_name);
        if (project == null) {
            return .{
                .project = try self.allocator.dupe(u8, project_name),
                .status = .not_found,
            };
        }

        const owned_project = project.?;
        errdefer self.freeProject(owned_project);
        const node_count = try self.countNodes(project_name);
        const edge_count = try self.countEdges(project_name);
        return .{
            .project = owned_project.name,
            .indexed_at = owned_project.indexed_at,
            .root_path = owned_project.root_path,
            .nodes = node_count,
            .edges = edge_count,
            .status = if (node_count > 0) .ready else .empty,
        };
    }

    pub fn freeProjectStatus(self: *Store, status: ProjectStatus) void {
        self.allocator.free(status.project);
        self.allocator.free(status.indexed_at);
        self.allocator.free(status.root_path);
    }

    // --- Node CRUD -------------------------------------------------------

    pub fn upsertNode(self: *Store, node: Node) !i64 {
        const stmt = try self.prepare(
            "INSERT INTO nodes(project, label, name, qualified_name, file_path, start_line, end_line, properties) " ++
                "VALUES(?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8) " ++
                "ON CONFLICT(project, qualified_name) DO UPDATE SET " ++
                "label = excluded.label, name = excluded.name, file_path = excluded.file_path, " ++
                "start_line = excluded.start_line, end_line = excluded.end_line, properties = excluded.properties",
        );
        defer self.finalize(stmt);

        try self.bindText(stmt, 1, node.project);
        try self.bindText(stmt, 2, node.label);
        try self.bindText(stmt, 3, node.name);
        try self.bindText(stmt, 4, node.qualified_name);
        try self.bindText(stmt, 5, node.file_path);
        try self.bindInt(stmt, 6, node.start_line);
        try self.bindInt(stmt, 7, node.end_line);
        try self.bindText(stmt, 8, node.properties_json);
        _ = try self.stepNoResult(stmt);

        return try self.findNodeId(node.project, node.qualified_name) orelse 0;
    }

    pub fn findNodeByQualifiedName(self: *Store, project: []const u8, qualified_name: []const u8) !?Node {
        const stmt = try self.prepare(
            "SELECT id, project, label, name, qualified_name, file_path, start_line, end_line, properties " ++
                "FROM nodes WHERE project = ?1 AND qualified_name = ?2 LIMIT 1",
        );
        defer self.finalize(stmt);
        try self.bindText(stmt, 1, project);
        try self.bindText(stmt, 2, qualified_name);

        const rc = c.sqlite3_step(stmt);
        if (rc == c.SQLITE_DONE) return null;
        if (rc != c.SQLITE_ROW) return StoreError.SqlError;
        return try self.rowToNode(stmt);
    }

    pub fn findNodeById(self: *Store, project: []const u8, node_id: i64) !?Node {
        const stmt = try self.prepare(
            "SELECT id, project, label, name, qualified_name, file_path, start_line, end_line, properties " ++
                "FROM nodes WHERE project = ?1 AND id = ?2 LIMIT 1",
        );
        defer self.finalize(stmt);
        try self.bindText(stmt, 1, project);
        try self.bindInt(stmt, 2, node_id);

        const rc = c.sqlite3_step(stmt);
        if (rc == c.SQLITE_DONE) return null;
        if (rc != c.SQLITE_ROW) return StoreError.SqlError;
        return try self.rowToNode(stmt);
    }

    pub fn findNodeId(self: *Store, project: []const u8, qualified_name: []const u8) !?i64 {
        const stmt = try self.prepare("SELECT id FROM nodes WHERE project = ?1 AND qualified_name = ?2 LIMIT 1");
        defer self.finalize(stmt);
        try self.bindText(stmt, 1, project);
        try self.bindText(stmt, 2, qualified_name);
        const rc = c.sqlite3_step(stmt);
        if (rc == c.SQLITE_DONE) return null;
        if (rc != c.SQLITE_ROW) return StoreError.SqlError;
        const id = c.sqlite3_column_int64(stmt, 0);
        return id;
    }

    pub fn findNodesByQualifiedNameSuffix(
        self: *Store,
        project: []const u8,
        qualified_name_suffix: []const u8,
        limit: usize,
    ) ![]Node {
        const stmt = try self.prepare(
            "SELECT id, project, label, name, qualified_name, file_path, start_line, end_line, properties " ++
                "FROM nodes WHERE project = ?1 AND qualified_name LIKE ?2 ORDER BY qualified_name ASC LIMIT ?3",
        );
        defer self.finalize(stmt);

        const suffix_like = try std.fmt.allocPrint(self.allocator, "%{s}", .{qualified_name_suffix});
        defer self.allocator.free(suffix_like);

        try self.bindText(stmt, 1, project);
        try self.bindText(stmt, 2, suffix_like);
        try self.bindInt(stmt, 3, @as(i64, @intCast(if (limit == 0) 25 else limit)));

        var out = std.ArrayList(Node).empty;
        while (true) {
            const rc = c.sqlite3_step(stmt);
            if (rc == c.SQLITE_DONE) break;
            if (rc != c.SQLITE_ROW) return StoreError.SqlError;
            try out.append(self.allocator, try self.rowToNode(stmt));
        }
        return out.toOwnedSlice(self.allocator);
    }

    pub fn searchNodes(self: *Store, filter: NodeSearchFilter) ![]Node {
        var sql = std.ArrayList(u8).empty;
        defer sql.deinit(self.allocator);

        var binds = std.ArrayList([]const u8).empty;
        defer {
            for (binds.items) |b| {
                self.allocator.free(b);
            }
            binds.deinit(self.allocator);
        }
        try sql.appendSlice(
            self.allocator,
            "SELECT id, project, label, name, qualified_name, file_path, start_line, end_line, properties " ++
                "FROM nodes WHERE 1=1",
        );

        if (filter.project.len > 0) {
            try sql.appendSlice(self.allocator, " AND project = ?1");
        } else {
            try sql.appendSlice(self.allocator, "");
        }

        if (filter.label_pattern) |pat| {
            try sql.appendSlice(self.allocator, if (filter.project.len > 0) " AND label LIKE ?" else " AND label LIKE ?");
            try binds.append(self.allocator, try toLike(self.allocator, pat));
        }
        if (filter.name_pattern) |pat| {
            try sql.appendSlice(self.allocator, " AND name LIKE ?");
            try binds.append(self.allocator, try toLike(self.allocator, pat));
        }
        if (filter.qn_pattern) |pat| {
            try sql.appendSlice(self.allocator, " AND qualified_name LIKE ?");
            try binds.append(self.allocator, try toLike(self.allocator, pat));
        }
        if (filter.file_pattern) |pat| {
            try sql.appendSlice(self.allocator, " AND file_path LIKE ?");
            try binds.append(self.allocator, try toLike(self.allocator, pat));
        }

        try sql.appendSlice(self.allocator, " ORDER BY name ASC");
        try sql.appendSlice(self.allocator, " LIMIT ?");

        const stmt = try self.prepare(sql.items);
        defer self.finalize(stmt);

        const limit = if (filter.limit == 0) 100 else filter.limit;
        var bind_index: u32 = 1;
        if (filter.project.len > 0) {
            try self.bindText(stmt, @as(c_int, @intCast(bind_index)), filter.project);
            bind_index += 1;
        }
        for (binds.items) |b| {
            try self.bindText(stmt, @as(c_int, @intCast(bind_index)), b);
            bind_index += 1;
        }
        try self.bindInt(stmt, @as(c_int, @intCast(bind_index)), @as(i64, @intCast(limit)));

        var out = std.ArrayList(Node).empty;
        while (true) {
            const rc = c.sqlite3_step(stmt);
            if (rc == c.SQLITE_DONE) break;
            if (rc != c.SQLITE_ROW) {
                return StoreError.SqlError;
            }
            try out.append(self.allocator, try self.rowToNode(stmt));
        }
        return out.toOwnedSlice(self.allocator);
    }

    pub fn freeNodes(self: *Store, nodes: []Node) void {
        for (nodes) |n| {
            self.freeNode(n);
        }
        self.allocator.free(nodes);
    }

    pub fn freeNode(self: *Store, node: Node) void {
        self.allocator.free(node.project);
        self.allocator.free(node.label);
        self.allocator.free(node.name);
        self.allocator.free(node.qualified_name);
        self.allocator.free(node.file_path);
        self.allocator.free(node.properties_json);
    }

    pub fn countNodes(self: *Store, project: []const u8) !i32 {
        const stmt = try self.prepare("SELECT COUNT(*) FROM nodes WHERE project = ?1");
        defer self.finalize(stmt);
        try self.bindText(stmt, 1, project);
        const rc = c.sqlite3_step(stmt);
        if (rc != c.SQLITE_ROW) return StoreError.SqlError;
        return @intCast(c.sqlite3_column_int64(stmt, 0));
    }

    // --- Edge CRUD -------------------------------------------------------

    pub fn upsertEdge(self: *Store, edge: Edge) !i64 {
        const stmt = try self.prepare(
            "INSERT INTO edges(project, source_id, target_id, type, properties) " ++
                "VALUES(?1, ?2, ?3, ?4, ?5) " ++
                "ON CONFLICT(project, source_id, target_id, type) DO UPDATE SET properties = excluded.properties",
        );
        defer self.finalize(stmt);

        try self.bindText(stmt, 1, edge.project);
        try self.bindInt(stmt, 2, edge.source_id);
        try self.bindInt(stmt, 3, edge.target_id);
        try self.bindText(stmt, 4, edge.edge_type);
        try self.bindText(stmt, 5, edge.properties_json);
        _ = try self.stepNoResult(stmt);

        const id_stmt = try self.prepare(
            "SELECT id FROM edges WHERE project = ?1 AND source_id = ?2 AND target_id = ?3 AND type = ?4 LIMIT 1",
        );
        defer self.finalize(id_stmt);
        try self.bindText(id_stmt, 1, edge.project);
        try self.bindInt(id_stmt, 2, edge.source_id);
        try self.bindInt(id_stmt, 3, edge.target_id);
        try self.bindText(id_stmt, 4, edge.edge_type);
        const rc = c.sqlite3_step(id_stmt);
        if (rc != c.SQLITE_ROW) return StoreError.SqlError;
        return c.sqlite3_column_int64(id_stmt, 0);
    }

    pub fn findEdgesBySource(
        self: *Store,
        project: []const u8,
        source_id: i64,
        edge_type: ?[]const u8,
    ) ![]Edge {
        const sql = if (edge_type) |_|
            "SELECT id, project, source_id, target_id, type, properties FROM edges WHERE project = ?1 AND source_id = ?2 AND type = ?3 ORDER BY id"
        else
            "SELECT id, project, source_id, target_id, type, properties FROM edges WHERE project = ?1 AND source_id = ?2 ORDER BY id";

        const stmt = try self.prepare(sql);
        defer self.finalize(stmt);
        try self.bindText(stmt, 1, project);
        try self.bindInt(stmt, 2, source_id);
        if (edge_type) |et| {
            try self.bindText(stmt, 3, et);
        }

        var out = std.ArrayList(Edge).empty;
        while (true) {
            const rc = c.sqlite3_step(stmt);
            if (rc == c.SQLITE_DONE) break;
            if (rc != c.SQLITE_ROW) return StoreError.SqlError;
            try out.append(self.allocator, try self.rowToEdge(stmt));
        }
        return out.toOwnedSlice(self.allocator);
    }

    pub fn findEdgesByTarget(
        self: *Store,
        project: []const u8,
        target_id: i64,
        edge_type: ?[]const u8,
    ) ![]Edge {
        const sql = if (edge_type) |_|
            "SELECT id, project, source_id, target_id, type, properties FROM edges WHERE project = ?1 AND target_id = ?2 AND type = ?3 ORDER BY id"
        else
            "SELECT id, project, source_id, target_id, type, properties FROM edges WHERE project = ?1 AND target_id = ?2 ORDER BY id";

        const stmt = try self.prepare(sql);
        defer self.finalize(stmt);
        try self.bindText(stmt, 1, project);
        try self.bindInt(stmt, 2, target_id);
        if (edge_type) |et| {
            try self.bindText(stmt, 3, et);
        }

        var out = std.ArrayList(Edge).empty;
        while (true) {
            const rc = c.sqlite3_step(stmt);
            if (rc == c.SQLITE_DONE) break;
            if (rc != c.SQLITE_ROW) return StoreError.SqlError;
            try out.append(self.allocator, try self.rowToEdge(stmt));
        }
        return out.toOwnedSlice(self.allocator);
    }

    pub fn findEdgeBetween(self: *Store, project: []const u8, source_id: i64, target_id: i64, edge_type: []const u8) !?Edge {
        const stmt = try self.prepare(
            "SELECT id, project, source_id, target_id, type, properties FROM edges " ++
                "WHERE project = ?1 AND source_id = ?2 AND target_id = ?3 AND type = ?4 LIMIT 1",
        );
        defer self.finalize(stmt);
        try self.bindText(stmt, 1, project);
        try self.bindInt(stmt, 2, source_id);
        try self.bindInt(stmt, 3, target_id);
        try self.bindText(stmt, 4, edge_type);

        const rc = c.sqlite3_step(stmt);
        if (rc == c.SQLITE_DONE) return null;
        if (rc != c.SQLITE_ROW) return StoreError.SqlError;
        return try self.rowToEdge(stmt);
    }

    pub fn freeEdges(self: *Store, edges: []Edge) void {
        for (edges) |e| {
            self.allocator.free(e.project);
            self.allocator.free(e.edge_type);
            self.allocator.free(e.properties_json);
        }
        self.allocator.free(edges);
    }

    pub fn countEdges(self: *Store, project: []const u8) !i32 {
        const stmt = try self.prepare("SELECT COUNT(*) FROM edges WHERE project = ?1");
        defer self.finalize(stmt);
        try self.bindText(stmt, 1, project);
        const rc = c.sqlite3_step(stmt);
        if (rc != c.SQLITE_ROW) return StoreError.SqlError;
        return @intCast(c.sqlite3_column_int64(stmt, 0));
    }

    pub fn getNodeDegree(self: *Store, project: []const u8, node_id: i64) !NodeDegree {
        const callers_stmt = try self.prepare("SELECT COUNT(*) FROM edges WHERE project = ?1 AND target_id = ?2");
        defer self.finalize(callers_stmt);
        try self.bindText(callers_stmt, 1, project);
        try self.bindInt(callers_stmt, 2, node_id);
        if (c.sqlite3_step(callers_stmt) != c.SQLITE_ROW) return StoreError.SqlError;

        const callees_stmt = try self.prepare("SELECT COUNT(*) FROM edges WHERE project = ?1 AND source_id = ?2");
        defer self.finalize(callees_stmt);
        try self.bindText(callees_stmt, 1, project);
        try self.bindInt(callees_stmt, 2, node_id);
        if (c.sqlite3_step(callees_stmt) != c.SQLITE_ROW) return StoreError.SqlError;

        return .{
            .callers = @intCast(c.sqlite3_column_int64(callers_stmt, 0)),
            .callees = @intCast(c.sqlite3_column_int64(callees_stmt, 0)),
        };
    }

    pub fn traverseEdgesBreadthFirst(
        self: *Store,
        project: []const u8,
        start_node_id: i64,
        direction: TraversalDirection,
        max_depth: u32,
        edge_type: ?[]const u8,
    ) ![]TraversalEdge {
        var frontier = std.ArrayList(struct { id: i64, depth: u32 }).empty;
        defer frontier.deinit(self.allocator);

        var visited = std.AutoHashMap(i64, void).init(self.allocator);
        defer visited.deinit();

        var seen_edges = std.AutoHashMap(i64, void).init(self.allocator);
        defer seen_edges.deinit();

        var out = std.ArrayList(TraversalEdge).empty;
        errdefer {
            self.freeTraversalEdgeItems(out.items);
            out.deinit(self.allocator);
        }

        try frontier.append(self.allocator, .{ .id = start_node_id, .depth = 0 });
        try visited.put(start_node_id, {});

        while (frontier.items.len > 0) {
            const next = frontier.orderedRemove(0);
            const next_depth = next.depth + 1;
            if (next_depth > max_depth) continue;

            if (direction == .outbound or direction == .both) {
                const outgoing = try self.findEdgesBySource(project, next.id, edge_type);
                defer self.freeEdges(outgoing);

                for (outgoing) |edge| {
                    try self.collectTraversalEdge(&out, &seen_edges, edge, next_depth);
                    if (!visited.contains(edge.target_id)) {
                        try visited.put(edge.target_id, {});
                        try frontier.append(self.allocator, .{ .id = edge.target_id, .depth = next_depth });
                    }
                }
            }

            if (direction == .inbound or direction == .both) {
                const incoming = try self.findEdgesByTarget(project, next.id, edge_type);
                defer self.freeEdges(incoming);

                for (incoming) |edge| {
                    try self.collectTraversalEdge(&out, &seen_edges, edge, next_depth);
                    if (!visited.contains(edge.source_id)) {
                        try visited.put(edge.source_id, {});
                        try frontier.append(self.allocator, .{ .id = edge.source_id, .depth = next_depth });
                    }
                }
            }
        }

        return out.toOwnedSlice(self.allocator);
    }

    pub fn freeTraversalEdges(self: *Store, edges: []TraversalEdge) void {
        self.freeTraversalEdgeItems(edges);
        self.allocator.free(edges);
    }

    pub fn getSchema(self: *Store, project: []const u8) !SchemaSummary {
        var labels = std.ArrayList(LabelCount).empty;
        var edge_types = std.ArrayList(EdgeTypeCount).empty;
        var languages = std.ArrayList(LanguageCount).empty;

        const labels_stmt = try self.prepare(
            "SELECT label, COUNT(*) FROM nodes WHERE project = ?1 GROUP BY label ORDER BY COUNT(*) DESC, label",
        );
        defer self.finalize(labels_stmt);
        try self.bindText(labels_stmt, 1, project);
        while (true) {
            const rc = c.sqlite3_step(labels_stmt);
            if (rc == c.SQLITE_DONE) break;
            if (rc != c.SQLITE_ROW) return StoreError.SqlError;
            try labels.append(self.allocator, .{
                .label = try self.copyColumnText(labels_stmt, 0),
                .count = c.sqlite3_column_int64(labels_stmt, 1),
            });
        }

        const types_stmt = try self.prepare(
            "SELECT type, COUNT(*) FROM edges WHERE project = ?1 GROUP BY type ORDER BY COUNT(*) DESC, type",
        );
        defer self.finalize(types_stmt);
        try self.bindText(types_stmt, 1, project);
        while (true) {
            const rc = c.sqlite3_step(types_stmt);
            if (rc == c.SQLITE_DONE) break;
            if (rc != c.SQLITE_ROW) return StoreError.SqlError;
            try edge_types.append(self.allocator, .{
                .edge_type = try self.copyColumnText(types_stmt, 0),
                .count = c.sqlite3_column_int64(types_stmt, 1),
            });
        }

        const lang_stmt = try self.prepare(
            "SELECT label, COUNT(*) FROM nodes WHERE project = ?1 GROUP BY label ORDER BY COUNT(*) DESC LIMIT 25",
        );
        defer self.finalize(lang_stmt);
        try self.bindText(lang_stmt, 1, project);
        // Language extraction placeholder: node labels stand in for language here.
        while (true) {
            const rc = c.sqlite3_step(lang_stmt);
            if (rc == c.SQLITE_DONE) break;
            if (rc != c.SQLITE_ROW) return StoreError.SqlError;
            try languages.append(self.allocator, .{
                .language = try self.copyColumnText(lang_stmt, 0),
                .count = c.sqlite3_column_int64(lang_stmt, 1),
            });
        }

        return SchemaSummary{
            .labels = try labels.toOwnedSlice(self.allocator),
            .edge_types = try edge_types.toOwnedSlice(self.allocator),
            .languages = try languages.toOwnedSlice(self.allocator),
        };
    }

    pub fn freeSchema(self: *Store, schema: SchemaSummary) void {
        for (schema.labels) |label| {
            self.allocator.free(label.label);
        }
        for (schema.edge_types) |et| {
            self.allocator.free(et.edge_type);
        }
        for (schema.languages) |lang| {
            self.allocator.free(lang.language);
        }
        self.allocator.free(schema.labels);
        self.allocator.free(schema.edge_types);
        self.allocator.free(schema.languages);
    }

    // --- Internal helpers -----------------------------------------------

    fn prepare(self: *Store, sql: []const u8) !*c.sqlite3_stmt {
        const sql_c = try self.allocator.dupeZ(u8, sql);
        defer self.allocator.free(sql_c);

        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(self.db, sql_c.ptr, -1, &stmt, null);
        if (rc != c.SQLITE_OK or stmt == null) {
            return StoreError.SqlError;
        }
        return stmt.?;
    }

    fn finalize(self: *Store, stmt: *c.sqlite3_stmt) void {
        _ = c.sqlite3_finalize(stmt);
        _ = self;
    }

    fn bindText(_: *Store, stmt: *c.sqlite3_stmt, idx: c_int, text: []const u8) !void {
        const rc = c.sqlite3_bind_text(stmt, idx, text.ptr, @intCast(text.len), null);
        if (rc != c.SQLITE_OK) return StoreError.SqlError;
    }

    fn bindInt(self: *Store, stmt: *c.sqlite3_stmt, idx: c_int, value: i64) !void {
        _ = self;
        const rc = c.sqlite3_bind_int64(stmt, idx, value);
        if (rc != c.SQLITE_OK) return StoreError.SqlError;
    }

    fn stepNoResult(self: *Store, stmt: *c.sqlite3_stmt) !i32 {
        _ = self;
        const rc = c.sqlite3_step(stmt);
        if (rc == c.SQLITE_DONE or rc == c.SQLITE_ROW) return rc;
        return StoreError.SqlError;
    }

    fn stepDone(self: *Store, stmt: *c.sqlite3_stmt) !void {
        _ = try self.stepNoResult(stmt);
    }

    fn copyColumnText(self: *Store, stmt: *c.sqlite3_stmt, idx: c_int) ![]u8 {
        const raw = c.sqlite3_column_text(stmt, idx);
        if (raw == null) return self.allocator.dupe(u8, "");
        const len = c.sqlite3_column_bytes(stmt, idx);
        return self.allocator.dupe(u8, raw[0..@intCast(len)]);
    }

    fn rowToNode(self: *Store, stmt: *c.sqlite3_stmt) !Node {
        return Node{
            .id = c.sqlite3_column_int64(stmt, 0),
            .project = try self.copyColumnText(stmt, 1),
            .label = try self.copyColumnText(stmt, 2),
            .name = try self.copyColumnText(stmt, 3),
            .qualified_name = try self.copyColumnText(stmt, 4),
            .file_path = try self.copyColumnText(stmt, 5),
            .start_line = @intCast(c.sqlite3_column_int(stmt, 6)),
            .end_line = @intCast(c.sqlite3_column_int(stmt, 7)),
            .properties_json = try self.copyColumnText(stmt, 8),
        };
    }

    fn rowToEdge(self: *Store, stmt: *c.sqlite3_stmt) !Edge {
        return Edge{
            .id = c.sqlite3_column_int64(stmt, 0),
            .project = try self.copyColumnText(stmt, 1),
            .source_id = c.sqlite3_column_int64(stmt, 2),
            .target_id = c.sqlite3_column_int64(stmt, 3),
            .edge_type = try self.copyColumnText(stmt, 4),
            .properties_json = try self.copyColumnText(stmt, 5),
        };
    }

    fn collectTraversalEdge(
        self: *Store,
        out: *std.ArrayList(TraversalEdge),
        seen_edges: *std.AutoHashMap(i64, void),
        edge: Edge,
        depth: u32,
    ) !void {
        if (seen_edges.contains(edge.id)) return;

        try seen_edges.put(edge.id, {});
        errdefer _ = seen_edges.remove(edge.id);

        try out.append(self.allocator, try self.duplicateTraversalEdge(edge, depth));
    }

    fn duplicateTraversalEdge(self: *Store, edge: Edge, depth: u32) !TraversalEdge {
        const project = try self.allocator.dupe(u8, edge.project);
        errdefer self.allocator.free(project);
        const edge_type = try self.allocator.dupe(u8, edge.edge_type);
        errdefer self.allocator.free(edge_type);
        const properties_json = try self.allocator.dupe(u8, edge.properties_json);

        return .{
            .id = edge.id,
            .project = project,
            .source_id = edge.source_id,
            .target_id = edge.target_id,
            .edge_type = edge_type,
            .properties_json = properties_json,
            .depth = depth,
        };
    }

    fn freeTraversalEdgeItems(self: *Store, edges: []TraversalEdge) void {
        for (edges) |edge| {
            self.allocator.free(edge.project);
            self.allocator.free(edge.edge_type);
            self.allocator.free(edge.properties_json);
        }
    }

    fn exec(self: *Store, sql: [*:0]const u8) !void {
        var err_msg: [*c]u8 = null;
        const rc = c.sqlite3_exec(self.db, sql, null, null, &err_msg);
        if (rc != c.SQLITE_OK) {
            if (err_msg) |msg| c.sqlite3_free(msg);
            return StoreError.SqlError;
        }
    }
};

fn toLike(allocator: std.mem.Allocator, pattern: []const u8) ![]u8 {
    if (pattern.len == 0) return try allocator.dupe(u8, "%");
    if (pattern.len == 1 and pattern[0] == '*') {
        return try allocator.dupe(u8, "%");
    }
    if (std.mem.containsAtLeast(u8, pattern, 1, "%") or
        std.mem.containsAtLeast(u8, pattern, 1, "_") or
        std.mem.containsAtLeast(u8, pattern, 1, "*"))
    {
        return try allocator.dupe(u8, pattern);
    }
    return try std.fmt.allocPrint(allocator, "%{s}%", .{pattern});
}

test "store open and basic node/edge operations" {
    var s = try Store.openMemory(std.testing.allocator);
    defer s.deinit();

    try s.upsertProject("p1", "/tmp/p1");
    const p = (try s.getProject("p1")).?;
    try std.testing.expectEqualStrings("p1", p.name);
    try std.testing.expectEqualStrings("/tmp/p1", p.root_path);
    defer s.freeProject(p);

    const node1_id = try s.upsertNode(.{
        .project = "p1",
        .label = "File",
        .name = "main",
        .qualified_name = "p1:main",
        .file_path = "src/main.rs",
        .start_line = 1,
        .end_line = 1,
    });
    try std.testing.expect(node1_id > 0);
    const node2_id = try s.upsertNode(.{
        .project = "p1",
        .label = "Function",
        .name = "run",
        .qualified_name = "p1:run",
        .file_path = "src/main.rs",
        .start_line = 5,
        .end_line = 20,
    });
    try std.testing.expect(node2_id > 0);

    const edge_id = try s.upsertEdge(.{
        .project = "p1",
        .source_id = node1_id,
        .target_id = node2_id,
        .edge_type = "CONTAINS",
    });
    try std.testing.expect(edge_id > 0);

    const by_qn = try s.findNodeByQualifiedName("p1", "p1:run");
    try std.testing.expect(by_qn != null);
    if (by_qn) |n| {
        try std.testing.expectEqualStrings("run", n.name);
        s.allocator.free(n.project);
        s.allocator.free(n.label);
        s.allocator.free(n.name);
        s.allocator.free(n.qualified_name);
        s.allocator.free(n.file_path);
        s.allocator.free(n.properties_json);
    }

    const contains = try s.findEdgesBySource("p1", node1_id, "CONTAINS");
    try std.testing.expectEqual(@as(usize, 1), contains.len);
    s.freeEdges(contains);

    const nodes = try s.searchNodes(.{
        .project = "p1",
        .name_pattern = "run",
    });
    try std.testing.expectEqual(@as(usize, 1), nodes.len);
    s.freeNodes(nodes);
}

test "store breadth-first traversal reuses shared edge traversal logic" {
    var s = try Store.openMemory(std.testing.allocator);
    defer s.deinit();

    try s.upsertProject("p2", "/tmp/p2");

    const start_id = try s.upsertNode(.{
        .project = "p2",
        .label = "Function",
        .name = "start",
        .qualified_name = "p2:start",
        .file_path = "src/main.zig",
    });
    const middle_id = try s.upsertNode(.{
        .project = "p2",
        .label = "Function",
        .name = "middle",
        .qualified_name = "p2:middle",
        .file_path = "src/main.zig",
    });
    const end_id = try s.upsertNode(.{
        .project = "p2",
        .label = "Function",
        .name = "end",
        .qualified_name = "p2:end",
        .file_path = "src/main.zig",
    });
    const helper_id = try s.upsertNode(.{
        .project = "p2",
        .label = "Function",
        .name = "helper",
        .qualified_name = "p2:helper",
        .file_path = "src/main.zig",
    });

    _ = try s.upsertEdge(.{
        .project = "p2",
        .source_id = start_id,
        .target_id = middle_id,
        .edge_type = "CALLS",
    });
    _ = try s.upsertEdge(.{
        .project = "p2",
        .source_id = middle_id,
        .target_id = end_id,
        .edge_type = "CALLS",
    });
    _ = try s.upsertEdge(.{
        .project = "p2",
        .source_id = helper_id,
        .target_id = middle_id,
        .edge_type = "REFERENCES",
    });

    const outbound = try s.traverseEdgesBreadthFirst("p2", start_id, .outbound, 2, "CALLS");
    defer s.freeTraversalEdges(outbound);
    try std.testing.expectEqual(@as(usize, 2), outbound.len);
    try std.testing.expectEqual(@as(i64, start_id), outbound[0].source_id);
    try std.testing.expectEqual(@as(i64, middle_id), outbound[0].target_id);
    try std.testing.expectEqual(@as(u32, 1), outbound[0].depth);
    try std.testing.expectEqual(@as(i64, middle_id), outbound[1].source_id);
    try std.testing.expectEqual(@as(i64, end_id), outbound[1].target_id);
    try std.testing.expectEqual(@as(u32, 2), outbound[1].depth);

    const inbound = try s.traverseEdgesBreadthFirst("p2", middle_id, .inbound, 1, null);
    defer s.freeTraversalEdges(inbound);
    try std.testing.expectEqual(@as(usize, 2), inbound.len);

    const both = try s.traverseEdgesBreadthFirst("p2", middle_id, .both, 1, null);
    defer s.freeTraversalEdges(both);
    try std.testing.expectEqual(@as(usize, 3), both.len);
}

test "store project status and suffix helpers support phase 3 tools" {
    var s = try Store.openMemory(std.testing.allocator);
    defer s.deinit();

    const no_project = try s.getProjectStatus(null);
    defer s.freeProjectStatus(no_project);
    try std.testing.expectEqual(ProjectStatus.Status.no_project, no_project.status);

    const missing = try s.getProjectStatus("missing");
    defer s.freeProjectStatus(missing);
    try std.testing.expectEqual(ProjectStatus.Status.not_found, missing.status);
    try std.testing.expectEqualStrings("missing", missing.project);

    try s.upsertProject("phase3", "/tmp/phase3");
    const run_id = try s.upsertNode(.{
        .project = "phase3",
        .label = "Function",
        .name = "run",
        .qualified_name = "phase3.main.run",
        .file_path = "src/main.py",
    });
    const helper_id = try s.upsertNode(.{
        .project = "phase3",
        .label = "Function",
        .name = "helper",
        .qualified_name = "phase3.helpers.helper",
        .file_path = "src/helpers.py",
    });
    _ = try s.upsertEdge(.{
        .project = "phase3",
        .source_id = run_id,
        .target_id = helper_id,
        .edge_type = "CALLS",
    });

    const status = try s.getProjectStatus("phase3");
    defer s.freeProjectStatus(status);
    try std.testing.expectEqual(ProjectStatus.Status.ready, status.status);
    try std.testing.expectEqual(@as(i32, 2), status.nodes);
    try std.testing.expectEqual(@as(i32, 1), status.edges);
    try std.testing.expectEqualStrings("/tmp/phase3", status.root_path);

    const suffix = try s.findNodesByQualifiedNameSuffix("phase3", "main.run", 10);
    defer s.freeNodes(suffix);
    try std.testing.expectEqual(@as(usize, 1), suffix.len);
    try std.testing.expectEqualStrings("phase3.main.run", suffix[0].qualified_name);

    const degree = try s.getNodeDegree("phase3", run_id);
    try std.testing.expectEqual(@as(i32, 0), degree.callers);
    try std.testing.expectEqual(@as(i32, 1), degree.callees);
}

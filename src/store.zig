// store.zig — SQLite graph store for code knowledge graphs.
//
// All graph data (nodes, edges, projects) lives in SQLite. The Store
// provides an opaque interface: callers never touch SQLite internals.
//
// Thread safety: a single Store handle must not be used concurrently.
// Use one store per thread or external synchronisation.

const std = @import("std");
const c = @cImport(@cInclude("sqlite3.h"));

pub const StoreError = error{
    OpenFailed,
    SqlError,
    NotFound,
    IntegrityError,
};

// -- Data types ---------------------------------------------------------------

pub const Node = struct {
    id: i64 = 0,
    project: []const u8 = "",
    label: []const u8 = "", // Function, Class, Method, Module, File, ...
    name: []const u8 = "", // short name
    qualified_name: []const u8 = "", // full dotted path
    file_path: []const u8 = "", // relative file path
    start_line: i32 = 0,
    end_line: i32 = 0,
    properties_json: []const u8 = "{}",
};

pub const Edge = struct {
    id: i64 = 0,
    project: []const u8 = "",
    source_id: i64 = 0,
    target_id: i64 = 0,
    edge_type: []const u8 = "", // CALLS, IMPORTS, HTTP_CALLS, ...
    properties_json: []const u8 = "{}",
};

pub const Project = struct {
    name: []const u8,
    indexed_at: []const u8 = "",
    root_path: []const u8 = "",
};

// -- Store handle -------------------------------------------------------------

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
        s.configurePragmas() catch return StoreError.SqlError;
        s.createSchema() catch return StoreError.SqlError;
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
        s.configurePragmas() catch return StoreError.SqlError;
        s.createSchema() catch return StoreError.SqlError;
        return s;
    }

    pub fn close(self: *Store) void {
        if (self.db) |db| {
            _ = c.sqlite3_close(db);
            self.db = null;
        }
    }

    pub fn deinit(self: *Store) void {
        self.close();
    }

    // -- Schema ---------------------------------------------------------------

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
                "UNIQUE(source_id, target_id, type)" ++
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
            "CREATE INDEX IF NOT EXISTS idx_edges_source ON edges(source_id, type)",
            "CREATE INDEX IF NOT EXISTS idx_edges_target ON edges(target_id, type)",
            "CREATE INDEX IF NOT EXISTS idx_edges_type ON edges(project, type)",
        };
        for (ddl) |sql| {
            try self.exec(sql);
        }
    }

    // -- Project CRUD ---------------------------------------------------------

    pub fn upsertProject(self: *Store, name: [*:0]const u8, root_path: [*:0]const u8) !void {
        _ = root_path;
        _ = name;
        _ = self;
        // TODO: implement with prepared statement
    }

    // -- Node CRUD ------------------------------------------------------------

    pub fn countNodes(self: *Store, project: [*:0]const u8) !i32 {
        _ = project;
        _ = self;
        // TODO: implement
        return 0;
    }

    // -- Edge CRUD ------------------------------------------------------------

    pub fn countEdges(self: *Store, project: [*:0]const u8) !i32 {
        _ = project;
        _ = self;
        // TODO: implement
        return 0;
    }

    // -- Helpers --------------------------------------------------------------

    fn exec(self: *Store, sql: [*:0]const u8) !void {
        var err_msg: [*c]u8 = null;
        const rc = c.sqlite3_exec(self.db, sql, null, null, &err_msg);
        if (rc != c.SQLITE_OK) {
            if (err_msg) |msg| c.sqlite3_free(msg);
            return StoreError.SqlError;
        }
    }
};

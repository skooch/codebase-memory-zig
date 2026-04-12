const std = @import("std");
const store = @import("store.zig");

const max_overlay_bytes = 2 * 1024 * 1024;
const overlay_rel_path = ".codebase-memory/scip.json";

const Overlay = struct {
    version: []const u8 = "0.1",
    source: []const u8 = "scip",
    documents: []const Document = &.{},
};

const Document = struct {
    rel_path: []const u8,
    language: []const u8 = "",
    symbols: []const Symbol = &.{},
    occurrences: []const Occurrence = &.{},
};

const Symbol = struct {
    symbol: []const u8 = "",
    qualified_name: []const u8 = "",
    display_name: []const u8 = "",
    kind: []const u8 = "symbol",
    start_line: i32 = 0,
    end_line: i32 = 0,
    properties_json: []const u8 = "{}",
};

const Occurrence = struct {
    symbol: []const u8,
    role: []const u8 = "reference",
    start_line: i32 = 0,
    end_line: i32 = 0,
};

pub fn importProjectOverlay(
    allocator: std.mem.Allocator,
    db: *store.Store,
    project: []const u8,
    repo_path: []const u8,
) !usize {
    try db.clearScipOverlay(project);

    const path = try std.fs.path.join(allocator, &.{ repo_path, overlay_rel_path });
    defer allocator.free(path);

    const bytes = std.fs.cwd().readFileAlloc(allocator, path, max_overlay_bytes) catch |err| switch (err) {
        error.FileNotFound => return 0,
        else => return err,
    };
    defer allocator.free(bytes);

    const parsed = try std.json.parseFromSlice(Overlay, allocator, bytes, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    var imported: usize = 0;
    for (parsed.value.documents) |document| {
        try db.insertScipDocument(project, document.rel_path, document.language);
        for (document.symbols) |symbol| {
            try db.insertScipSymbol(.{
                .project = project,
                .symbol = normalizedSymbolKey(symbol),
                .qualified_name = normalizedQualifiedName(symbol),
                .display_name = normalizedDisplayName(symbol),
                .kind = symbol.kind,
                .file_path = document.rel_path,
                .start_line = symbol.start_line,
                .end_line = normalizedEndLine(symbol),
                .properties_json = normalizedProperties(symbol),
            });
            imported += 1;
        }
        for (document.occurrences) |occurrence| {
            try db.insertScipOccurrence(.{
                .project = project,
                .file_path = document.rel_path,
                .symbol = occurrence.symbol,
                .role = occurrence.role,
                .start_line = occurrence.start_line,
                .end_line = normalizedOccurrenceEndLine(occurrence),
            });
        }
    }

    return imported;
}

pub fn labelForKind(kind: []const u8) []const u8 {
    if (std.ascii.eqlIgnoreCase(kind, "function")) return "Function";
    if (std.ascii.eqlIgnoreCase(kind, "method")) return "Method";
    if (std.ascii.eqlIgnoreCase(kind, "class")) return "Class";
    if (std.ascii.eqlIgnoreCase(kind, "interface")) return "Interface";
    if (std.ascii.eqlIgnoreCase(kind, "trait")) return "Trait";
    if (std.ascii.eqlIgnoreCase(kind, "enum")) return "Enum";
    if (std.ascii.eqlIgnoreCase(kind, "struct")) return "Class";
    if (std.ascii.eqlIgnoreCase(kind, "module")) return "Module";
    if (std.ascii.eqlIgnoreCase(kind, "variable")) return "Variable";
    return "Symbol";
}

fn normalizedSymbolKey(symbol: Symbol) []const u8 {
    if (symbol.symbol.len > 0) return symbol.symbol;
    if (symbol.qualified_name.len > 0) return symbol.qualified_name;
    if (symbol.display_name.len > 0) return symbol.display_name;
    return "symbol";
}

fn normalizedQualifiedName(symbol: Symbol) []const u8 {
    if (symbol.qualified_name.len > 0) return symbol.qualified_name;
    if (symbol.display_name.len > 0) return symbol.display_name;
    return normalizedSymbolKey(symbol);
}

fn normalizedDisplayName(symbol: Symbol) []const u8 {
    if (symbol.display_name.len > 0) return symbol.display_name;
    if (symbol.qualified_name.len > 0) {
        if (std.mem.lastIndexOfScalar(u8, symbol.qualified_name, '.')) |idx| {
            return symbol.qualified_name[idx + 1 ..];
        }
        return symbol.qualified_name;
    }
    return normalizedSymbolKey(symbol);
}

fn normalizedEndLine(symbol: Symbol) i32 {
    if (symbol.end_line >= symbol.start_line) return symbol.end_line;
    return symbol.start_line;
}

fn normalizedOccurrenceEndLine(occurrence: Occurrence) i32 {
    if (occurrence.end_line >= occurrence.start_line) return occurrence.end_line;
    return occurrence.start_line;
}

fn normalizedProperties(symbol: Symbol) []const u8 {
    if (symbol.properties_json.len > 0) return symbol.properties_json;
    return "{}";
}

test "importProjectOverlay stores normalized SCIP sidecar data" {
    const allocator = std.testing.allocator;
    const repo_dir = try std.fmt.allocPrint(allocator, "/tmp/cbm-scip-{x}", .{std.crypto.random.int(u64)});
    defer allocator.free(repo_dir);
    try std.fs.cwd().makePath(repo_dir);
    defer std.fs.cwd().deleteTree(repo_dir) catch {};

    const overlay_dir = try std.fs.path.join(allocator, &.{ repo_dir, ".codebase-memory" });
    defer allocator.free(overlay_dir);
    try std.fs.cwd().makePath(overlay_dir);

    const overlay_path = try std.fs.path.join(allocator, &.{ repo_dir, overlay_rel_path });
    defer allocator.free(overlay_path);
    const overlay_contents =
        \\{
        \\  "version": "0.1",
        \\  "source": "scip",
        \\  "documents": [
        \\    {
        \\      "rel_path": "src/main.ts",
        \\      "language": "typescript",
        \\      "symbols": [
        \\        {
        \\          "symbol": "scip-typescript pkg main()",
        \\          "qualified_name": "demo.main",
        \\          "display_name": "main",
        \\          "kind": "function",
        \\          "start_line": 1,
        \\          "end_line": 3
        \\        }
        \\      ],
        \\      "occurrences": [
        \\        {
        \\          "symbol": "scip-typescript pkg main()",
        \\          "role": "definition",
        \\          "start_line": 1,
        \\          "end_line": 3
        \\        }
        \\      ]
        \\    }
        \\  ]
        \\}
    ;
    var overlay_file = try std.fs.cwd().createFile(overlay_path, .{});
    defer overlay_file.close();
    try overlay_file.writeAll(overlay_contents);

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();
    try db.upsertProject("demo", repo_dir);

    const imported = try importProjectOverlay(allocator, &db, "demo", repo_dir);
    try std.testing.expectEqual(@as(usize, 1), imported);

    const symbol = (try db.findScipSymbolByQualifiedName("demo", "demo.main")).?;
    defer db.freeScipSymbol(symbol);
    try std.testing.expectEqualStrings("main", symbol.display_name);
    try std.testing.expectEqualStrings("src/main.ts", symbol.file_path);

    const file_symbols = try db.findScipSymbolsByFile("demo", "src/main.ts");
    defer db.freeScipSymbols(file_symbols);
    try std.testing.expectEqual(@as(usize, 1), file_symbols.len);
}

test "importProjectOverlay is optional when no sidecar exists" {
    const allocator = std.testing.allocator;
    const repo_dir = try std.fmt.allocPrint(allocator, "/tmp/cbm-scip-missing-{x}", .{std.crypto.random.int(u64)});
    defer allocator.free(repo_dir);
    try std.fs.cwd().makePath(repo_dir);
    defer std.fs.cwd().deleteTree(repo_dir) catch {};

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();
    try db.upsertProject("demo", repo_dir);

    const imported = try importProjectOverlay(allocator, &db, "demo", repo_dir);
    try std.testing.expectEqual(@as(usize, 0), imported);
}

test "fixture-backed SCIP overlay imports repository sidecar" {
    const allocator = std.testing.allocator;
    const repo_dir = "testdata/interop/scip";

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();
    try db.upsertProject("scip", repo_dir);

    const imported = try importProjectOverlay(allocator, &db, "scip", repo_dir);
    try std.testing.expectEqual(@as(usize, 2), imported);

    const symbol = (try db.findScipSymbolByQualifiedName("scip", "interop.scip.renderMessage")).?;
    defer db.freeScipSymbol(symbol);
    try std.testing.expectEqualStrings("renderMessage", symbol.display_name);
}

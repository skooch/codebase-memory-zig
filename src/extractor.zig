// extractor.zig — Heuristic extraction stage.
//
// Current phase: create file/module nodes and discover best-effort:
// - symbol declarations for Rust/Zig/Python/JS-family languages
// - import targets
// - direct call candidates
// - inheritance/implements hints

const std = @import("std");
const discover = @import("discover.zig");
const graph_buffer = @import("graph_buffer.zig");

const ParsedSymbol = struct {
    label: []const u8,
    name: []const u8,
};

pub const ExtractedSymbol = struct {
    id: i64,
    label: []const u8,
    name: []const u8,
    qualified_name: []const u8,
    file_path: []const u8,
};

pub const UnresolvedCall = struct {
    caller_id: i64,
    callee_name: []const u8,
    file_path: []const u8,
};

pub const UnresolvedImport = struct {
    importer_id: i64,
    import_name: []const u8,
    file_path: []const u8,
};

pub const SemanticHint = struct {
    child_id: i64,
    parent_name: []const u8,
    file_path: []const u8,
    relation: []const u8,
};

pub const FileExtraction = struct {
    file_path: []const u8,
    file_id: i64,
    module_id: i64,
    language: discover.Language,
    symbols: []ExtractedSymbol,
    unresolved_calls: []UnresolvedCall,
    unresolved_imports: []UnresolvedImport,
    semantic_hints: []SemanticHint,
};

pub fn extractFile(
    allocator: std.mem.Allocator,
    project_name: []const u8,
    file: discover.FileInfo,
    gb: *graph_buffer.GraphBuffer,
) !FileExtraction {
    const rel = file.rel_path;
    const file_name = std.fs.path.basename(rel);
    const stem = std.fs.path.stem(file_name);

    var symbols = std.ArrayList(ExtractedSymbol).init(allocator);
    var unresolved_calls = std.ArrayList(UnresolvedCall).init(allocator);
    var unresolved_imports = std.ArrayList(UnresolvedImport).init(allocator);
    var semantic_hints = std.ArrayList(SemanticHint).init(allocator);
    var has_owned = false;

    errdefer if (!has_owned) {
        freeExtractedSymbols(allocator, symbols.items);
        freeUnresolvedCalls(allocator, unresolved_calls.items);
        freeUnresolvedImports(allocator, unresolved_imports.items);
        freeSemanticHints(allocator, semantic_hints.items);
    };

    const qn_base = try normalizePath(allocator, rel);
    defer allocator.free(qn_base);

    const file_qn = try std.fmt.allocPrint(
        allocator,
        "{s}:file:{s}:{s}",
        .{ project_name, qn_base, @tagName(file.language) },
    );
    defer allocator.free(file_qn);

    const file_id = try gb.upsertNode(
        "File",
        file_name,
        file_qn,
        rel,
        1,
        1,
    );
    if (file_id == 0) {
        has_owned = true;
        return .{
            .file_path = try allocator.dupe(u8, rel),
            .file_id = 0,
            .module_id = 0,
            .language = file.language,
            .symbols = try symbols.toOwnedSlice(),
            .unresolved_calls = try unresolved_calls.toOwnedSlice(),
            .unresolved_imports = try unresolved_imports.toOwnedSlice(),
            .semantic_hints = try semantic_hints.toOwnedSlice(),
        };
    }

    var module_id: i64 = file_id;
    var current_scope_id: i64 = file_id;
    if (stem.len > 0) {
        const module_qn = try std.fmt.allocPrint(
            allocator,
            "{s}:module:{s}:{s}",
            .{ project_name, qn_base, @tagName(file.language) },
        );
        defer allocator.free(module_qn);

        const created_module = try gb.upsertNode(
            "Module",
            stem,
            module_qn,
            rel,
            1,
            1,
        );
        if (created_module > 0) {
            module_id = created_module;
            _ = gb.insertEdge(file_id, module_id, "CONTAINS") catch |err| switch (err) {
                graph_buffer.GraphBufferError.DuplicateEdge => {},
                else => return err,
            };
            current_scope_id = module_id;
        }
    }

    const bytes = std.fs.cwd().readFileAlloc(allocator, file.path, 8 * 1024 * 1024) catch |err| switch (err) {
        error.IsDir => {
            has_owned = true;
            return .{
                .file_path = try allocator.dupe(u8, rel),
                .file_id = file_id,
                .module_id = module_id,
                .language = file.language,
                .symbols = try symbols.toOwnedSlice(),
                .unresolved_calls = try unresolved_calls.toOwnedSlice(),
                .unresolved_imports = try unresolved_imports.toOwnedSlice(),
                .semantic_hints = try semantic_hints.toOwnedSlice(),
            };
        },
        else => return err,
    };
    defer allocator.free(bytes);

    var lines = std.mem.splitAny(u8, bytes, "\n\r");
    var line_no: i32 = 1;
    while (lines.next()) |line_raw| : (line_no += 1) {
        const line = std.mem.trim(u8, line_raw, " \t");
        if (line.len == 0) continue;

        const clean_line = stripComments(file.language, line);
        if (clean_line.len == 0) continue;

        if (parseSymbol(file.language, clean_line)) |sym| {
            const symbol_qn = try std.fmt.allocPrint(
                allocator,
                "{s}:{s}:{s}:symbol:{s}:{s}",
                .{ project_name, qn_base, @tagName(file.language), @tagName(file.language), sym.name },
            );
            const symbol_id = try gb.upsertNode(
                sym.label,
                sym.name,
                symbol_qn,
                rel,
                line_no,
                line_no,
            );
            if (symbol_id > 0 and gb.findNodeById(module_id) != null) {
                _ = gb.insertEdge(module_id, symbol_id, "CONTAINS") catch |err| switch (err) {
                    graph_buffer.GraphBufferError.DuplicateEdge => {},
                    else => {
                        allocator.free(symbol_qn);
                        return err;
                    },
                };
                try symbols.append(.{
                    .id = symbol_id,
                    .label = try allocator.dupe(u8, sym.label),
                    .name = try allocator.dupe(u8, sym.name),
                    .qualified_name = try allocator.dupe(u8, symbol_qn),
                    .file_path = try allocator.dupe(u8, rel),
                });
                current_scope_id = symbol_id;
            }
            allocator.free(symbol_qn);
        }

        try parseImports(
            allocator,
            file.language,
            clean_line,
            current_scope_id,
            rel,
            &unresolved_imports,
        );

        if (parseSemanticHint(file.language, clean_line)) |hint| {
            if (current_scope_id != 0) {
                try semantic_hints.append(.{
                    .child_id = current_scope_id,
                    .parent_name = try allocator.dupe(u8, hint.parent_name),
                    .file_path = try allocator.dupe(u8, rel),
                    .relation = try allocator.dupe(u8, hint.relation),
                });
            }
        }

        const callee_names = collectCalls(allocator, clean_line, file.language) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => null,
        };
        if (callee_names) |names| {
            defer freeStringSlices(allocator, names);
            for (names) |callee| {
                if (callee.len == 0) continue;
                const caller_id = if (current_scope_id != 0) current_scope_id else module_id;
                try unresolved_calls.append(.{
                    .caller_id = caller_id,
                    .callee_name = try allocator.dupe(u8, callee),
                    .file_path = try allocator.dupe(u8, rel),
                });
            }
        }
    }

    has_owned = true;
    return .{
        .file_path = try allocator.dupe(u8, rel),
        .file_id = file_id,
        .module_id = module_id,
        .language = file.language,
        .symbols = try symbols.toOwnedSlice(),
        .unresolved_calls = try unresolved_calls.toOwnedSlice(),
        .unresolved_imports = try unresolved_imports.toOwnedSlice(),
        .semantic_hints = try semantic_hints.toOwnedSlice(),
    };
}

fn parseImports(
    allocator: std.mem.Allocator,
    language: discover.Language,
    line: []const u8,
    importer_id: i64,
    file_path: []const u8,
    out: *std.ArrayList(UnresolvedImport),
) !void {
    switch (language) {
        .python => try parsePythonImports(allocator, line, importer_id, file_path, out),
        .javascript, .typescript, .tsx => try parseJsImports(allocator, line, importer_id, file_path, out),
        .rust => try parseRustImports(allocator, line, importer_id, file_path, out),
        .zig => try parseZigImports(allocator, line, importer_id, file_path, out),
        else => {},
    }
}

fn parsePythonImports(
    allocator: std.mem.Allocator,
    line: []const u8,
    importer_id: i64,
    file_path: []const u8,
    out: *std.ArrayList(UnresolvedImport),
) !void {
    const trimmed = std.mem.trim(u8, line, " \t");
    const import_pos = std.mem.indexOf(u8, trimmed, "import ");
    const from_pos = std.mem.indexOf(u8, trimmed, "from ");

    if (from_pos) |from_start| {
        const after_from = std.mem.trim(u8, trimmed[from_start + "from ".len ..], " \t");
        const import_kw = std.mem.indexOf(u8, after_from, " import ");
        if (import_kw != null) {
            const module = std.mem.trim(u8, after_from[0..import_kw.?], " \t");
            if (module.len > 0) {
                try out.append(.{
                    .importer_id = importer_id,
                    .import_name = try allocator.dupe(u8, module),
                    .file_path = try allocator.dupe(u8, file_path),
                });
            }
        }
    } else if (import_pos != null) {
        const after_import = std.mem.trim(u8, trimmed[import_pos.? + "import ".len ..], " \t");
        var modules = std.mem.split(u8, after_import, ",");
        while (modules.next()) |raw| {
            const target = std.mem.trim(u8, raw, " \t");
            if (target.len == 0) continue;
            const name = if (std.mem.indexOf(u8, target, " as ")) |as_pos|
                std.mem.trim(u8, target[0..as_pos], " \t")
            else
                target;
            if (name.len == 0) continue;
            try out.append(.{
                .importer_id = importer_id,
                .import_name = try allocator.dupe(u8, name),
                .file_path = try allocator.dupe(u8, file_path),
            });
        }
    }
}

fn parseJsImports(
    allocator: std.mem.Allocator,
    line: []const u8,
    importer_id: i64,
    file_path: []const u8,
    out: *std.ArrayList(UnresolvedImport),
) !void {
    const trimmed = std.mem.trim(u8, line, " \t");
    const import_pos = std.mem.indexOf(u8, trimmed, "import ");
    if (import_pos != null) {
        const tail = trimmed[import_pos.? + "import ".len ..];
        const from_pos = std.mem.indexOf(u8, tail, " from ");
        if (from_pos != null) {
            if (extractQuotedString(tail[from_pos.? + " from ".len ..])) |spec| {
                try out.append(.{
                    .importer_id = importer_id,
                    .import_name = try allocator.dupe(u8, spec),
                    .file_path = try allocator.dupe(u8, file_path),
                });
            }
            return;
        }
        if (std.mem.startsWith(u8, tail, "require(")) {
            if (extractQuotedString(tail["require(".len..])) |spec| {
                try out.append(.{
                    .importer_id = importer_id,
                    .import_name = try allocator.dupe(u8, spec),
                    .file_path = try allocator.dupe(u8, file_path),
                });
            }
            return;
        }
        return;
    }

    if (std.mem.indexOf(u8, trimmed, "require(")) |req_pos| {
        const after = trimmed[req_pos + "require(".len ..];
        if (extractQuotedString(after)) |spec| {
            try out.append(.{
                .importer_id = importer_id,
                .import_name = try allocator.dupe(u8, spec),
                .file_path = try allocator.dupe(u8, file_path),
            });
        }
    }
}

fn parseRustImports(
    allocator: std.mem.Allocator,
    line: []const u8,
    importer_id: i64,
    file_path: []const u8,
    out: *std.ArrayList(UnresolvedImport),
) !void {
    const trimmed = std.mem.trim(u8, line, " \t");
    const prefix_len: usize = if (std.mem.startsWith(u8, trimmed, "pub use ")) "pub use ".len else if (std.mem.startsWith(u8, trimmed, "use ")) "use ".len else 0;
    if (prefix_len == 0) return;
    const after_use = std.mem.trim(u8, trimmed[prefix_len..], " \t;");
    if (after_use.len == 0) return;

    const semicolon = std.mem.indexOfScalar(u8, after_use, ';') orelse after_use.len;
    const path_raw = std.mem.trim(u8, after_use[0..semicolon], " \t");
    if (path_raw.len == 0) return;

    const path = normalizeUsePath(path_raw);
    if (path.len == 0) return;

    try out.append(.{
        .importer_id = importer_id,
        .import_name = try allocator.dupe(u8, path),
        .file_path = try allocator.dupe(u8, file_path),
    });
}

fn parseZigImports(
    allocator: std.mem.Allocator,
    line: []const u8,
    importer_id: i64,
    file_path: []const u8,
    out: *std.ArrayList(UnresolvedImport),
) !void {
    const import_pos = std.mem.indexOf(u8, line, "@import(") orelse return;
    const after = line[import_pos + "@import(".len ..];
    const spec = extractQuotedString(after) orelse return;
    if (spec.len == 0) return;
    try out.append(.{
        .importer_id = importer_id,
        .import_name = try allocator.dupe(u8, spec),
        .file_path = try allocator.dupe(u8, file_path),
    });
}

fn parseSemanticHint(language: discover.Language, line: []const u8) ?struct {
    parent_name: []const u8,
    relation: []const u8,
} {
    return switch (language) {
        .python => if (parsePythonInheritance(line)) |parent_name| .{ .parent_name = parent_name, .relation = "INHERITS" } else null,
        .javascript, .typescript, .tsx => if (parseJsInheritance(line)) |parent_name| .{ .parent_name = parent_name, .relation = "INHERITS" } else null,
        .rust => if (parseRustSemanticHint(line)) |hint| .{
            .parent_name = hint.parent,
            .relation = hint.relation,
        } else null,
        else => null,
    };
}

fn parseRustSemanticHint(line: []const u8) ?struct {
    relation: []const u8,
    parent: []const u8,
} {
    const impl_pos = std.mem.indexOf(u8, line, "impl ");
    if (impl_pos == null) return null;
    const after_impl = std.mem.trim(u8, line[impl_pos.? + "impl ".len ..], " \t");
    if (after_impl.len == 0) return null;
    const for_pos = std.mem.indexOf(u8, after_impl, " for ");
    if (for_pos == null) return null;
    const parent_raw = std.mem.trim(u8, after_impl[for_pos.? + " for ".len ..], " \t");
    if (parent_raw.len == 0) return null;
    const parent = firstIdentifier(parent_raw) orelse return null;
    return .{ .relation = "IMPLEMENTS", .parent = parent };
}

fn collectCalls(
    allocator: std.mem.Allocator,
    line: []const u8,
    language: discover.Language,
) !?[]const []const u8 {
    _ = language;
    if (line.len == 0) return null;
    var names = std.ArrayList([]const u8).init(allocator);
    var i: usize = 0;

    while (i < line.len) {
        if (line[i] == '#') break;
        if (line[i] == '/' and i + 1 < line.len and line[i + 1] == '/') break;
        if (line[i] == '/' and i + 1 < line.len and (line[i + 1] == '*' or line[i + 1] == '/')) break;

        if (line[i] == '"' or line[i] == '\'' or line[i] == '`') {
            const quote = line[i];
            i += 1;
            while (i < line.len and line[i] != quote) {
                if (line[i] == '\\') i += 2 else i += 1;
            }
            if (i < line.len) i += 1;
            continue;
        }
        if (!isIdentifierStart(line[i])) {
            i += 1;
            continue;
        }

        const start = i;
        while (i < line.len and isIdentifierChar(line[i])) i += 1;
        var callee = line[start..i];

        var j = i;
        while (j < line.len and std.ascii.isWhitespace(line[j])) j += 1;
        while (j < line.len and line[j] == '.') {
            j += 1;
            while (j < line.len and std.ascii.isWhitespace(line[j])) j += 1;
            const part_start = j;
            while (j < line.len and isIdentifierChar(line[j])) j += 1;
            if (part_start == j) break;
            callee = line[part_start..j];
            while (j < line.len and std.ascii.isWhitespace(line[j])) j += 1;
        }
        if (j < line.len and line[j] == '(' and callee.len > 0) {
            if (!isKeywordCandidate(callee)) {
                try names.append(try allocator.dupe(u8, callee));
            }
        }
        i = j + 1;
    }

    if (names.items.len == 0) {
        return null;
    }
    return try names.toOwnedSlice();
}

fn parseSymbol(language: discover.Language, line: []const u8) ?ParsedSymbol {
    return switch (language) {
        .python => parsePythonDefs(line),
        .javascript, .typescript, .tsx => parseJsDefs(line),
        .rust => parseRustDefs(line),
        .zig => parseZigDefs(line),
        else => null,
    };
}

fn parsePythonDefs(line: []const u8) ?ParsedSymbol {
    if (extractPrefixName(line, "def ")) |name| {
        return .{ .label = "Function", .name = name };
    }
    if (extractPrefixName(line, "async def ")) |name| {
        return .{ .label = "Function", .name = name };
    }
    if (extractPrefixName(line, "class ")) |name| {
        return .{ .label = "Class", .name = name };
    }
    return null;
}

fn parseJsDefs(line: []const u8) ?ParsedSymbol {
    if (extractPrefixName(line, "export async function ")) |name| {
        return .{ .label = "Function", .name = name };
    }
    if (extractPrefixName(line, "export function ")) |name| {
        return .{ .label = "Function", .name = name };
    }
    if (extractPrefixName(line, "async function ")) |name| {
        return .{ .label = "Function", .name = name };
    }
    if (extractPrefixName(line, "function ")) |name| {
        return .{ .label = "Function", .name = name };
    }
    if (extractPrefixName(line, "class ")) |name| {
        return .{ .label = "Class", .name = name };
    }
    if (parseJsVarOrConstFn(line)) |name| {
        return .{ .label = "Function", .name = name };
    }
    return null;
}

fn parseRustDefs(line: []const u8) ?ParsedSymbol {
    if (extractPrefixName(line, "pub async fn ")) |name| {
        return .{ .label = "Function", .name = name };
    }
    if (extractPrefixName(line, "async fn ")) |name| {
        return .{ .label = "Function", .name = name };
    }
    if (extractPrefixName(line, "pub fn ")) |name| {
        return .{ .label = "Function", .name = name };
    }
    if (extractPrefixName(line, "fn ")) |name| {
        return .{ .label = "Function", .name = name };
    }
    if (extractPrefixName(line, "pub const ")) |name| {
        return .{ .label = "Constant", .name = name };
    }
    if (extractPrefixName(line, "struct ")) |name| {
        return .{ .label = "Class", .name = name };
    }
    if (extractPrefixName(line, "enum ")) |name| {
        return .{ .label = "Class", .name = name };
    }
    if (extractPrefixName(line, "trait ")) |name| {
        return .{ .label = "Class", .name = name };
    }
    if (parseRustImpl(line)) |name| {
        return .{ .label = "Class", .name = name };
    }
    return null;
}

fn parseRustImpl(line: []const u8) ?[]const u8 {
    const impl_pos = std.mem.indexOf(u8, line, "impl ");
    if (impl_pos == null) return null;
    var cursor = impl_pos.? + "impl ".len;
    const trimmed = std.mem.trim(u8, line[cursor..], " \t");
    if (trimmed.len == 0) return null;
    if (trimmed[0] == '<') {
        const close = std.mem.indexOf(u8, trimmed, ">") orelse return null;
        cursor = close + 1;
    } else {
        cursor = 0;
    }

    const after = if (cursor == 0) trimmed else trimmed[cursor..];
    const spaced = std.mem.trim(u8, after, " \t");
    const for_pos = std.mem.indexOf(u8, spaced, " for ");
    const target = if (for_pos) |p| spaced[0..p] else spaced;
    return firstIdentifier(target);
}

fn parseZigDefs(line: []const u8) ?ParsedSymbol {
    if (extractPrefixName(line, "pub fn ")) |name| {
        return .{ .label = "Function", .name = name };
    }
    if (extractPrefixName(line, "fn ")) |name| {
        return .{ .label = "Function", .name = name };
    }
    if (extractPrefixName(line, "pub const ")) |name| {
        return .{ .label = "Constant", .name = name };
    }
    if (extractPrefixName(line, "const ")) |name| {
        return .{ .label = "Constant", .name = name };
    }

    const trimmed = std.mem.trim(u8, line, " \t");
    if (std.mem.startsWith(u8, trimmed, "test \"")) {
        const quote_pos = std.mem.indexOf(u8, trimmed, "\"") orelse return null;
        const rest = trimmed[quote_pos + 1 ..];
        const end = std.mem.indexOf(u8, rest, "\"") orelse return null;
        const test_name = rest[0..end];
        return .{ .label = "Test", .name = test_name };
    }
    return null;
}

fn parseJsInheritance(line: []const u8) ?[]const u8 {
    const class_pos = std.mem.indexOf(u8, line, "class ");
    if (class_pos == null) return null;
    const after_class = std.mem.trim(u8, line[class_pos.? + "class ".len ..], " \t");
    const extends_pos = std.mem.indexOf(u8, after_class, " extends ");
    if (extends_pos == null) return null;
    const parent_raw = std.mem.trim(u8, after_class[extends_pos.? + " extends ".len ..], " \t{");
    return firstIdentifier(parent_raw);
}

fn parsePythonInheritance(line: []const u8) ?[]const u8 {
    const class_pos = std.mem.indexOf(u8, line, "class ");
    if (class_pos == null) return null;
    const after_class = std.mem.trim(u8, line[class_pos.? + "class ".len ..], " \t");
    const open_paren = std.mem.indexOf(u8, after_class, "(") orelse return null;
    const close_paren = std.mem.indexOf(u8, after_class[open_paren + 1 ..], ")") orelse return null;
    const base_raw = std.mem.trim(u8, after_class[open_paren + 1 .. open_paren + 1 + close_paren], " \t");
    if (base_raw.len == 0) return null;
    return firstIdentifier(base_raw);
}

fn firstIdentifier(text: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, text, " \t");
    if (trimmed.len == 0) return null;
    if (!isIdentifierStart(trimmed[0])) {
        return null;
    }
    var end: usize = 1;
    while (end < trimmed.len and isIdentifierChar(trimmed[end])) end += 1;
    return trimmed[0..end];
}

fn parseJsVarOrConstFn(line: []const u8) ?[]const u8 {
    const is_const = std.mem.startsWith(u8, line, "const ");
    const is_let = std.mem.startsWith(u8, line, "let ");
    const offset: usize = if (is_const) 6 else if (is_let) 4 else return null;
    const rest = std.mem.trim(u8, line[offset..], " \t");
    const equals = std.mem.indexOf(u8, rest, "=") orelse return null;
    const name = std.mem.trim(u8, rest[0..equals], " \t");
    if (name.len == 0 or !isIdentifierStart(name[0])) return null;
    const rhs = std.mem.trim(u8, rest[equals + 1 ..], " \t");
    if (rhs.len == 0) return null;
    if (std.mem.containsAtLeast(u8, rhs, 1, "=>") or
        std.mem.containsAtLeast(u8, rhs, 1, "function") or
        std.mem.containsAtLeast(u8, rhs, 1, "async"))
    {
        return name;
    }
    return null;
}

fn extractPrefixName(line: []const u8, prefix: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, line, " \t");
    if (!std.mem.startsWith(u8, trimmed, prefix)) return null;
    var start = prefix.len;
    while (start < trimmed.len and std.ascii.isWhitespace(trimmed[start])) start += 1;
    if (start >= trimmed.len or !isIdentifierStart(trimmed[start])) return null;
    var end = start + 1;
    while (end < trimmed.len and isIdentifierChar(trimmed[end])) end += 1;
    return trimmed[start..end];
}

fn extractQuotedString(line: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, line, " \t;");
    var quote_pos: usize = std.math.maxInt(usize);
    var quote_char: u8 = 0;
    if (std.mem.indexOfScalar(u8, trimmed, '"')) |dq| {
        quote_pos = dq;
        quote_char = '"';
    }
    if (std.mem.indexOfScalar(u8, trimmed, '\'')) |sq| {
        if (sq < quote_pos) {
            quote_pos = sq;
            quote_char = '\'';
        }
    }
    if (quote_char == 0 or quote_pos == std.math.maxInt(usize)) return null;
    const start = quote_pos + 1;
    if (start >= trimmed.len) return null;
    const end = std.mem.indexOfScalar(u8, trimmed[start..], quote_char) orelse return null;
    if (start + end == start) return "";
    return trimmed[start .. start + end];
}

fn normalizeUsePath(spec: []const u8) []const u8 {
    const group_open = std.mem.indexOf(u8, spec, "::{");
    var path = if (group_open) |idx| spec[0..idx] else spec;
    if (std.mem.indexOf(u8, path, " as ")) |as_pos| {
        path = path[0..as_pos];
    }
    return std.mem.trim(u8, path, " \t;");
}

fn stripComments(language: discover.Language, line: []const u8) []const u8 {
    return switch (language) {
        .python => stripCommentToken(line, '#'),
        else => {
            const slash = std.mem.indexOf(u8, line, "//");
            if (slash == null) return line;
            return line[0..slash.?];
        },
    };
}

fn stripCommentToken(line: []const u8, token: u8) []const u8 {
    const idx = std.mem.indexOfScalar(u8, line, token);
    if (idx == null) return line;
    return line[0..idx.?];
}

fn normalizePath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const copied = try allocator.dupe(u8, path);
    for (copied) |*c| {
        if (c.* == std.fs.path.sep) c.* = '/';
    }
    return copied;
}

fn isIdentifierChar(c: u8) bool {
    return std.ascii.isAlphabetic(c) or
        std.ascii.isDigit(c) or
        c == '_' or
        c == '@';
}

fn isIdentifierStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_' or c == '@';
}

fn isKeywordCandidate(name: []const u8) bool {
    const keywords = [_][]const u8{
        "if",
        "for",
        "while",
        "switch",
        "return",
        "await",
        "else",
        "catch",
        "true",
        "false",
        "new",
        "this",
        "class",
        "interface",
        "const",
        "let",
        "var",
        "fn",
        "pub",
        "impl",
        "struct",
        "enum",
        "trait",
        "async",
        "await",
        "use",
        "from",
        "as",
        "in",
        "is",
    };
    for (keywords) |kw| {
        if (std.mem.eql(u8, kw, name)) return true;
    }
    return false;
}

fn freeStringSlices(allocator: std.mem.Allocator, names: []const []const u8) void {
    for (names) |name| allocator.free(name);
    allocator.free(names);
}

pub fn freeExtractedSymbols(allocator: std.mem.Allocator, symbols: []ExtractedSymbol) void {
    for (symbols) |s| {
        allocator.free(s.label);
        allocator.free(s.name);
        allocator.free(s.qualified_name);
        allocator.free(s.file_path);
    }
    allocator.free(symbols);
}

pub fn freeUnresolvedCalls(allocator: std.mem.Allocator, calls: []UnresolvedCall) void {
    for (calls) |c| {
        allocator.free(c.callee_name);
        allocator.free(c.file_path);
    }
    allocator.free(calls);
}

pub fn freeUnresolvedImports(allocator: std.mem.Allocator, imports: []UnresolvedImport) void {
    for (imports) |i| {
        allocator.free(i.import_name);
        allocator.free(i.file_path);
    }
    allocator.free(imports);
}

pub fn freeSemanticHints(allocator: std.mem.Allocator, hints: []SemanticHint) void {
    for (hints) |h| {
        allocator.free(h.parent_name);
        allocator.free(h.file_path);
        allocator.free(h.relation);
    }
    allocator.free(hints);
}

pub fn freeFileExtraction(allocator: std.mem.Allocator, extraction: FileExtraction) void {
    allocator.free(extraction.file_path);
    freeExtractedSymbols(allocator, extraction.symbols);
    freeUnresolvedCalls(allocator, extraction.unresolved_calls);
    freeUnresolvedImports(allocator, extraction.unresolved_imports);
    freeSemanticHints(allocator, extraction.semantic_hints);
}

test "extractor parses definitions for core languages" {
    try std.testing.expect(parseSymbol(.python, "def hello(x):") != null);
    try std.testing.expect(parseSymbol(.python, "class A(object):") != null);
    try std.testing.expect(parseSymbol(.zig, "fn main() !void") != null);
    try std.testing.expect(parseSymbol(.rust, "pub async fn load()") != null);
    try std.testing.expect(parseSymbol(.javascript, "export async function calc(a,b)") != null);
    try std.testing.expect(parseSymbol(.javascript, "const run = async () => {}") != null);
    try std.testing.expect(parseSymbol(.javascript, "class Service extends Base") != null);
    try std.testing.expect(parseSymbol(.rust, "impl Display for Foo") != null);
}

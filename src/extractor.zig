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
const ts = @import("tree_sitter");

const TsDefinition = struct {
    label: []const u8,
    name: []const u8,
    start_line: i32,
};

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

const TsSymbol = struct {
    symbol_id: i64,
    line_no: i32,
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

    var symbols = std.ArrayList(ExtractedSymbol).empty;
    var tree_sitter_defs = std.ArrayList(TsDefinition).empty;
    var unresolved_calls = std.ArrayList(UnresolvedCall).empty;
    var unresolved_imports = std.ArrayList(UnresolvedImport).empty;
    var semantic_hints = std.ArrayList(SemanticHint).empty;
    var scope_markers = std.ArrayList(TsSymbol).empty;
    errdefer freePendingExtractedSymbols(allocator, &symbols);
    defer freePendingTsDefinitions(allocator, &tree_sitter_defs);
    errdefer freePendingUnresolvedCalls(allocator, &unresolved_calls);
    errdefer freePendingUnresolvedImports(allocator, &unresolved_imports);
    errdefer freePendingSemanticHints(allocator, &semantic_hints);
    defer scope_markers.deinit(allocator);

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
        return finishExtraction(
            allocator,
            try allocator.dupe(u8, rel),
            0,
            0,
            file.language,
            &symbols,
            &unresolved_calls,
            &unresolved_imports,
            &semantic_hints,
        );
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
            return finishExtraction(
                allocator,
                try allocator.dupe(u8, rel),
                file_id,
                module_id,
                file.language,
                &symbols,
                &unresolved_calls,
                &unresolved_imports,
                &semantic_hints,
            );
        },
        else => return err,
    };
    defer allocator.free(bytes);

    if (supportsTreeSitterDefs(file.language)) {
        collectDefinitionsWithTreeSitter(allocator, bytes, file.language, &tree_sitter_defs) catch |err| {
            switch (err) {
                error.OutOfMemory => return err,
                else => {},
            }
        };
    }

    for (tree_sitter_defs.items) |def| {
        const symbol_qn = try std.fmt.allocPrint(
            allocator,
            "{s}:{s}:{s}:symbol:{s}:{s}",
            .{ project_name, qn_base, @tagName(file.language), @tagName(file.language), def.name },
        );
        const symbol_id = try gb.upsertNode(
            def.label,
            def.name,
            symbol_qn,
            rel,
            def.start_line,
            def.start_line,
        );
        if (symbol_id > 0 and gb.findNodeById(module_id) != null) {
            _ = gb.insertEdge(module_id, symbol_id, "CONTAINS") catch |err| switch (err) {
                graph_buffer.GraphBufferError.DuplicateEdge => {},
                else => {
                    allocator.free(symbol_qn);
                    return err;
                },
            };
            try symbols.append(allocator, .{
                .id = symbol_id,
                .label = try allocator.dupe(u8, def.label),
                .name = try allocator.dupe(u8, def.name),
                .qualified_name = try allocator.dupe(u8, symbol_qn),
                .file_path = try allocator.dupe(u8, rel),
            });
            if (isDeclarationLabel(def.label)) {
                try scope_markers.append(allocator, .{
                    .symbol_id = symbol_id,
                    .line_no = def.start_line,
                });
            }
        }
        allocator.free(symbol_qn);
    }

    if (scope_markers.items.len > 1) {
        std.sort.pdq(TsSymbol, scope_markers.items, {}, tsSymbolLessThan);
    }

    var lines = std.mem.splitAny(u8, bytes, "\n\r");
    var line_no: i32 = 1;
    var scope_index: usize = 0;
    while (lines.next()) |line_raw| : (line_no += 1) {
        const line = std.mem.trim(u8, line_raw, " \t");
        if (line.len == 0) continue;

        const clean_line = stripComments(file.language, line);
        if (clean_line.len == 0) continue;

        while (scope_index < scope_markers.items.len and scope_markers.items[scope_index].line_no == line_no) {
            current_scope_id = scope_markers.items[scope_index].symbol_id;
            scope_index += 1;
        }

        const parsed_symbol = parseSymbol(file.language, clean_line);
        if (parsed_symbol) |sym| {
            const symbol_qn = try std.fmt.allocPrint(
                allocator,
                "{s}:{s}:{s}:symbol:{s}:{s}",
                .{ project_name, qn_base, @tagName(file.language), @tagName(file.language), sym.name },
            );
            defer allocator.free(symbol_qn);

            addSymbolFromParsed(
                allocator,
                project_name,
                qn_base,
                rel,
                file.language,
                line_no,
                sym,
                gb,
                module_id,
                &symbols,
            ) catch |err| switch (err) {
                error.OutOfMemory => return err,
                else => {},
            };
            if (sym.label.len > 0 and isDeclarationLabel(sym.label)) {
                if (gb.findNodeByQualifiedName(symbol_qn)) |decl_node| {
                    current_scope_id = decl_node.id;
                }
            }
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
                try semantic_hints.append(allocator, .{
                    .child_id = current_scope_id,
                    .parent_name = try allocator.dupe(u8, hint.parent_name),
                    .file_path = try allocator.dupe(u8, rel),
                    .relation = try allocator.dupe(u8, hint.relation),
                });
            }
        }

        const callee_names = collectCalls(
            allocator,
            clean_line,
            file.language,
            parsed_symbol,
        ) catch |err| switch (err) {
            error.OutOfMemory => return err,
        };
        if (callee_names) |names| {
            defer freeStringSlices(allocator, names);
            for (names) |callee| {
                if (callee.len == 0) continue;
                const caller_id = if (current_scope_id != 0) current_scope_id else module_id;
                try unresolved_calls.append(allocator, .{
                    .caller_id = caller_id,
                    .callee_name = try allocator.dupe(u8, callee),
                    .file_path = try allocator.dupe(u8, rel),
                });
            }
        }
    }

    return finishExtraction(
        allocator,
        try allocator.dupe(u8, rel),
        file_id,
        module_id,
        file.language,
        &symbols,
        &unresolved_calls,
        &unresolved_imports,
        &semantic_hints,
    );
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
                try out.append(allocator, .{
                    .importer_id = importer_id,
                    .import_name = try allocator.dupe(u8, module),
                    .file_path = try allocator.dupe(u8, file_path),
                });
            }
        }
    } else if (import_pos != null) {
        const after_import = std.mem.trim(u8, trimmed[import_pos.? + "import ".len ..], " \t");
        var modules = std.mem.splitSequence(u8, after_import, ",");
        while (modules.next()) |raw| {
            const target = std.mem.trim(u8, raw, " \t");
            if (target.len == 0) continue;
            const name = if (std.mem.indexOf(u8, target, " as ")) |as_pos|
                std.mem.trim(u8, target[0..as_pos], " \t")
            else
                target;
            if (name.len == 0) continue;
            try out.append(allocator, .{
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
                try out.append(allocator, .{
                    .importer_id = importer_id,
                    .import_name = try allocator.dupe(u8, spec),
                    .file_path = try allocator.dupe(u8, file_path),
                });
            }
            return;
        }
        if (std.mem.startsWith(u8, tail, "require(")) {
            if (extractQuotedString(tail["require(".len..])) |spec| {
                try out.append(allocator, .{
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
            try out.append(allocator, .{
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

    try out.append(allocator, .{
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
    try out.append(allocator, .{
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
            .parent_name = hint.trait_name,
            .relation = hint.relation,
        } else null,
        else => null,
    };
}

fn parseRustSemanticHint(line: []const u8) ?struct {
    relation: []const u8,
    trait_name: []const u8,
} {
    const parts = parseRustImplParts(line) orelse return null;
    const trait_name = parts.trait_name orelse return null;
    return .{ .relation = "IMPLEMENTS", .trait_name = trait_name };
}

fn collectCalls(
    allocator: std.mem.Allocator,
    line: []const u8,
    language: discover.Language,
    parsed_symbol: ?ParsedSymbol,
) !?[]const []const u8 {
    if (line.len == 0) return null;
    if (parsed_symbol) |sym| {
        if (isDeclarationLabel(sym.label)) return null;
    } else if (isDeclarationLine(language, line)) {
        return null;
    }

    var names: std.ArrayList([]const u8) = .empty;
    errdefer freePendingStringSlices(allocator, &names);
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
                try names.append(allocator, try allocator.dupe(u8, callee));
            }
        }
        i = j;
    }

    if (names.items.len == 0) {
        return null;
    }
    return try names.toOwnedSlice(allocator);
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

fn isDeclarationLabel(label: []const u8) bool {
    return std.mem.eql(u8, label, "Function") or
        std.mem.eql(u8, label, "Class") or
        std.mem.eql(u8, label, "Struct") or
        std.mem.eql(u8, label, "Trait") or
        std.mem.eql(u8, label, "Interface") or
        std.mem.eql(u8, label, "Test");
}

fn addSymbolFromParsed(
    allocator: std.mem.Allocator,
    project_name: []const u8,
    qn_base: []const u8,
    rel: []const u8,
    language: discover.Language,
    line_no: i32,
    symbol: ParsedSymbol,
    gb: *graph_buffer.GraphBuffer,
    module_id: i64,
    symbols: *std.ArrayList(ExtractedSymbol),
) !void {
    const symbol_qn = try std.fmt.allocPrint(
        allocator,
        "{s}:{s}:{s}:symbol:{s}:{s}",
        .{ project_name, qn_base, @tagName(language), @tagName(language), symbol.name },
    );
    defer allocator.free(symbol_qn);

    const exists = gb.findNodeByQualifiedName(symbol_qn) != null;
    const symbol_id = try gb.upsertNode(
        symbol.label,
        symbol.name,
        symbol_qn,
        rel,
        line_no,
        line_no,
    );
    if (symbol_id > 0 and gb.findNodeById(module_id) != null and !exists) {
        _ = gb.insertEdge(module_id, symbol_id, "CONTAINS") catch |err| switch (err) {
            graph_buffer.GraphBufferError.DuplicateEdge => {},
            else => {
                return err;
            },
        };
        try symbols.append(allocator, .{
            .id = symbol_id,
            .label = try allocator.dupe(u8, symbol.label),
            .name = try allocator.dupe(u8, symbol.name),
            .qualified_name = try allocator.dupe(u8, symbol_qn),
            .file_path = try allocator.dupe(u8, rel),
        });
    }
}

fn supportsTreeSitterDefs(language: discover.Language) bool {
    return switch (language) {
        .python, .javascript, .typescript, .tsx, .rust, .zig => true,
        else => false,
    };
}

fn collectDefinitionsWithTreeSitter(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    language: discover.Language,
    out: *std.ArrayList(TsDefinition),
) !void {
    const language_fn: *const fn () *const ts.Language = switch (language) {
        .python => treeSitterLanguagePython,
        .javascript => treeSitterLanguageJavascript,
        .typescript => treeSitterLanguageTypescript,
        .tsx => treeSitterLanguageTsx,
        .rust => treeSitterLanguageRust,
        .zig => treeSitterLanguageZig,
        else => return,
    };

    var parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(language_fn());
    const parsed_tree = parser.parseString(bytes, null) orelse return;
    defer parsed_tree.destroy();
    try collectTsDefinitions(allocator, language, bytes, parsed_tree.rootNode(), out);
}

fn collectTsDefinitions(
    allocator: std.mem.Allocator,
    language: discover.Language,
    bytes: []const u8,
    node: ts.Node,
    out: *std.ArrayList(TsDefinition),
) !void {
    if (tsNodeLabel(language, node.kind())) |label| {
        if (try extractTsName(allocator, language, bytes, node)) |name| {
            try out.append(allocator, .{
                .label = try allocator.dupe(u8, label),
                .name = name,
                .start_line = @as(i32, @intCast(node.startPoint().row)) + 1,
            });
        }
    }

    const child_count = node.namedChildCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        if (node.namedChild(i)) |child| {
            try collectTsDefinitions(allocator, language, bytes, child, out);
        }
    }
}

fn tsNodeLabel(language: discover.Language, kind: []const u8) ?[]const u8 {
    return switch (language) {
        .python => if (std.mem.eql(u8, kind, "function_definition"))
            "Function"
        else if (std.mem.eql(u8, kind, "class_definition"))
            "Class"
        else
            null,
        .javascript, .typescript, .tsx => if (std.mem.eql(u8, kind, "function_declaration") or
            std.mem.eql(u8, kind, "generator_function_declaration") or
            std.mem.eql(u8, kind, "function_expression") or
            std.mem.eql(u8, kind, "arrow_function") or
            std.mem.eql(u8, kind, "method_definition"))
            "Function"
        else if (std.mem.eql(u8, kind, "class_declaration") or
            std.mem.eql(u8, kind, "class"))
            "Class"
        else if (std.mem.eql(u8, kind, "abstract_class_declaration") or
            std.mem.eql(u8, kind, "enum_declaration") or
            std.mem.eql(u8, kind, "interface_declaration") or
            std.mem.eql(u8, kind, "type_alias_declaration") or
            std.mem.eql(u8, kind, "internal_module"))
            "Interface"
        else
            null,
        .rust => if (std.mem.eql(u8, kind, "function_item") or
            std.mem.eql(u8, kind, "function_signature_item") or
            std.mem.eql(u8, kind, "closure_expression"))
            "Function"
        else if (std.mem.eql(u8, kind, "struct_item") or
            std.mem.eql(u8, kind, "enum_item") or
            std.mem.eql(u8, kind, "union_item") or
            std.mem.eql(u8, kind, "trait_item") or
            std.mem.eql(u8, kind, "type_item") or
            std.mem.eql(u8, kind, "impl_item"))
            if (std.mem.eql(u8, kind, "trait_item")) "Trait" else "Class"
        else
            null,
        .zig => if (std.mem.eql(u8, kind, "function_declaration") or
            std.mem.eql(u8, kind, "test_declaration"))
            "Function"
        else if (std.mem.eql(u8, kind, "struct_declaration") or
            std.mem.eql(u8, kind, "enum_declaration") or
            std.mem.eql(u8, kind, "union_declaration"))
            "Struct"
        else if (std.mem.eql(u8, kind, "variable_declaration"))
            "Constant"
        else
            null,
        else => null,
    };
}

fn extractTsName(
    allocator: std.mem.Allocator,
    language: discover.Language,
    bytes: []const u8,
    node: ts.Node,
) !?[]const u8 {
    if (language == .rust and std.mem.eql(u8, node.kind(), "impl_item")) {
        const start = @as(usize, @intCast(node.startByte()));
        const end = @as(usize, @intCast(node.endByte()));
        if (start >= bytes.len or end > bytes.len or start >= end) return null;
        const src = bytes[start..end];
        const impl_target = extractRustImplFromText(src) orelse return null;
        return try allocator.dupe(u8, impl_target);
    }

    const name_node = node.childByFieldName("name") orelse {
        if (language == .zig and std.mem.eql(u8, node.kind(), "variable_declaration")) {
            const start = @as(usize, @intCast(node.startByte()));
            const end = @as(usize, @intCast(node.endByte()));
            if (start >= bytes.len or end > bytes.len or start >= end) return null;
            const src = std.mem.trim(u8, bytes[start..end], " \t\r\n");
            if (extractPrefixName(src, "const ")) |name| return try allocator.dupe(u8, name);
            if (extractPrefixName(src, "var ")) |name| return try allocator.dupe(u8, name);
        }
        return null;
    };

    const start = @as(usize, @intCast(name_node.startByte()));
    const end = @as(usize, @intCast(name_node.endByte()));
    if (start >= bytes.len or end > bytes.len or start >= end) return null;
    return try allocator.dupe(u8, bytes[start..end]);
}

fn extractRustImplFromText(bytes: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, bytes, " \t\r\n");
    const parts = parseRustImplParts(trimmed) orelse return null;
    return parts.target_name;
}

fn tsSymbolLessThan(_: void, lhs: TsSymbol, rhs: TsSymbol) bool {
    if (lhs.line_no < rhs.line_no) return true;
    if (lhs.line_no > rhs.line_no) return false;
    return lhs.symbol_id < rhs.symbol_id;
}

fn freePendingTsDefinitions(allocator: std.mem.Allocator, definitions: *std.ArrayList(TsDefinition)) void {
    for (definitions.items) |d| {
        allocator.free(d.label);
        allocator.free(d.name);
    }
    definitions.deinit(allocator);
}

extern "c" fn tree_sitter_python() *const ts.Language;
extern "c" fn tree_sitter_javascript() *const ts.Language;
extern "c" fn tree_sitter_typescript() *const ts.Language;
extern "c" fn tree_sitter_tsx() *const ts.Language;
extern "c" fn tree_sitter_rust() *const ts.Language;
extern "c" fn tree_sitter_zig() *const ts.Language;

fn treeSitterLanguagePython() *const ts.Language {
    return tree_sitter_python();
}

fn treeSitterLanguageJavascript() *const ts.Language {
    return tree_sitter_javascript();
}

fn treeSitterLanguageTypescript() *const ts.Language {
    return tree_sitter_typescript();
}

fn treeSitterLanguageTsx() *const ts.Language {
    return tree_sitter_tsx();
}

fn treeSitterLanguageRust() *const ts.Language {
    return tree_sitter_rust();
}

fn treeSitterLanguageZig() *const ts.Language {
    return tree_sitter_zig();
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
        return .{ .label = "Trait", .name = name };
    }
    if (parseRustImpl(line)) |name| {
        return .{ .label = "Class", .name = name };
    }
    return null;
}

fn parseRustImpl(line: []const u8) ?[]const u8 {
    const parts = parseRustImplParts(line) orelse return null;
    return parts.target_name;
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

fn finishExtraction(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    file_id: i64,
    module_id: i64,
    language: discover.Language,
    symbols: *std.ArrayList(ExtractedSymbol),
    unresolved_calls: *std.ArrayList(UnresolvedCall),
    unresolved_imports: *std.ArrayList(UnresolvedImport),
    semantic_hints: *std.ArrayList(SemanticHint),
) !FileExtraction {
    errdefer allocator.free(file_path);

    const owned_symbols = try symbols.toOwnedSlice(allocator);
    errdefer freeExtractedSymbols(allocator, owned_symbols);

    const owned_calls = try unresolved_calls.toOwnedSlice(allocator);
    errdefer freeUnresolvedCalls(allocator, owned_calls);

    const owned_imports = try unresolved_imports.toOwnedSlice(allocator);
    errdefer freeUnresolvedImports(allocator, owned_imports);

    const owned_hints = try semantic_hints.toOwnedSlice(allocator);
    errdefer freeSemanticHints(allocator, owned_hints);

    return .{
        .file_path = file_path,
        .file_id = file_id,
        .module_id = module_id,
        .language = language,
        .symbols = owned_symbols,
        .unresolved_calls = owned_calls,
        .unresolved_imports = owned_imports,
        .semantic_hints = owned_hints,
    };
}

fn parseRustImplParts(line: []const u8) ?struct {
    target_name: []const u8,
    trait_name: ?[]const u8,
} {
    const impl_pos = std.mem.indexOf(u8, line, "impl ");
    if (impl_pos == null) return null;

    var trimmed = std.mem.trim(u8, line[impl_pos.? + "impl ".len ..], " \t");
    if (trimmed.len == 0) return null;

    if (trimmed[0] == '<') {
        const close = std.mem.indexOf(u8, trimmed, ">") orelse return null;
        trimmed = std.mem.trim(u8, trimmed[close + 1 ..], " \t");
        if (trimmed.len == 0) return null;
    }

    if (std.mem.indexOf(u8, trimmed, " for ")) |for_pos| {
        const trait_raw = std.mem.trim(u8, trimmed[0..for_pos], " \t");
        const target_raw = std.mem.trim(u8, trimmed[for_pos + " for ".len ..], " \t");
        const trait_name = firstIdentifier(trait_raw) orelse return null;
        const target_name = firstIdentifier(target_raw) orelse return null;
        return .{
            .target_name = target_name,
            .trait_name = trait_name,
        };
    }

    const target_name = firstIdentifier(trimmed) orelse return null;
    return .{
        .target_name = target_name,
        .trait_name = null,
    };
}

fn isDeclarationLine(language: discover.Language, line: []const u8) bool {
    if (parseSymbol(language, line)) |sym| {
        return isDeclarationLabel(sym.label);
    }
    return false;
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

fn freePendingStringSlices(allocator: std.mem.Allocator, names: *std.ArrayList([]const u8)) void {
    for (names.items) |name| allocator.free(name);
    names.deinit(allocator);
}

fn freePendingExtractedSymbols(allocator: std.mem.Allocator, symbols: *std.ArrayList(ExtractedSymbol)) void {
    for (symbols.items) |s| {
        allocator.free(s.label);
        allocator.free(s.name);
        allocator.free(s.qualified_name);
        allocator.free(s.file_path);
    }
    symbols.deinit(allocator);
}

fn freePendingUnresolvedCalls(allocator: std.mem.Allocator, calls: *std.ArrayList(UnresolvedCall)) void {
    for (calls.items) |c| {
        allocator.free(c.callee_name);
        allocator.free(c.file_path);
    }
    calls.deinit(allocator);
}

fn freePendingUnresolvedImports(allocator: std.mem.Allocator, imports: *std.ArrayList(UnresolvedImport)) void {
    for (imports.items) |i| {
        allocator.free(i.import_name);
        allocator.free(i.file_path);
    }
    imports.deinit(allocator);
}

fn freePendingSemanticHints(allocator: std.mem.Allocator, hints: *std.ArrayList(SemanticHint)) void {
    for (hints.items) |h| {
        allocator.free(h.parent_name);
        allocator.free(h.file_path);
        allocator.free(h.relation);
    }
    hints.deinit(allocator);
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

test "extractor parseSymbol captures top-level rust functions" {
    try std.testing.expect(parseSymbol(.rust, "pub fn emit(notifier: &impl Notifier, msg: &str) {") != null);
    try std.testing.expect(parseSymbol(.rust, "pub fn build(counter: &mut Counter) {") != null);
}

test "tree-sitter extracts python definitions with labels and line numbers" {
    var defs = std.ArrayList(TsDefinition).empty;
    defer freePendingTsDefinitions(std.testing.allocator, &defs);

    try collectDefinitionsWithTreeSitter(
        std.testing.allocator,
        \\def helper(value):
        \\    return value
        \\
        \\class Worker:
        \\    pass
        \\
        \\def main():
        \\    return helper(1)
        \\
    ,
        .python,
        &defs,
    );

    try std.testing.expect(definitionPresent(defs.items, "Function", "helper", 1));
    try std.testing.expect(definitionPresent(defs.items, "Class", "Worker", 4));
    try std.testing.expect(definitionPresent(defs.items, "Function", "main", 7));
}

test "tree-sitter extracts javascript definitions with labels and line numbers" {
    var defs = std.ArrayList(TsDefinition).empty;
    defer freePendingTsDefinitions(std.testing.allocator, &defs);

    try collectDefinitionsWithTreeSitter(
        std.testing.allocator,
        \\export function helper(input) {
        \\    return input;
        \\}
        \\
        \\class Service extends Base {
        \\    constructor(value) {
        \\        this.value = value;
        \\    }
        \\}
        \\
        \\function main() {
        \\    return helper(3);
        \\}
        \\
    ,
        .javascript,
        &defs,
    );

    try std.testing.expect(definitionPresent(defs.items, "Function", "helper", 1));
    try std.testing.expect(definitionPresent(defs.items, "Class", "Service", 5));
    try std.testing.expect(definitionPresent(defs.items, "Function", "main", 11));
}

test "tree-sitter extracts typescript definitions with labels and line numbers" {
    var defs = std.ArrayList(TsDefinition).empty;
    defer freePendingTsDefinitions(std.testing.allocator, &defs);

    try collectDefinitionsWithTreeSitter(
        std.testing.allocator,
        \\interface ServicePort {
        \\  read(value: string): void;
        \\}
        \\
        \\function helper(value: string) {
        \\  return value;
        \\}
        \\
        \\class Service implements ServicePort {
        \\  read(value: string): void {}
        \\}
        \\
    ,
        .typescript,
        &defs,
    );

    try std.testing.expect(definitionPresent(defs.items, "Interface", "ServicePort", 1));
    try std.testing.expect(definitionPresent(defs.items, "Function", "helper", 5));
    try std.testing.expect(definitionPresent(defs.items, "Class", "Service", 9));
}

test "tree-sitter extracts tsx definitions with labels and line numbers" {
    var defs = std.ArrayList(TsDefinition).empty;
    defer freePendingTsDefinitions(std.testing.allocator, &defs);

    try collectDefinitionsWithTreeSitter(
        std.testing.allocator,
        \\import { useState } from "react";
        \\
        \\type Props = { label: string };
        \\
        \\function View(props: Props) {
        \\  const [count] = useState(0);
        \\  return <span>{props.label}</span>;
        \\}
        \\
        \\
    ,
        .tsx,
        &defs,
    );

    try std.testing.expect(definitionPresent(defs.items, "Interface", "Props", 3));
    try std.testing.expect(definitionPresent(defs.items, "Function", "View", 5));
}

test "tree-sitter extracts rust definitions with labels and line numbers" {
    var defs = std.ArrayList(TsDefinition).empty;
    defer freePendingTsDefinitions(std.testing.allocator, &defs);

    try collectDefinitionsWithTreeSitter(
        std.testing.allocator,
        \\struct Service {
        \\    id: u64
        \\}
        \\
        \\trait Handler {}
        \\
        \\fn helper(value: u64) -> u64 {
        \\    value + 1
        \\}
        \\
        \\fn main() {
        \\    let _ = helper(5);
        \\}
        \\
        \\impl Handler for Service {
        \\    fn run(&self) {}
        \\}
        \\
    ,
        .rust,
        &defs,
    );

    try std.testing.expect(definitionPresent(defs.items, "Class", "Service", 1));
    try std.testing.expect(definitionPresent(defs.items, "Trait", "Handler", 5));
    try std.testing.expect(definitionPresent(defs.items, "Function", "helper", 7));
    try std.testing.expect(definitionPresent(defs.items, "Function", "main", 11));
    try std.testing.expect(definitionPresent(defs.items, "Class", "Service", 15));
}

test "line parser captures Rust top-level funcs despite traits" {
    const source =
        \\pub const VERSION: u32 = 1;
        \\
        \\pub struct Counter {
        \\    pub value: i32,
        \\}
        \\
        \\pub trait Notifier {
        \\    fn notify(&self, msg: &str);
        \\}
        \\
        \\impl Counter {
        \\    pub fn new(value: i32) -> Self {
        \\        Self { value }
        \\    }
        \\
        \\    pub fn bump(&mut self) {
        \\        self.value += 1;
        \\    }
        \\}
        \\
        \\impl Notifier for Counter {
        \\    fn notify(&self, msg: &str) {
        \\        println!("{msg}");
        \\    }
        \\}
        \\
        \\pub fn emit(notifier: &impl Notifier, msg: &str) {
        \\    notifier.notify(msg);
        \\}
        \\
        \\pub fn build(counter: &mut Counter) {
        \\    counter.bump();
        \\    emit(counter, "ready");
        \\}
        \\
        ;
    var lines = std.mem.splitAny(u8, source, "\n\r");
    var line_no: u32 = 1;
    while (lines.next()) |line_raw| : (line_no += 1) {
        const line = std.mem.trim(u8, line_raw, " \t");
        if (line.len == 0) continue;
        const symbol = parseSymbol(.rust, line);
        if (symbol) |sym| {
            std.debug.print("line {}: {s} {s}\n", .{ line_no, sym.label, sym.name });
        }
    }
}

test "tree-sitter extracts zig definitions with labels and line numbers" {
    var defs = std.ArrayList(TsDefinition).empty;
    defer freePendingTsDefinitions(std.testing.allocator, &defs);

    try collectDefinitionsWithTreeSitter(
        std.testing.allocator,
        \\const max_items = 5;
        \\
        \\fn helper() u8 {
        \\    return 1;
        \\}
        \\
        \\fn main() void {
        \\    _ = helper();
        \\}
        \\
    ,
        .zig,
        &defs,
    );

    try std.testing.expect(definitionPresent(defs.items, "Constant", "max_items", 1));
    try std.testing.expect(definitionPresent(defs.items, "Function", "helper", 3));
    try std.testing.expect(definitionPresent(defs.items, "Function", "main", 7));
}

fn definitionPresent(
    defs: []const TsDefinition,
    expected_label: []const u8,
    expected_name: []const u8,
    expected_line: i32,
) bool {
    for (defs) |def| {
        if (def.start_line != expected_line) continue;
        if (!std.mem.eql(u8, def.label, expected_label)) continue;
        if (!std.mem.eql(u8, def.name, expected_name)) continue;
        return true;
    }
    return false;
}

test "rust impl parsing keeps target and trait roles straight" {
    const parts = parseRustImplParts("impl Display for Foo {") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("Foo", parts.target_name);
    try std.testing.expect(parts.trait_name != null);
    try std.testing.expectEqualStrings("Display", parts.trait_name.?);

    const hint = parseRustSemanticHint("impl Display for Foo {") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("Display", hint.trait_name);
}

test "call collection skips declaration lines" {
    try std.testing.expect((try collectCalls(std.testing.allocator, "fn main() void {}", .zig, null)) == null);
    try std.testing.expect((try collectCalls(std.testing.allocator, "def hello(x):", .python, null)) == null);
    try std.testing.expect((try collectCalls(std.testing.allocator, "class Foo(Base):", .python, null)) == null);

    const calls = (try collectCalls(std.testing.allocator, "result = helper(value)", .python, null)) orelse return error.TestUnexpectedResult;
    defer freeStringSlices(std.testing.allocator, calls);
    try std.testing.expectEqual(@as(usize, 1), calls.len);
    try std.testing.expectEqualStrings("helper", calls[0]);

    const const_calls = (try collectCalls(
        std.testing.allocator,
        "const doubled = add(value, 1)",
        .zig,
        null,
    )) orelse return error.TestUnexpectedResult;
    defer freeStringSlices(std.testing.allocator, const_calls);
    try std.testing.expectEqual(@as(usize, 1), const_calls.len);
    try std.testing.expectEqualStrings("add", const_calls[0]);
}

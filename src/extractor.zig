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
const routes = @import("routes.zig");
const service_patterns = @import("service_patterns.zig");
const test_tagging = @import("test_tagging.zig");
const ts = @import("tree_sitter");

const TsDefinition = struct {
    label: []const u8,
    name: []const u8,
    container_name: []const u8 = "",
    container_label: []const u8 = "",
    start_line: i32,
    end_line: i32,
};

const ParsedSymbol = struct {
    label: []const u8,
    name: []const u8,
};

const PendingRouteDecorator = struct {
    route_path: []const u8,
    route_method: []const u8,
};

const PendingAsyncDecorator = struct {
    broker: []const u8,
    topic: []const u8,
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
    full_callee_name: []const u8 = "",
    file_path: []const u8,
    first_string_arg: []const u8 = "",
    route_path: []const u8 = "",
    route_handler_ref: []const u8 = "",
    route_method: []const u8 = "",
};

pub const UnresolvedImport = struct {
    importer_id: i64,
    import_name: []const u8,
    binding_alias: []const u8,
    file_path: []const u8,
    emit_edge: bool = true,
};

pub const UnresolvedUsage = struct {
    user_id: i64,
    ref_name: []const u8,
    file_path: []const u8,
};

pub const UnresolvedThrow = struct {
    thrower_id: i64,
    exception_name: []const u8,
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
    unresolved_usages: []UnresolvedUsage,
    unresolved_throws: []UnresolvedThrow,
    semantic_hints: []SemanticHint,
};

const TsSymbol = struct {
    symbol_id: i64,
    start_line: i32,
    end_line: i32,
};

pub fn extractFile(
    allocator: std.mem.Allocator,
    project_name: []const u8,
    file: discover.FileInfo,
    gb: *graph_buffer.GraphBuffer,
) !FileExtraction {
    const rel = file.rel_path;
    const file_name = std.fs.path.basename(rel);

    var symbols = std.ArrayList(ExtractedSymbol).empty;
    var tree_sitter_defs = std.ArrayList(TsDefinition).empty;
    var unresolved_calls = std.ArrayList(UnresolvedCall).empty;
    var unresolved_imports = std.ArrayList(UnresolvedImport).empty;
    var unresolved_usages = std.ArrayList(UnresolvedUsage).empty;
    var semantic_hints = std.ArrayList(SemanticHint).empty;
    var unresolved_throws = std.ArrayList(UnresolvedThrow).empty;
    var scope_markers = std.ArrayList(TsSymbol).empty;
    var pending_decorators = std.ArrayList([]const u8).empty;
    var pending_route_decorators = std.ArrayList(PendingRouteDecorator).empty;
    var pending_async_decorators = std.ArrayList(PendingAsyncDecorator).empty;
    errdefer freePendingExtractedSymbols(allocator, &symbols);
    defer freePendingTsDefinitions(allocator, &tree_sitter_defs);
    errdefer freePendingUnresolvedCalls(allocator, &unresolved_calls);
    errdefer freePendingUnresolvedImports(allocator, &unresolved_imports);
    errdefer freePendingUnresolvedUsages(allocator, &unresolved_usages);
    errdefer freePendingUnresolvedThrows(allocator, &unresolved_throws);
    errdefer freePendingSemanticHints(allocator, &semantic_hints);
    defer freePendingStringSlices(allocator, &pending_decorators);
    defer freePendingRouteDecorators(allocator, &pending_route_decorators);
    defer freePendingAsyncDecorators(allocator, &pending_async_decorators);
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
            &unresolved_usages,
            &unresolved_throws,
            &semantic_hints,
        );
    }

    var module_id: i64 = file_id;
    var current_scope_id: i64 = file_id;
    if (file_name.len > 0) {
        const module_qn = try std.fmt.allocPrint(
            allocator,
            "{s}:module:{s}:{s}",
            .{ project_name, qn_base, @tagName(file.language) },
        );
        defer allocator.free(module_qn);

        const created_module = try gb.upsertNode(
            "Module",
            rel,
            module_qn,
            rel,
            1,
            1,
        );
        if (created_module > 0) {
            module_id = created_module;
            _ = gb.insertEdge(file_id, module_id, "DEFINES") catch |err| switch (err) {
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
                &unresolved_usages,
                &unresolved_throws,
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
        const symbol_qn = try treeSitterQualifiedName(allocator, project_name, qn_base, file.language, def);
        const exists = gb.findNodeByQualifiedName(symbol_qn) != null;
        const symbol_props = test_tagging.symbolPropertiesJson(def.label, def.name, rel);
        const symbol_id = if (std.mem.eql(u8, symbol_props, "{}"))
            try gb.upsertNode(
                def.label,
                def.name,
                symbol_qn,
                rel,
                def.start_line,
                def.end_line,
            )
        else
            try gb.upsertNodeWithProperties(
                def.label,
                def.name,
                symbol_qn,
                rel,
                def.start_line,
                def.end_line,
                symbol_props,
            );
        if (symbol_id > 0 and !exists) {
            _ = gb.insertEdge(file_id, symbol_id, "DEFINES") catch |err| switch (err) {
                graph_buffer.GraphBufferError.DuplicateEdge => {},
                else => {
                    allocator.free(symbol_qn);
                    return err;
                },
            };
            if (treeSitterMethodOwner(allocator, project_name, qn_base, file.language, def, gb)) |owner| {
                _ = gb.insertEdge(owner.id, symbol_id, "DEFINES_METHOD") catch |err| switch (err) {
                    graph_buffer.GraphBufferError.DuplicateEdge => {},
                    else => {
                        allocator.free(symbol_qn);
                        return err;
                    },
                };
            }
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
                    .start_line = def.start_line,
                    .end_line = def.end_line,
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
    var active_scope_end_line: i32 = 0;
    while (lines.next()) |line_raw| : (line_no += 1) {
        const line = std.mem.trim(u8, line_raw, " \t");
        if (line.len == 0) continue;

        const clean_line = stripComments(file.language, line);
        if (clean_line.len == 0) continue;

        if (parseDecoratorReference(clean_line)) |decorator_name| {
            try pending_decorators.append(allocator, try allocator.dupe(u8, decorator_name));
            if (parseRouteDecoratorMetadata(clean_line)) |route| {
                try pending_route_decorators.append(allocator, .{
                    .route_path = try allocator.dupe(u8, route.route_path),
                    .route_method = try allocator.dupe(u8, route.method),
                });
            }
            if (parseAsyncDecoratorMetadata(clean_line)) |async_route| {
                try pending_async_decorators.append(allocator, .{
                    .broker = try allocator.dupe(u8, async_route.broker),
                    .topic = try allocator.dupe(u8, async_route.topic),
                });
            }
            try appendUnresolvedUsageRef(allocator, module_id, decorator_name, rel, &unresolved_usages);
            continue;
        }

        if (active_scope_end_line > 0 and line_no > active_scope_end_line) {
            current_scope_id = module_id;
            active_scope_end_line = 0;
        }
        var scope_starts_here = false;
        var selected_scope_id = current_scope_id;
        var selected_scope_end = active_scope_end_line;
        while (scope_index < scope_markers.items.len and scope_markers.items[scope_index].start_line == line_no) : (scope_index += 1) {
            const marker = scope_markers.items[scope_index];
            if (!scope_starts_here or (marker.end_line - marker.start_line) <= (selected_scope_end - line_no)) {
                selected_scope_id = marker.symbol_id;
                selected_scope_end = marker.end_line;
            }
            scope_starts_here = true;
        }
        if (scope_starts_here) {
            current_scope_id = selected_scope_id;
            active_scope_end_line = selected_scope_end;
        }

        const parsed_symbol = parseSymbol(file.language, clean_line);
        if (parsed_symbol) |sym| {
            const parsed_end_line = estimateParsedSymbolEndLine(bytes, file.language, line_no, sym);
            const tree_sitter_owns_declaration = supportsTreeSitterDefs(file.language) and scope_starts_here and current_scope_id != module_id;
            var decl_node_id: i64 = 0;
            if (tree_sitter_owns_declaration) {
                decl_node_id = current_scope_id;
            } else {
                if (parsedMethodOwner(gb, current_scope_id, module_id, sym)) |owner| {
                    decl_node_id = try addScopedMethodFromParsed(
                        allocator,
                        project_name,
                        qn_base,
                        rel,
                        file.language,
                        line_no,
                        parsed_end_line,
                        sym.name,
                        owner,
                        gb,
                        file_id,
                        &symbols,
                    );
                } else {
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
                        parsed_end_line,
                        sym,
                        gb,
                        file_id,
                        module_id,
                        &symbols,
                    ) catch |err| switch (err) {
                        error.OutOfMemory => return err,
                        else => {},
                    };
                    if (gb.findNodeByQualifiedName(symbol_qn)) |decl_node| {
                        decl_node_id = decl_node.id;
                    }
                }
            }
            if (sym.label.len > 0 and isDeclarationLabel(sym.label)) {
                if (decl_node_id != 0) {
                    current_scope_id = decl_node_id;
                    if (parsed_end_line > line_no and parsed_end_line > active_scope_end_line) {
                        active_scope_end_line = parsed_end_line;
                    }
                    for (pending_decorators.items) |decorator_name| {
                        try semantic_hints.append(allocator, .{
                            .child_id = decl_node_id,
                            .parent_name = try allocator.dupe(u8, decorator_name),
                            .file_path = try allocator.dupe(u8, rel),
                            .relation = try allocator.dupe(u8, "DECORATES"),
                        });
                    }
                    if (gb.findNodeById(decl_node_id)) |decl_node| {
                        for (pending_route_decorators.items) |route| {
                            try emitDecoratorRoute(allocator, gb, decl_node, rel, route);
                        }
                        for (pending_async_decorators.items) |async_route| {
                            try emitAsyncDecoratorRoute(allocator, gb, decl_node, rel, async_route);
                        }
                    }
                    for (pending_decorators.items) |decorator_name| allocator.free(decorator_name);
                    pending_decorators.clearRetainingCapacity();
                    for (pending_route_decorators.items) |route| {
                        allocator.free(route.route_path);
                        allocator.free(route.route_method);
                    }
                    pending_route_decorators.clearRetainingCapacity();
                    for (pending_async_decorators.items) |async_route| {
                        allocator.free(async_route.broker);
                        allocator.free(async_route.topic);
                    }
                    pending_async_decorators.clearRetainingCapacity();
                }
            }
        }
        if (parsed_symbol == null) {
            try appendSupplementalDefinitions(
                allocator,
                project_name,
                qn_base,
                file.language,
                line_raw,
                rel,
                line_no,
                gb,
                file_id,
                current_scope_id,
                module_id,
                &symbols,
            );
        }
        try parseImports(
            allocator,
            file.language,
            clean_line,
            file_id,
            rel,
            &unresolved_imports,
        );

        try appendSemanticHints(
            allocator,
            file.language,
            clean_line,
            current_scope_id,
            rel,
            &semantic_hints,
        );
        try appendModuleDeclarationUsages(
            allocator,
            file.language,
            clean_line,
            module_id,
            rel,
            &unresolved_usages,
        );
        try appendRustModuleFieldTypeUsages(
            allocator,
            file.language,
            clean_line,
            current_scope_id,
            module_id,
            rel,
            gb,
            &unresolved_usages,
        );

        const collect_definition_calls_at_module = shouldCollectDefinitionCallsAtModuleScope(file.language, clean_line, parsed_symbol);
        const call_scope_id = if (collect_definition_calls_at_module) module_id else current_scope_id;
        const route_metadata = parseRouteRegistrationMetadata(clean_line);
        const callee_names = collectCalls(
            allocator,
            clean_line,
            file.language,
            parsed_symbol,
            call_scope_id,
            module_id,
            scope_starts_here,
        ) catch |err| switch (err) {
            error.OutOfMemory => return err,
        };
        if (callee_names) |names| {
            defer freeStringSlices(allocator, names);
            for (names) |callee| {
                if (callee.len == 0) continue;
                const caller_id = if (call_scope_id != 0) call_scope_id else module_id;
                const route_call = if (route_metadata) |meta|
                    std.mem.eql(u8, callee, meta.callee_leaf)
                else
                    false;
                const call_metadata = parseCallLineMetadataForLeaf(clean_line, callee);
                try unresolved_calls.append(allocator, .{
                    .caller_id = caller_id,
                    .callee_name = try allocator.dupe(u8, callee),
                    .full_callee_name = try allocator.dupe(u8, if (route_call)
                        route_metadata.?.callee_full
                    else if (call_metadata) |meta|
                        meta.callee_full
                    else
                        callee),
                    .file_path = try allocator.dupe(u8, rel),
                    .first_string_arg = if (call_metadata) |meta| try allocator.dupe(u8, meta.first_string_arg) else "",
                    .route_path = if (route_call) try allocator.dupe(u8, route_metadata.?.route_path) else "",
                    .route_handler_ref = if (route_call) try allocator.dupe(u8, route_metadata.?.handler_ref) else "",
                    .route_method = if (route_call) try allocator.dupe(u8, route_metadata.?.method) else "",
                });
            }
        }

        const usage_names = collectUsages(
            allocator,
            clean_line,
            file.language,
            parsed_symbol,
            current_scope_id,
            module_id,
        ) catch |err| switch (err) {
            error.OutOfMemory => return err,
        };
        if (usage_names) |names| {
            defer freeStringSlices(allocator, names);
            for (names) |ref_name| {
                if (ref_name.len == 0) continue;
                const user_id = usageOwnerForLine(parsed_symbol, current_scope_id, module_id);
                try unresolved_usages.append(allocator, .{
                    .user_id = user_id,
                    .ref_name = try allocator.dupe(u8, ref_name),
                    .file_path = try allocator.dupe(u8, rel),
                });
            }
        }

        if (parseThrowException(file.language, clean_line)) |exception_name| {
            const thrower_id = if (current_scope_id != 0) current_scope_id else module_id;
            try unresolved_throws.append(allocator, .{
                .thrower_id = thrower_id,
                .exception_name = try allocator.dupe(u8, exception_name),
                .file_path = try allocator.dupe(u8, rel),
            });
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
        &unresolved_usages,
        &unresolved_throws,
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
        .go => try parseGoImports(allocator, line, importer_id, file_path, out),
        .java => try parseJavaImports(allocator, line, importer_id, file_path, out),
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
                    .binding_alias = try allocator.dupe(u8, ""),
                    .file_path = try allocator.dupe(u8, file_path),
                    .emit_edge = true,
                });
                const imported = std.mem.trim(u8, after_from[import_kw.? + " import ".len ..], " \t");
                var imported_names = std.mem.splitSequence(u8, imported, ",");
                while (imported_names.next()) |raw_name| {
                    const parsed = parseImportBinding(raw_name);
                    if (parsed.target.len == 0) continue;
                    const namespace = try joinImportNamespace(allocator, module, parsed.target, '.');
                    defer allocator.free(namespace);
                    try out.append(allocator, .{
                        .importer_id = importer_id,
                        .import_name = try allocator.dupe(u8, namespace),
                        .binding_alias = try allocator.dupe(u8, importAliasOrDefault(parsed.target, parsed.alias)),
                        .file_path = try allocator.dupe(u8, file_path),
                        .emit_edge = false,
                    });
                }
            }
        }
    } else if (import_pos != null) {
        const after_import = std.mem.trim(u8, trimmed[import_pos.? + "import ".len ..], " \t");
        var modules = std.mem.splitSequence(u8, after_import, ",");
        while (modules.next()) |raw| {
            const parsed = parseImportBinding(raw);
            if (parsed.target.len == 0) continue;
            try out.append(allocator, .{
                .importer_id = importer_id,
                .import_name = try allocator.dupe(u8, parsed.target),
                .binding_alias = try allocator.dupe(u8, importAliasOrDefault(parsed.target, parsed.alias)),
                .file_path = try allocator.dupe(u8, file_path),
                .emit_edge = true,
            });
        }
    }
}

fn parseGoImports(
    allocator: std.mem.Allocator,
    line: []const u8,
    importer_id: i64,
    file_path: []const u8,
    out: *std.ArrayList(UnresolvedImport),
) !void {
    const trimmed = std.mem.trim(u8, line, " \t");
    if (!std.mem.startsWith(u8, trimmed, "import ")) return;
    var tail = std.mem.trim(u8, trimmed["import ".len..], " \t");
    if (tail.len == 0 or tail[0] == '(') return;

    var alias: []const u8 = "";
    if (tail[0] != '"' and tail[0] != '`') {
        const first_space = std.mem.indexOfScalar(u8, tail, ' ') orelse return;
        alias = std.mem.trim(u8, tail[0..first_space], " \t");
        tail = std.mem.trim(u8, tail[first_space + 1 ..], " \t");
    }

    const spec = extractQuotedString(tail) orelse return;
    try out.append(allocator, .{
        .importer_id = importer_id,
        .import_name = try allocator.dupe(u8, spec),
        .binding_alias = try allocator.dupe(u8, alias),
        .file_path = try allocator.dupe(u8, file_path),
    });
}

fn parseJavaImports(
    allocator: std.mem.Allocator,
    line: []const u8,
    importer_id: i64,
    file_path: []const u8,
    out: *std.ArrayList(UnresolvedImport),
) !void {
    const trimmed = std.mem.trim(u8, line, " \t");
    if (!std.mem.startsWith(u8, trimmed, "import ")) return;
    var tail = std.mem.trim(u8, trimmed["import ".len..], " \t;");
    if (std.mem.startsWith(u8, tail, "static ")) {
        tail = std.mem.trim(u8, tail["static ".len..], " \t;");
    }
    if (tail.len == 0) return;
    try out.append(allocator, .{
        .importer_id = importer_id,
        .import_name = try allocator.dupe(u8, tail),
        .binding_alias = try allocator.dupe(u8, lastImportSegment(tail)),
        .file_path = try allocator.dupe(u8, file_path),
    });
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
            const bindings = std.mem.trim(u8, tail[0..from_pos.?], " \t");
            if (extractQuotedString(tail[from_pos.? + " from ".len ..])) |spec| {
                try appendJsImportBindings(allocator, importer_id, file_path, spec, bindings, out);
            }
            return;
        }
        if (std.mem.startsWith(u8, tail, "require(")) {
            if (extractQuotedString(tail["require(".len..])) |spec| {
                try out.append(allocator, .{
                    .importer_id = importer_id,
                    .import_name = try allocator.dupe(u8, spec),
                    .binding_alias = try allocator.dupe(u8, ""),
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
            const alias = parseRequireAlias(trimmed[0..req_pos]);
            try out.append(allocator, .{
                .importer_id = importer_id,
                .import_name = try allocator.dupe(u8, spec),
                .binding_alias = try allocator.dupe(u8, alias),
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

    try appendRustImportBindings(allocator, importer_id, file_path, path_raw, path, out);
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
    const alias = parseZigImportAlias(line);
    try out.append(allocator, .{
        .importer_id = importer_id,
        .import_name = try allocator.dupe(u8, spec),
        .binding_alias = try allocator.dupe(u8, alias),
        .file_path = try allocator.dupe(u8, file_path),
    });
}

const ImportBindingParts = struct {
    target: []const u8,
    alias: []const u8,
};

fn parseImportBinding(raw: []const u8) ImportBindingParts {
    const trimmed = std.mem.trim(u8, raw, " \t{};");
    if (trimmed.len == 0) return .{ .target = "", .alias = "" };
    if (std.mem.indexOf(u8, trimmed, " as ")) |as_pos| {
        const target = std.mem.trim(u8, trimmed[0..as_pos], " \t");
        const alias = std.mem.trim(u8, trimmed[as_pos + " as ".len ..], " \t");
        return .{ .target = target, .alias = if (alias.len > 0) alias else target };
    }
    if (std.mem.indexOf(u8, trimmed, "::") == null) {
        if (std.mem.indexOfScalar(u8, trimmed, ':')) |colon| {
            const left = std.mem.trim(u8, trimmed[0..colon], " \t");
            const right = std.mem.trim(u8, trimmed[colon + 1 ..], " \t");
            if (left.len > 0 and right.len > 0) {
                return .{ .target = left, .alias = right };
            }
        }
    }
    return .{ .target = trimmed, .alias = "" };
}

fn importAliasOrDefault(target: []const u8, explicit_alias: []const u8) []const u8 {
    if (explicit_alias.len > 0) return explicit_alias;
    return lastImportSegment(target);
}

fn lastImportSegment(target: []const u8) []const u8 {
    if (target.len == 0) return "";
    var start: usize = 0;
    var i: usize = 0;
    while (i < target.len) : (i += 1) {
        if (target[i] == '/' or target[i] == '\\' or target[i] == '.') {
            start = i + 1;
            continue;
        }
        if (target[i] == ':') {
            if (i + 1 < target.len and target[i + 1] == ':') {
                start = i + 2;
                i += 1;
            } else {
                start = i + 1;
            }
        }
    }
    return target[start..];
}

fn joinImportNamespace(
    allocator: std.mem.Allocator,
    namespace: []const u8,
    target: []const u8,
    sep: u8,
) ![]u8 {
    if (namespace.len == 0) return allocator.dupe(u8, target);
    if (target.len == 0) return allocator.dupe(u8, namespace);
    return std.fmt.allocPrint(allocator, "{s}{c}{s}", .{ namespace, sep, target });
}

fn appendJsImportBindings(
    allocator: std.mem.Allocator,
    importer_id: i64,
    file_path: []const u8,
    spec: []const u8,
    bindings: []const u8,
    out: *std.ArrayList(UnresolvedImport),
) !void {
    const trimmed = std.mem.trim(u8, bindings, " \t");
    if (trimmed.len == 0) return;

    if (std.mem.startsWith(u8, trimmed, "* as ")) {
        const alias = std.mem.trim(u8, trimmed["* as ".len..], " \t");
        if (alias.len == 0) return;
        try out.append(allocator, .{
            .importer_id = importer_id,
            .import_name = try allocator.dupe(u8, spec),
            .binding_alias = try allocator.dupe(u8, alias),
            .file_path = try allocator.dupe(u8, file_path),
        });
        return;
    }

    const brace_open = std.mem.indexOfScalar(u8, trimmed, '{');
    const brace_close = std.mem.indexOfScalar(u8, trimmed, '}');
    if (brace_open != null and brace_close != null and brace_open.? < brace_close.?) {
        const before = std.mem.trim(u8, trimmed[0..brace_open.?], " \t,");
        if (before.len > 0) {
            try out.append(allocator, .{
                .importer_id = importer_id,
                .import_name = try allocator.dupe(u8, spec),
                .binding_alias = try allocator.dupe(u8, before),
                .file_path = try allocator.dupe(u8, file_path),
            });
        }

        const members = trimmed[brace_open.? + 1 .. brace_close.?];
        var iter = std.mem.splitSequence(u8, members, ",");
        while (iter.next()) |raw_member| {
            const parsed = parseImportBinding(raw_member);
            if (parsed.target.len == 0) continue;
            const namespace = try joinImportNamespace(allocator, spec, parsed.target, '.');
            defer allocator.free(namespace);
            try out.append(allocator, .{
                .importer_id = importer_id,
                .import_name = try allocator.dupe(u8, namespace),
                .binding_alias = try allocator.dupe(u8, importAliasOrDefault(parsed.target, parsed.alias)),
                .file_path = try allocator.dupe(u8, file_path),
            });
        }
        return;
    }

    try out.append(allocator, .{
        .importer_id = importer_id,
        .import_name = try allocator.dupe(u8, spec),
        .binding_alias = try allocator.dupe(u8, trimmed),
        .file_path = try allocator.dupe(u8, file_path),
    });
}

fn appendRustImportBindings(
    allocator: std.mem.Allocator,
    importer_id: i64,
    file_path: []const u8,
    path_raw: []const u8,
    normalized_path: []const u8,
    out: *std.ArrayList(UnresolvedImport),
) !void {
    if (std.mem.indexOf(u8, path_raw, "::{")) |group_pos| {
        const base = std.mem.trim(u8, path_raw[0..group_pos], " \t");
        const open_brace = std.mem.indexOfScalarPos(u8, path_raw, group_pos, '{') orelse return;
        const close_brace = std.mem.lastIndexOfScalar(u8, path_raw, '}') orelse return;
        if (close_brace <= open_brace) return;
        var iter = std.mem.splitSequence(u8, path_raw[open_brace + 1 .. close_brace], ",");
        while (iter.next()) |raw_member| {
            const parsed = parseImportBinding(raw_member);
            if (parsed.target.len == 0) continue;
            const namespace = try std.fmt.allocPrint(allocator, "{s}::{s}", .{ std.mem.trim(u8, base, " \t"), parsed.target });
            defer allocator.free(namespace);
            try out.append(allocator, .{
                .importer_id = importer_id,
                .import_name = try allocator.dupe(u8, namespace),
                .binding_alias = try allocator.dupe(u8, importAliasOrDefault(parsed.target, parsed.alias)),
                .file_path = try allocator.dupe(u8, file_path),
            });
        }
        return;
    }

    _ = normalized_path;
    const parsed = parseImportBinding(path_raw);
    if (parsed.target.len == 0) return;
    try out.append(allocator, .{
        .importer_id = importer_id,
        .import_name = try allocator.dupe(u8, parsed.target),
        .binding_alias = try allocator.dupe(u8, importAliasOrDefault(parsed.target, parsed.alias)),
        .file_path = try allocator.dupe(u8, file_path),
    });
}

fn parseRequireAlias(prefix: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, prefix, " \t=");
    if (trimmed.len == 0) return "";
    if (std.mem.startsWith(u8, trimmed, "const ")) return std.mem.trim(u8, trimmed["const ".len..], " \t");
    if (std.mem.startsWith(u8, trimmed, "let ")) return std.mem.trim(u8, trimmed["let ".len..], " \t");
    if (std.mem.startsWith(u8, trimmed, "var ")) return std.mem.trim(u8, trimmed["var ".len..], " \t");
    return "";
}

fn parseZigImportAlias(line: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, line, " \t");
    if (std.mem.startsWith(u8, trimmed, "pub const ")) {
        return extractPrefixName(trimmed, "pub const ") orelse "";
    }
    if (std.mem.startsWith(u8, trimmed, "const ")) {
        return extractPrefixName(trimmed, "const ") orelse "";
    }
    return "";
}

fn appendSemanticHints(
    allocator: std.mem.Allocator,
    language: discover.Language,
    line: []const u8,
    child_id: i64,
    file_path: []const u8,
    out: *std.ArrayList(SemanticHint),
) !void {
    _ = allocator;
    _ = language;
    _ = line;
    _ = child_id;
    _ = file_path;
    _ = out;
}

fn parseRustSemanticHint(line: []const u8) ?struct {
    relation: []const u8,
    trait_name: []const u8,
} {
    const parts = parseRustImplParts(line) orelse return null;
    const trait_name = parts.trait_name orelse return null;
    return .{ .relation = "IMPLEMENTS", .trait_name = trait_name };
}

fn appendSemanticHint(
    allocator: std.mem.Allocator,
    child_id: i64,
    file_path: []const u8,
    parent_name: []const u8,
    relation: []const u8,
    out: *std.ArrayList(SemanticHint),
) !void {
    if (parent_name.len == 0) return;
    try out.append(allocator, .{
        .child_id = child_id,
        .parent_name = try allocator.dupe(u8, parent_name),
        .file_path = try allocator.dupe(u8, file_path),
        .relation = try allocator.dupe(u8, relation),
    });
}

fn appendDelimitedSemanticHints(
    allocator: std.mem.Allocator,
    child_id: i64,
    file_path: []const u8,
    raw_names: ?[]const u8,
    relation: []const u8,
    out: *std.ArrayList(SemanticHint),
) !void {
    const names = raw_names orelse return;
    var iter = std.mem.splitSequence(u8, names, ",");
    while (iter.next()) |raw_name| {
        if (normalizeReferenceName(raw_name)) |name| {
            try appendSemanticHint(allocator, child_id, file_path, name, relation, out);
        }
    }
}

fn appendModuleDeclarationUsages(
    allocator: std.mem.Allocator,
    language: discover.Language,
    line: []const u8,
    module_id: i64,
    file_path: []const u8,
    out: *std.ArrayList(UnresolvedUsage),
) !void {
    if (module_id == 0) return;

    switch (language) {
        .python => try appendDelimitedUnresolvedUsages(
            allocator,
            module_id,
            file_path,
            parsePythonInheritanceList(line),
            out,
        ),
        .javascript => if (parseJsInheritance(line)) |parent_name| {
            try appendUnresolvedUsageRef(allocator, module_id, parent_name, file_path, out);
        },
        .rust => if (parseRustImplParts(line)) |parts| {
            try appendUnresolvedUsageRef(allocator, module_id, parts.target_name, file_path, out);
        },
        else => {},
    }
}

fn appendUnresolvedUsageRef(
    allocator: std.mem.Allocator,
    user_id: i64,
    ref_name: []const u8,
    file_path: []const u8,
    out: *std.ArrayList(UnresolvedUsage),
) !void {
    if (user_id == 0 or ref_name.len == 0) return;
    try out.append(allocator, .{
        .user_id = user_id,
        .ref_name = try allocator.dupe(u8, ref_name),
        .file_path = try allocator.dupe(u8, file_path),
    });
}

fn appendRustModuleFieldTypeUsages(
    allocator: std.mem.Allocator,
    language: discover.Language,
    line: []const u8,
    current_scope_id: i64,
    module_id: i64,
    file_path: []const u8,
    gb: *const graph_buffer.GraphBuffer,
    out: *std.ArrayList(UnresolvedUsage),
) !void {
    if (language != .rust or module_id == 0 or current_scope_id == 0 or current_scope_id == module_id) return;
    const scope_node = gb.findNodeById(current_scope_id) orelse return;
    if (!std.mem.eql(u8, scope_node.label, "Class")) return;
    if (std.mem.indexOfScalar(u8, line, '(') != null) return;

    var names: std.ArrayList([]const u8) = .empty;
    defer freePendingStringSlices(allocator, &names);
    try appendReferencesAfterMarker(allocator, line, ":", &names);
    dedupeStringArray(allocator, &names);
    for (names.items) |name| {
        try appendUnresolvedUsageRef(allocator, module_id, name, file_path, out);
    }
}

fn appendDelimitedUnresolvedUsages(
    allocator: std.mem.Allocator,
    user_id: i64,
    file_path: []const u8,
    raw_names: ?[]const u8,
    out: *std.ArrayList(UnresolvedUsage),
) !void {
    const names = raw_names orelse return;
    var iter = std.mem.splitSequence(u8, names, ",");
    while (iter.next()) |raw_name| {
        if (normalizeReferenceName(raw_name)) |name| {
            try appendUnresolvedUsageRef(allocator, user_id, name, file_path, out);
        }
    }
}

fn collectUsages(
    allocator: std.mem.Allocator,
    line: []const u8,
    language: discover.Language,
    parsed_symbol: ?ParsedSymbol,
    current_scope_id: i64,
    module_id: i64,
) !?[]const []const u8 {
    _ = current_scope_id;
    _ = module_id;
    if (line.len == 0) return null;
    if (isImportLine(language, line)) return null;

    var names: std.ArrayList([]const u8) = .empty;
    errdefer freePendingStringSlices(allocator, &names);

    if (parsed_symbol != null) {
        try appendTypeUsageCandidates(allocator, language, line, &names);
    }
    if (parsed_symbol) |sym| {
        if (!isDeclarationLabel(sym.label)) {
            try appendBareUsageCandidates(allocator, line, language, &names);
        } else {
            if (names.items.len == 0) return null;
            dedupeStringArray(allocator, &names);
            return try names.toOwnedSlice(allocator);
        }
    } else {
        try appendBareUsageCandidates(allocator, line, language, &names);
    }

    if (names.items.len == 0) return null;
    dedupeStringArray(allocator, &names);
    return try names.toOwnedSlice(allocator);
}

fn usageOwnerForLine(parsed_symbol: ?ParsedSymbol, current_scope_id: i64, module_id: i64) i64 {
    const fallback = if (current_scope_id != 0) current_scope_id else module_id;
    const symbol = parsed_symbol orelse return fallback;
    if (std.mem.eql(u8, symbol.label, "Function") or std.mem.eql(u8, symbol.label, "Method")) {
        return fallback;
    }
    if (isDeclarationLabel(symbol.label)) {
        return if (module_id != 0) module_id else fallback;
    }
    return fallback;
}

fn collectCalls(
    allocator: std.mem.Allocator,
    line: []const u8,
    language: discover.Language,
    parsed_symbol: ?ParsedSymbol,
    current_scope_id: i64,
    module_id: i64,
    scope_starts_here: bool,
) !?[]const []const u8 {
    if (line.len == 0) return null;
    const allow_definition_calls = shouldCollectDefinitionCallsAtModuleScope(language, line, parsed_symbol);
    if (parsed_symbol) |sym| {
        if (!allow_definition_calls and shouldSkipDeclarationCalls(sym.label, current_scope_id, module_id)) return null;
    } else if (scope_starts_here or isDeclarationLine(language, line)) {
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
            if (!isKeywordCandidate(callee) and !isConstructorCall(line, start)) {
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

const RouteRegistrationMetadata = struct {
    callee_leaf: []const u8,
    callee_full: []const u8,
    route_path: []const u8,
    handler_ref: []const u8,
    method: []const u8,
};

const RouteDecoratorMetadata = struct {
    callee_full: []const u8,
    route_path: []const u8,
    method: []const u8,
};

const AsyncDecoratorMetadata = struct {
    callee_full: []const u8,
    broker: []const u8,
    topic: []const u8,
};

const CallLineMetadata = struct {
    callee_full: []const u8,
    first_string_arg: []const u8,
};

fn parseCallLineMetadataForLeaf(line: []const u8, callee_leaf: []const u8) ?CallLineMetadata {
    var search_start: usize = 0;
    while (search_start < line.len) {
        const paren = std.mem.indexOfScalarPos(u8, line, search_start, '(') orelse return null;
        const callee_full = calleeBeforeParen(line, paren) orelse {
            search_start = paren + 1;
            continue;
        };
        if (!std.mem.eql(u8, lastDottedSegment(callee_full), callee_leaf)) {
            search_start = paren + 1;
            continue;
        }
        const close = matchingParen(line, paren) orelse line.len;
        const args = line[paren + 1 .. close];
        return .{
            .callee_full = callee_full,
            .first_string_arg = firstStringArg(args) orelse "",
        };
    }
    return null;
}

fn parseRouteRegistrationMetadata(line: []const u8) ?RouteRegistrationMetadata {
    var search_start: usize = 0;
    while (search_start < line.len) {
        const paren_rel = std.mem.indexOfScalarPos(u8, line, search_start, '(') orelse return null;
        const paren = paren_rel;
        const callee_full = calleeBeforeParen(line, paren) orelse {
            search_start = paren + 1;
            continue;
        };
        const method = routeRegistrationMethod(callee_full) orelse {
            search_start = paren + 1;
            continue;
        };
        if (!looksLikeRouteRegistrar(callee_full)) {
            search_start = paren + 1;
            continue;
        }
        const close = matchingParen(line, paren) orelse line.len;
        const args = line[paren + 1 .. close];
        const route_path = firstRoutePathArg(args) orelse {
            search_start = paren + 1;
            continue;
        };
        const handler_ref = handlerRefAfterRoutePath(args, route_path) orelse {
            search_start = paren + 1;
            continue;
        };
        if (handler_ref.len == 0) {
            search_start = paren + 1;
            continue;
        }
        return .{
            .callee_leaf = lastDottedSegment(callee_full),
            .callee_full = callee_full,
            .route_path = route_path,
            .handler_ref = handler_ref,
            .method = method,
        };
    }
    return null;
}

fn parseRouteDecoratorMetadata(line: []const u8) ?RouteDecoratorMetadata {
    const trimmed = std.mem.trim(u8, line, " \t");
    if (!std.mem.startsWith(u8, trimmed, "@")) return null;
    const decorator = trimmed[1..];
    const paren = std.mem.indexOfScalar(u8, decorator, '(') orelse return null;
    const callee_full = std.mem.trim(u8, decorator[0..paren], " \t");
    if (callee_full.len == 0) return null;
    const method = routeRegistrationMethod(callee_full) orelse return null;
    if (!looksLikeRouteRegistrar(callee_full)) return null;
    const close = matchingParen(decorator, paren) orelse decorator.len;
    const args = decorator[paren + 1 .. close];
    const route_path = firstRoutePathArg(args) orelse return null;
    return .{
        .callee_full = callee_full,
        .route_path = route_path,
        .method = method,
    };
}

fn parseAsyncDecoratorMetadata(line: []const u8) ?AsyncDecoratorMetadata {
    const trimmed = std.mem.trim(u8, line, " \t");
    if (!std.mem.startsWith(u8, trimmed, "@")) return null;
    const decorator = trimmed[1..];
    const paren = std.mem.indexOfScalar(u8, decorator, '(') orelse return null;
    const callee_full = std.mem.trim(u8, decorator[0..paren], " \t");
    if (callee_full.len == 0) return null;
    if (service_patterns.classify(callee_full) != .async_broker) return null;
    const broker = service_patterns.asyncBroker(callee_full) orelse return null;
    const close = matchingParen(decorator, paren) orelse decorator.len;
    const args = decorator[paren + 1 .. close];
    const topic = firstAsyncTopicArg(args) orelse return null;
    return .{
        .callee_full = callee_full,
        .broker = broker,
        .topic = topic,
    };
}

fn emitDecoratorRoute(
    allocator: std.mem.Allocator,
    gb: *graph_buffer.GraphBuffer,
    decl_node: *const graph_buffer.BufferNode,
    file_path: []const u8,
    route: PendingRouteDecorator,
) !void {
    const handler_id = decl_node.id;
    const handler_qn = try allocator.dupe(u8, decl_node.qualified_name);
    defer allocator.free(handler_qn);

    const route_id = try routes.upsertHttpRoute(
        allocator,
        gb,
        file_path,
        route.route_method,
        route.route_path,
        "decorator",
    );

    const handler_props = try std.fmt.allocPrint(
        allocator,
        "{{\"handler\":\"{s}\"}}",
        .{handler_qn},
    );
    defer allocator.free(handler_props);

    _ = gb.insertEdgeWithProperties(handler_id, route_id, "HANDLES", handler_props) catch |err| switch (err) {
        graph_buffer.GraphBufferError.DuplicateEdge => {},
        else => return err,
    };
}

fn emitAsyncDecoratorRoute(
    allocator: std.mem.Allocator,
    gb: *graph_buffer.GraphBuffer,
    decl_node: *const graph_buffer.BufferNode,
    file_path: []const u8,
    route: PendingAsyncDecorator,
) !void {
    const handler_qn = try allocator.dupe(u8, decl_node.qualified_name);
    defer allocator.free(handler_qn);

    const route_id = try routes.upsertAsyncRoute(
        allocator,
        gb,
        file_path,
        route.broker,
        route.topic,
        "decorator",
    );

    const handler_props = try std.fmt.allocPrint(
        allocator,
        "{{\"handler\":\"{s}\",\"broker\":\"{s}\"}}",
        .{ handler_qn, route.broker },
    );
    defer allocator.free(handler_props);

    _ = gb.insertEdgeWithProperties(decl_node.id, route_id, "HANDLES", handler_props) catch |err| switch (err) {
        graph_buffer.GraphBufferError.DuplicateEdge => {},
        else => return err,
    };
}

fn calleeBeforeParen(line: []const u8, paren: usize) ?[]const u8 {
    if (paren == 0) return null;
    var end = paren;
    while (end > 0 and std.ascii.isWhitespace(line[end - 1])) end -= 1;
    var start = end;
    while (start > 0) {
        const ch = line[start - 1];
        if (isIdentifierChar(ch) or ch == '.') {
            start -= 1;
            continue;
        }
        break;
    }
    if (start == end) return null;
    return line[start..end];
}

fn matchingParen(line: []const u8, open: usize) ?usize {
    var depth: usize = 0;
    var quote: u8 = 0;
    var escaped = false;
    var idx = open;
    while (idx < line.len) : (idx += 1) {
        const ch = line[idx];
        if (quote != 0) {
            if (escaped) {
                escaped = false;
            } else if (ch == '\\') {
                escaped = true;
            } else if (ch == quote) {
                quote = 0;
            }
            continue;
        }
        if (ch == '"' or ch == '\'' or ch == '`') {
            quote = ch;
            continue;
        }
        if (ch == '(') {
            depth += 1;
            continue;
        }
        if (ch == ')') {
            if (depth == 0) return null;
            depth -= 1;
            if (depth == 0) return idx;
        }
    }
    return null;
}

fn firstRoutePathArg(args: []const u8) ?[]const u8 {
    const first = firstStringArg(args) orelse return null;
    if (first.len > 0 and first[0] == '/') return first;
    return null;
}

fn firstAsyncTopicArg(args: []const u8) ?[]const u8 {
    const first = firstStringArg(args) orelse return null;
    if (first.len == 0 or first[0] == '/') return null;
    return first;
}

fn firstStringArg(args: []const u8) ?[]const u8 {
    var idx: usize = 0;
    while (idx < args.len) : (idx += 1) {
        const ch = args[idx];
        if (ch != '"' and ch != '\'' and ch != '`') continue;
        const quote = ch;
        const start = idx + 1;
        idx = start;
        var escaped = false;
        while (idx < args.len) : (idx += 1) {
            if (escaped) {
                escaped = false;
                continue;
            }
            if (args[idx] == '\\') {
                escaped = true;
                continue;
            }
            if (args[idx] == quote) break;
        }
        if (idx <= args.len and start < idx) {
            return args[start..idx];
        }
    }
    return null;
}

fn handlerRefAfterRoutePath(args: []const u8, route_path: []const u8) ?[]const u8 {
    const path_pos = std.mem.indexOf(u8, args, route_path) orelse return null;
    var idx = path_pos + route_path.len;
    while (idx < args.len and args[idx] != ',') : (idx += 1) {}
    if (idx >= args.len) return null;
    idx += 1;
    while (idx < args.len and std.ascii.isWhitespace(args[idx])) : (idx += 1) {}
    if (idx >= args.len) return null;
    if (args[idx] == '"' or args[idx] == '\'' or args[idx] == '`' or args[idx] == '{' or args[idx] == '[') return null;

    const start = idx;
    while (idx < args.len and (isIdentifierChar(args[idx]) or args[idx] == '.')) : (idx += 1) {}
    if (idx == start) return null;
    const ref = args[start..idx];
    if (isKeywordCandidate(ref)) return null;
    return ref;
}

fn routeRegistrationMethod(callee_full: []const u8) ?[]const u8 {
    return service_patterns.routeMethod(callee_full);
}

fn looksLikeRouteRegistrar(callee_full: []const u8) bool {
    if (std.mem.indexOfScalar(u8, callee_full, '.') == null) return false;
    const receiver = callee_full[0 .. callee_full.len - lastDottedSegment(callee_full).len];
    const hints: []const []const u8 = &.{
        "app",
        "api",
        "router",
        "route",
        "routes",
        "server",
        "express",
        "fastify",
        "hono",
        "koa",
        "hapi",
        "flask",
        "blueprint",
        "mux",
        "chi",
        "echo",
        "fiber",
    };
    for (hints) |hint| {
        if (std.mem.indexOf(u8, receiver, hint) != null) return true;
    }
    return false;
}

fn lastDottedSegment(value: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, value, '.')) |idx| {
        return value[idx + 1 ..];
    }
    return value;
}

fn shouldCollectDefinitionCallsAtModuleScope(
    language: discover.Language,
    line: []const u8,
    parsed_symbol: ?ParsedSymbol,
) bool {
    const symbol = parsed_symbol orelse return false;
    switch (language) {
        .javascript, .typescript, .tsx => {},
        else => return false,
    }
    if (!std.mem.eql(u8, symbol.label, "Function")) return false;
    if (std.mem.indexOfScalar(u8, line, '=') == null) return false;
    if (std.mem.indexOfScalar(u8, line, '(') == null) return false;
    return std.mem.indexOf(u8, line, "function") != null or std.mem.indexOf(u8, line, "=>") != null;
}

fn isConstructorCall(line: []const u8, ident_start: usize) bool {
    var idx = ident_start;
    while (idx > 0 and std.ascii.isWhitespace(line[idx - 1])) : (idx -= 1) {}
    if (idx < 3) return false;
    if (!std.mem.eql(u8, line[idx - 3 .. idx], "new")) return false;
    if (idx > 3 and isIdentifierChar(line[idx - 4])) return false;
    return true;
}

fn parseSymbol(language: discover.Language, line: []const u8) ?ParsedSymbol {
    return switch (language) {
        .go => parseGoDefs(line),
        .java => parseJavaDefs(line),
        .python => parsePythonDefs(line),
        .javascript, .typescript, .tsx => parseJsDefs(line),
        .rust => parseRustDefs(line),
        .zig => parseZigDefs(line),
        .yaml => parseYamlDefs(line),
        .toml => parseTomlDefs(line),
        else => null,
    };
}

fn isDeclarationLabel(label: []const u8) bool {
    return std.mem.eql(u8, label, "Function") or
        std.mem.eql(u8, label, "Method") or
        std.mem.eql(u8, label, "Class") or
        std.mem.eql(u8, label, "Struct") or
        std.mem.eql(u8, label, "Trait") or
        std.mem.eql(u8, label, "Interface") or
        std.mem.eql(u8, label, "Test");
}

fn shouldSkipDeclarationCalls(label: []const u8, current_scope_id: i64, module_id: i64) bool {
    if (isDeclarationLabel(label)) return true;
    return std.mem.eql(u8, label, "Constant") and current_scope_id == module_id;
}

fn addSymbolFromParsed(
    allocator: std.mem.Allocator,
    project_name: []const u8,
    qn_base: []const u8,
    rel: []const u8,
    language: discover.Language,
    line_no: i32,
    end_line: i32,
    symbol: ParsedSymbol,
    gb: *graph_buffer.GraphBuffer,
    file_id: i64,
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
    const symbol_props = test_tagging.symbolPropertiesJson(symbol.label, symbol.name, rel);
    const symbol_id = if (std.mem.eql(u8, symbol_props, "{}"))
        try gb.upsertNode(
            symbol.label,
            symbol.name,
            symbol_qn,
            rel,
            line_no,
            end_line,
        )
    else
        try gb.upsertNodeWithProperties(
            symbol.label,
            symbol.name,
            symbol_qn,
            rel,
            line_no,
            end_line,
            symbol_props,
        );
    if (symbol_id > 0 and gb.findNodeById(module_id) != null and !exists) {
        _ = gb.insertEdge(file_id, symbol_id, "DEFINES") catch |err| switch (err) {
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

fn parsedMethodOwner(
    gb: *graph_buffer.GraphBuffer,
    current_scope_id: i64,
    module_id: i64,
    symbol: ParsedSymbol,
) ?*const graph_buffer.BufferNode {
    if (!std.mem.eql(u8, symbol.label, "Function")) return null;
    if (current_scope_id == 0 or current_scope_id == module_id) return null;
    const scope_node = gb.findNodeById(current_scope_id) orelse return null;
    if (!std.mem.eql(u8, scope_node.label, "Class") and !std.mem.eql(u8, scope_node.label, "Interface")) {
        return null;
    }
    return scope_node;
}

fn addScopedMethodFromParsed(
    allocator: std.mem.Allocator,
    project_name: []const u8,
    qn_base: []const u8,
    rel: []const u8,
    language: discover.Language,
    line_no: i32,
    end_line: i32,
    method_name: []const u8,
    owner: *const graph_buffer.BufferNode,
    gb: *graph_buffer.GraphBuffer,
    file_id: i64,
    symbols: *std.ArrayList(ExtractedSymbol),
) !i64 {
    const symbol_qn = try std.fmt.allocPrint(
        allocator,
        "{s}:{s}:{s}:symbol:{s}:{s}.{s}",
        .{ project_name, qn_base, @tagName(language), @tagName(language), owner.name, method_name },
    );
    defer allocator.free(symbol_qn);

    const exists = gb.findNodeByQualifiedName(symbol_qn) != null;
    const symbol_props = test_tagging.symbolPropertiesJson("Method", method_name, rel);
    const symbol_id = if (std.mem.eql(u8, symbol_props, "{}"))
        try gb.upsertNode(
            "Method",
            method_name,
            symbol_qn,
            rel,
            line_no,
            end_line,
        )
    else
        try gb.upsertNodeWithProperties(
            "Method",
            method_name,
            symbol_qn,
            rel,
            line_no,
            end_line,
            symbol_props,
        );
    if (symbol_id > 0 and !exists) {
        _ = gb.insertEdge(file_id, symbol_id, "DEFINES") catch |err| switch (err) {
            graph_buffer.GraphBufferError.DuplicateEdge => {},
            else => return err,
        };
        _ = gb.insertEdge(owner.id, symbol_id, "DEFINES_METHOD") catch |err| switch (err) {
            graph_buffer.GraphBufferError.DuplicateEdge => {},
            else => return err,
        };
        try symbols.append(allocator, .{
            .id = symbol_id,
            .label = try allocator.dupe(u8, "Method"),
            .name = try allocator.dupe(u8, method_name),
            .qualified_name = try allocator.dupe(u8, symbol_qn),
            .file_path = try allocator.dupe(u8, rel),
        });
    }
    return symbol_id;
}

fn appendSupplementalDefinitions(
    allocator: std.mem.Allocator,
    project_name: []const u8,
    qn_base: []const u8,
    language: discover.Language,
    line: []const u8,
    file_path: []const u8,
    line_no: i32,
    gb: *graph_buffer.GraphBuffer,
    file_id: i64,
    current_scope_id: i64,
    module_id: i64,
    symbols: *std.ArrayList(ExtractedSymbol),
) !void {
    if (language == .python and currentScopeOwnsPythonModuleVariable(line, current_scope_id, module_id)) {
        const variable_name = parsePythonVariableName(line) orelse return;
        return addSymbolFromParsed(
            allocator,
            project_name,
            qn_base,
            file_path,
            language,
            line_no,
            line_no,
            .{ .label = "Variable", .name = variable_name },
            gb,
            file_id,
            module_id,
            symbols,
        );
    }

    if (language != .rust or current_scope_id == 0 or current_scope_id == module_id) return;
    const scope_node = gb.findNodeById(current_scope_id) orelse return;
    if (!std.mem.eql(u8, scope_node.label, "Class")) return;
    const field_name = parseRustFieldName(line) orelse return;
    const field_qn = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ scope_node.qualified_name, field_name });
    defer allocator.free(field_qn);

    const exists = gb.findNodeByQualifiedName(field_qn) != null;
    const field_id = try gb.upsertNode(
        "Field",
        field_name,
        field_qn,
        file_path,
        line_no,
        line_no,
    );
    if (field_id > 0 and !exists) {
        _ = gb.insertEdge(file_id, field_id, "DEFINES") catch |err| switch (err) {
            graph_buffer.GraphBufferError.DuplicateEdge => {},
            else => return err,
        };
        try symbols.append(allocator, .{
            .id = field_id,
            .label = try allocator.dupe(u8, "Field"),
            .name = try allocator.dupe(u8, field_name),
            .qualified_name = try allocator.dupe(u8, field_qn),
            .file_path = try allocator.dupe(u8, file_path),
        });
    }
}

fn currentScopeOwnsPythonModuleVariable(line: []const u8, current_scope_id: i64, module_id: i64) bool {
    if (current_scope_id != module_id) return false;
    const trimmed_left = std.mem.trimLeft(u8, line, " \t");
    return trimmed_left.len == line.len;
}

fn parseRustFieldName(line: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, line, " \t,");
    if (trimmed.len == 0) return null;
    if (std.mem.startsWith(u8, trimmed, "fn ") or
        std.mem.startsWith(u8, trimmed, "pub fn ") or
        std.mem.startsWith(u8, trimmed, "impl ") or
        std.mem.startsWith(u8, trimmed, "where "))
    {
        return null;
    }
    if (std.mem.indexOfScalar(u8, trimmed, '(') != null or std.mem.indexOfScalar(u8, trimmed, '=') != null) return null;
    const colon = std.mem.indexOfScalar(u8, trimmed, ':') orelse return null;
    var name = std.mem.trim(u8, trimmed[0..colon], " \t");
    if (std.mem.startsWith(u8, name, "pub ")) {
        name = std.mem.trim(u8, name["pub ".len..], " \t");
    }
    if (name.len == 0 or !isIdentifierStart(name[0])) return null;
    var end: usize = 1;
    while (end < name.len and isIdentifierChar(name[end])) end += 1;
    return name[0..end];
}

fn parsePythonVariableName(line: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, line, " \t");
    if (trimmed.len == 0 or
        std.mem.startsWith(u8, trimmed, "def ") or
        std.mem.startsWith(u8, trimmed, "async def ") or
        std.mem.startsWith(u8, trimmed, "class ") or
        std.mem.startsWith(u8, trimmed, "import ") or
        std.mem.startsWith(u8, trimmed, "from ") or
        std.mem.startsWith(u8, trimmed, "@"))
    {
        return null;
    }

    const equals = std.mem.indexOfScalar(u8, trimmed, '=') orelse return null;
    if (equals == 0) return null;
    if (trimmed[equals - 1] == '=' or (equals + 1 < trimmed.len and trimmed[equals + 1] == '=')) return null;

    var lhs = std.mem.trim(u8, trimmed[0..equals], " \t");
    if (std.mem.indexOfScalar(u8, lhs, ':')) |annotation| {
        lhs = std.mem.trim(u8, lhs[0..annotation], " \t");
    }
    if (lhs.len == 0 or !isIdentifierStart(lhs[0])) return null;
    var end: usize = 1;
    while (end < lhs.len and isIdentifierChar(lhs[end])) end += 1;
    if (end != lhs.len) return null;
    return lhs;
}

fn supportsTreeSitterDefs(language: discover.Language) bool {
    return switch (language) {
        .go, .java, .python, .javascript, .typescript, .tsx, .rust, .zig, .powershell, .gdscript => true,
        else => false,
    };
}

fn estimateParsedSymbolEndLine(
    bytes: []const u8,
    language: discover.Language,
    start_line: i32,
    symbol: ParsedSymbol,
) i32 {
    if (!isDeclarationLabel(symbol.label)) return start_line;
    return switch (language) {
        .go, .java, .javascript, .typescript, .tsx, .rust, .zig => estimateBraceDelimitedEndLine(bytes, language, start_line),
        else => start_line,
    };
}

fn estimateBraceDelimitedEndLine(bytes: []const u8, language: discover.Language, start_line: i32) i32 {
    var iter = std.mem.splitAny(u8, bytes, "\n\r");
    var line_no: i32 = 1;
    var seen_open = false;
    var depth: i32 = 0;
    while (iter.next()) |line_raw| : (line_no += 1) {
        if (line_no < start_line) continue;
        const line = stripComments(language, std.mem.trim(u8, line_raw, " \t"));
        if (line.len == 0 and !seen_open) continue;
        var quote: u8 = 0;
        var escaped = false;
        for (line) |ch| {
            if (quote != 0) {
                if (escaped) {
                    escaped = false;
                    continue;
                }
                if (ch == '\\') {
                    escaped = true;
                    continue;
                }
                if (ch == quote) quote = 0;
                continue;
            }
            if (ch == '"' or ((language == .javascript or language == .typescript or language == .tsx) and (ch == '\'' or ch == '`'))) {
                quote = ch;
                continue;
            }
            if (ch == '{') {
                seen_open = true;
                depth += 1;
                continue;
            }
            if (ch == '}' and seen_open) {
                depth -= 1;
                if (depth <= 0) return line_no;
            }
        }
    }
    return start_line;
}

fn collectDefinitionsWithTreeSitter(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    language: discover.Language,
    out: *std.ArrayList(TsDefinition),
) !void {
    const language_fn: *const fn () *const ts.Language = switch (language) {
        .go => treeSitterLanguageGo,
        .java => treeSitterLanguageJava,
        .python => treeSitterLanguagePython,
        .javascript => treeSitterLanguageJavascript,
        .typescript => treeSitterLanguageTypescript,
        .tsx => treeSitterLanguageTsx,
        .rust => treeSitterLanguageRust,
        .zig => treeSitterLanguageZig,
        .powershell => treeSitterLanguagePowershell,
        .gdscript => treeSitterLanguageGdscript,
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
    if (tsNodeLabel(language, node)) |label| {
        if (try extractTsName(allocator, language, bytes, node)) |name| {
            const container = if (std.mem.eql(u8, label, "Method"))
                try extractTsContainer(allocator, language, bytes, node)
            else
                null;
            try out.append(allocator, .{
                .label = try allocator.dupe(u8, label),
                .name = name,
                .container_name = if (container) |found| found.name else "",
                .container_label = if (container) |found| found.label else "",
                .start_line = @as(i32, @intCast(node.startPoint().row)) + 1,
                .end_line = tsDefinitionEndLine(node),
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

const TsContainer = struct {
    label: []const u8,
    name: []const u8,
};

fn extractTsContainer(
    allocator: std.mem.Allocator,
    language: discover.Language,
    bytes: []const u8,
    node: ts.Node,
) !?TsContainer {
    if (language == .go and std.mem.eql(u8, node.kind(), "method_declaration")) {
        const receiver_node = node.childByFieldName("receiver") orelse return null;
        const receiver_type = try extractGoReceiverType(allocator, bytes, receiver_node) orelse return null;
        return .{ .label = "Class", .name = receiver_type };
    }

    var current = node.parent();
    while (current) |ancestor| : (current = ancestor.parent()) {
        const label = tsNodeLabel(language, ancestor) orelse continue;
        if (!std.mem.eql(u8, label, "Class") and !std.mem.eql(u8, label, "Interface")) continue;
        const name = (try extractTsName(allocator, language, bytes, ancestor)) orelse continue;
        return .{ .label = label, .name = name };
    }
    return null;
}

fn tsNodeLabel(language: discover.Language, node: ts.Node) ?[]const u8 {
    const kind = node.kind();
    return switch (language) {
        .go => if (std.mem.eql(u8, kind, "function_declaration"))
            "Function"
        else if (std.mem.eql(u8, kind, "method_declaration"))
            "Method"
        else if (std.mem.eql(u8, kind, "type_spec"))
            goTypeSpecLabel(node)
        else
            null,
        .java => if (std.mem.eql(u8, kind, "class_declaration") or
            std.mem.eql(u8, kind, "enum_declaration") or
            std.mem.eql(u8, kind, "record_declaration"))
            "Class"
        else if (std.mem.eql(u8, kind, "interface_declaration") or
            std.mem.eql(u8, kind, "annotation_type_declaration"))
            "Interface"
        else if (std.mem.eql(u8, kind, "method_declaration") or
            std.mem.eql(u8, kind, "constructor_declaration") or
            std.mem.eql(u8, kind, "compact_constructor_declaration"))
            "Method"
        else
            null,
        .python => if (std.mem.eql(u8, kind, "function_definition"))
            if (nodeHasAncestorKind(node, "class_definition")) "Method" else "Function"
        else if (std.mem.eql(u8, kind, "class_definition"))
            "Class"
        else
            null,
        .javascript, .typescript, .tsx => if (std.mem.eql(u8, kind, "function_declaration") or
            std.mem.eql(u8, kind, "generator_function_declaration"))
            "Function"
        else if (std.mem.eql(u8, kind, "method_definition"))
            "Method"
        else if (std.mem.eql(u8, kind, "method_signature"))
            if (nodeHasAncestorKind(node, "class_declaration") or nodeHasAncestorKind(node, "class")) "Method" else null
        else if (std.mem.eql(u8, kind, "function_expression"))
            if (jsTsFunctionExpressionIsDefinition(node)) "Function" else null
        else if (std.mem.eql(u8, kind, "arrow_function"))
            if (jsTsArrowFunctionIsDefinition(node)) "Function" else null
        else if (std.mem.eql(u8, kind, "variable_declarator"))
            if (jsTsVariableDeclaratorLabel(node)) |label| label else null
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
            std.mem.eql(u8, kind, "function_signature_item"))
            if (nodeHasAncestorKind(node, "impl_item") or nodeHasAncestorKind(node, "trait_item")) "Method" else "Function"
        else if (std.mem.eql(u8, kind, "closure_expression"))
            if (rustClosureIsDefinition(node)) "Function" else null
        else if (std.mem.eql(u8, kind, "struct_item") or
            std.mem.eql(u8, kind, "enum_item") or
            std.mem.eql(u8, kind, "union_item") or
            std.mem.eql(u8, kind, "trait_item") or
            std.mem.eql(u8, kind, "type_item") or
            std.mem.eql(u8, kind, "impl_item"))
            if (std.mem.eql(u8, kind, "trait_item")) "Interface" else "Class"
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
        .powershell => if (std.mem.eql(u8, kind, "function_statement"))
            "Function"
        else if (std.mem.eql(u8, kind, "class_statement"))
            "Class"
        else if (std.mem.eql(u8, kind, "class_method_definition"))
            "Method"
        else
            null,
        .gdscript => if (std.mem.eql(u8, kind, "function_definition"))
            if (nodeHasAncestorKind(node, "class_definition")) "Method" else "Function"
        else if (std.mem.eql(u8, kind, "class_definition") or
            std.mem.eql(u8, kind, "class_name_statement"))
            "Class"
        else
            null,
        else => null,
    };
}

fn jsTsVariableDeclaratorLabel(node: ts.Node) ?[]const u8 {
    if (jsTsVariableDeclaratorIsLocal(node)) return null;
    const value_node = node.childByFieldName("value") orelse return "Variable";
    const value_kind = value_node.kind();
    if (std.mem.eql(u8, value_kind, "arrow_function") or
        std.mem.eql(u8, value_kind, "function_expression") or
        std.mem.eql(u8, value_kind, "generator_function"))
    {
        return null;
    }
    return "Variable";
}

fn jsTsVariableDeclaratorIsLocal(node: ts.Node) bool {
    var current = node.parent();
    while (current) |ancestor| : (current = ancestor.parent()) {
        const kind = ancestor.kind();
        if (std.mem.eql(u8, kind, "function_declaration") or
            std.mem.eql(u8, kind, "function_expression") or
            std.mem.eql(u8, kind, "arrow_function") or
            std.mem.eql(u8, kind, "generator_function") or
            std.mem.eql(u8, kind, "generator_function_declaration") or
            std.mem.eql(u8, kind, "method_definition"))
        {
            return true;
        }
    }
    return false;
}

fn jsTsFunctionExpressionIsDefinition(node: ts.Node) bool {
    const parent = node.parent() orelse return false;
    return std.mem.eql(u8, parent.kind(), "variable_declarator");
}

fn jsTsArrowFunctionIsDefinition(node: ts.Node) bool {
    const parent = node.parent() orelse return false;
    const parent_kind = parent.kind();
    return std.mem.eql(u8, parent_kind, "variable_declarator") or
        std.mem.eql(u8, parent_kind, "public_field_definition") or
        std.mem.eql(u8, parent_kind, "field_definition");
}

fn rustClosureIsDefinition(node: ts.Node) bool {
    const parent = node.parent() orelse return false;
    const parent_kind = parent.kind();
    return std.mem.eql(u8, parent_kind, "let_declaration") or
        std.mem.eql(u8, parent_kind, "const_item") or
        std.mem.eql(u8, parent_kind, "static_item");
}

fn nodeHasAncestorKind(node: ts.Node, expected_kind: []const u8) bool {
    var current = node.parent();
    while (current) |ancestor| : (current = ancestor.parent()) {
        if (std.mem.eql(u8, ancestor.kind(), expected_kind)) return true;
    }
    return false;
}

fn extractTsName(
    allocator: std.mem.Allocator,
    language: discover.Language,
    bytes: []const u8,
    node: ts.Node,
) !?[]const u8 {
    if (language == .go and std.mem.eql(u8, node.kind(), "type_spec")) {
        const name_node = node.childByFieldName("name") orelse return null;
        return try copyTsNodeText(allocator, bytes, name_node);
    }

    if (language == .powershell) {
        if (std.mem.eql(u8, node.kind(), "function_statement")) {
            if (findFirstNamedChildOfKind(node, "function_name")) |name_node| {
                return try copyTsNodeText(allocator, bytes, name_node);
            }
            return null;
        }
        if (std.mem.eql(u8, node.kind(), "class_statement") or
            std.mem.eql(u8, node.kind(), "class_method_definition"))
        {
            if (findFirstNamedChildOfKind(node, "simple_name")) |name_node| {
                return try copyTsNodeText(allocator, bytes, name_node);
            }
            return null;
        }
    }

    if (language == .javascript or language == .typescript or language == .tsx) {
        if (std.mem.eql(u8, node.kind(), "variable_declarator")) {
            const name_node = node.childByFieldName("name") orelse return null;
            return try copyTsNodeText(allocator, bytes, name_node);
        }
        if (std.mem.eql(u8, node.kind(), "arrow_function")) {
            if (try extractJsTsParentAssignedName(allocator, bytes, node)) |name| return name;
            return null;
        }
        if (std.mem.eql(u8, node.kind(), "function_expression")) {
            if (!jsTsFunctionExpressionIsDefinition(node)) return null;
        }
    }

    if (language == .rust and std.mem.eql(u8, node.kind(), "impl_item")) {
        const start = @as(usize, @intCast(node.startByte()));
        const end = @as(usize, @intCast(node.endByte()));
        if (start >= bytes.len or end > bytes.len or start >= end) return null;
        const src = bytes[start..end];
        const impl_target = extractRustImplFromText(src) orelse return null;
        return try allocator.dupe(u8, impl_target);
    }

    if (language == .rust and std.mem.eql(u8, node.kind(), "closure_expression")) {
        if (try extractRustParentBindingName(allocator, bytes, node)) |name| return name;
        return null;
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
        if ((language == .javascript or language == .typescript or language == .tsx) and
            std.mem.eql(u8, node.kind(), "function_expression"))
        {
            if (try extractJsTsParentAssignedName(allocator, bytes, node)) |name| return name;
        }
        return null;
    };
    return try copyTsNodeText(allocator, bytes, name_node);
}

fn extractJsTsParentAssignedName(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    node: ts.Node,
) !?[]const u8 {
    const parent = node.parent() orelse return null;
    const parent_kind = parent.kind();
    if (std.mem.eql(u8, parent_kind, "variable_declarator")) {
        const name_node = parent.childByFieldName("name") orelse return null;
        return try copyTsNodeText(allocator, bytes, name_node);
    }
    if (std.mem.eql(u8, parent_kind, "public_field_definition")) {
        const name_node = parent.childByFieldName("name") orelse return null;
        return try copyTsNodeText(allocator, bytes, name_node);
    }
    if (std.mem.eql(u8, parent_kind, "field_definition")) {
        const property_node = parent.childByFieldName("property") orelse return null;
        return try copyTsNodeText(allocator, bytes, property_node);
    }
    return null;
}

fn extractRustParentBindingName(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    node: ts.Node,
) !?[]const u8 {
    const parent = node.parent() orelse return null;
    const parent_kind = parent.kind();
    if (std.mem.eql(u8, parent_kind, "let_declaration")) {
        const pattern_node = parent.childByFieldName("pattern") orelse return null;
        return try copyTsNodeText(allocator, bytes, pattern_node);
    }
    if (std.mem.eql(u8, parent_kind, "const_item") or
        std.mem.eql(u8, parent_kind, "static_item"))
    {
        const name_node = parent.childByFieldName("name") orelse return null;
        return try copyTsNodeText(allocator, bytes, name_node);
    }
    return null;
}

fn copyTsNodeText(allocator: std.mem.Allocator, bytes: []const u8, node: ts.Node) !?[]const u8 {
    const start = @as(usize, @intCast(node.startByte()));
    const end = @as(usize, @intCast(node.endByte()));
    if (start >= bytes.len or end > bytes.len or start >= end) return null;
    return try allocator.dupe(u8, bytes[start..end]);
}

fn findFirstNamedChildOfKind(node: ts.Node, expected_kind: []const u8) ?ts.Node {
    const child_count = node.namedChildCount();
    var i: u32 = 0;
    while (i < child_count) : (i += 1) {
        const child = node.namedChild(i) orelse continue;
        if (std.mem.eql(u8, child.kind(), expected_kind)) return child;
    }
    return null;
}

fn tsDefinitionEndLine(node: ts.Node) i32 {
    var end_line = @as(i32, @intCast(node.endPoint().row)) + 1;
    if (node.childByFieldName("body")) |body| {
        end_line = @max(end_line, @as(i32, @intCast(body.endPoint().row)) + 1);
    }
    const child_count = node.namedChildCount();
    if (child_count > 0) {
        if (node.namedChild(child_count - 1)) |last_child| {
            end_line = @max(end_line, @as(i32, @intCast(last_child.endPoint().row)) + 1);
        }
    }
    return end_line;
}

fn extractRustImplFromText(bytes: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, bytes, " \t\r\n");
    const parts = parseRustImplParts(trimmed) orelse return null;
    return parts.target_name;
}

fn goTypeSpecLabel(node: ts.Node) ?[]const u8 {
    const type_node = node.childByFieldName("type") orelse return null;
    const type_kind = type_node.kind();
    if (std.mem.eql(u8, type_kind, "struct_type")) return "Class";
    if (std.mem.eql(u8, type_kind, "interface_type")) return "Interface";
    return null;
}

fn extractGoReceiverType(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    receiver_node: ts.Node,
) !?[]const u8 {
    const receiver_text = (try copyTsNodeText(allocator, bytes, receiver_node)) orelse return null;
    defer allocator.free(receiver_text);
    return try allocator.dupe(u8, lastIdentifier(receiver_text) orelse return null);
}

fn lastIdentifier(text: []const u8) ?[]const u8 {
    var end = text.len;
    while (end > 0) {
        const ch = text[end - 1];
        if (isIdentifierChar(ch)) break;
        end -= 1;
    }
    if (end == 0) return null;

    var start = end - 1;
    while (start > 0 and isIdentifierChar(text[start - 1])) : (start -= 1) {}
    if (!isIdentifierStart(text[start])) return null;
    return text[start..end];
}

fn tsSymbolLessThan(_: void, lhs: TsSymbol, rhs: TsSymbol) bool {
    if (lhs.start_line < rhs.start_line) return true;
    if (lhs.start_line > rhs.start_line) return false;
    if (lhs.end_line < rhs.end_line) return true;
    if (lhs.end_line > rhs.end_line) return false;
    return lhs.symbol_id < rhs.symbol_id;
}

const ScopeSelection = struct {
    symbol_id: i64,
    starts_here: bool,
};

fn selectScopeForLine(scope_markers: []const TsSymbol, line_no: i32, module_id: i64) ScopeSelection {
    var best: ?TsSymbol = null;
    var best_span: i32 = std.math.maxInt(i32);
    for (scope_markers) |marker| {
        if (line_no < marker.start_line or line_no > marker.end_line) continue;
        const span = marker.end_line - marker.start_line;
        if (best == null or span <= best_span) {
            best = marker;
            best_span = span;
        }
    }
    if (best) |marker| {
        return .{
            .symbol_id = marker.symbol_id,
            .starts_here = marker.start_line == line_no,
        };
    }
    return .{
        .symbol_id = module_id,
        .starts_here = false,
    };
}

fn treeSitterQualifiedName(
    allocator: std.mem.Allocator,
    project_name: []const u8,
    qn_base: []const u8,
    language: discover.Language,
    def: TsDefinition,
) ![]u8 {
    if (std.mem.eql(u8, def.label, "Method") and def.container_name.len > 0) {
        return std.fmt.allocPrint(
            allocator,
            "{s}:{s}:{s}:symbol:{s}:{s}.{s}",
            .{ project_name, qn_base, @tagName(language), @tagName(language), def.container_name, def.name },
        );
    }
    return std.fmt.allocPrint(
        allocator,
        "{s}:{s}:{s}:symbol:{s}:{s}",
        .{ project_name, qn_base, @tagName(language), @tagName(language), def.name },
    );
}

fn treeSitterMethodOwner(
    allocator: std.mem.Allocator,
    project_name: []const u8,
    qn_base: []const u8,
    language: discover.Language,
    def: TsDefinition,
    gb: *graph_buffer.GraphBuffer,
) ?*const graph_buffer.BufferNode {
    if (std.mem.eql(u8, def.label, "Method") and def.container_name.len > 0) {
        const owner_qn = std.fmt.allocPrint(
            allocator,
            "{s}:{s}:{s}:symbol:{s}:{s}",
            .{ project_name, qn_base, @tagName(language), @tagName(language), def.container_name },
        ) catch return null;
        defer allocator.free(owner_qn);
        return gb.findNodeByQualifiedName(owner_qn);
    }
    return null;
}

fn freePendingTsDefinitions(allocator: std.mem.Allocator, definitions: *std.ArrayList(TsDefinition)) void {
    for (definitions.items) |d| {
        allocator.free(d.label);
        allocator.free(d.name);
        if (d.container_name.len > 0) allocator.free(d.container_name);
    }
    definitions.deinit(allocator);
}

extern "c" fn tree_sitter_python() *const ts.Language;
extern "c" fn tree_sitter_javascript() *const ts.Language;
extern "c" fn tree_sitter_typescript() *const ts.Language;
extern "c" fn tree_sitter_tsx() *const ts.Language;
extern "c" fn tree_sitter_rust() *const ts.Language;
extern "c" fn tree_sitter_zig() *const ts.Language;
extern "c" fn tree_sitter_go() *const ts.Language;
extern "c" fn tree_sitter_java() *const ts.Language;
extern "c" fn tree_sitter_powershell() *const ts.Language;
extern "c" fn tree_sitter_gdscript() *const ts.Language;

fn treeSitterLanguageGo() *const ts.Language {
    return tree_sitter_go();
}

fn treeSitterLanguageJava() *const ts.Language {
    return tree_sitter_java();
}

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

fn treeSitterLanguagePowershell() *const ts.Language {
    return tree_sitter_powershell();
}

fn treeSitterLanguageGdscript() *const ts.Language {
    return tree_sitter_gdscript();
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
        return .{ .label = "Interface", .name = name };
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

fn parseGoDefs(line: []const u8) ?ParsedSymbol {
    const trimmed = std.mem.trim(u8, line, " \t");
    if (extractPrefixName(trimmed, "func ")) |name| {
        return .{ .label = "Function", .name = name };
    }
    if (std.mem.startsWith(u8, trimmed, "func (")) {
        const close = std.mem.indexOfScalar(u8, trimmed, ')') orelse return null;
        if (extractPrefixName(trimmed[close + 1 ..], "")) |name| {
            return .{ .label = "Method", .name = name };
        }
    }
    if (std.mem.startsWith(u8, trimmed, "type ")) {
        const rest = std.mem.trim(u8, trimmed["type ".len..], " \t");
        if (std.mem.indexOf(u8, rest, " struct")) |struct_pos| {
            const name = std.mem.trim(u8, rest[0..struct_pos], " \t");
            if (name.len > 0) return .{ .label = "Class", .name = name };
        }
        if (std.mem.indexOf(u8, rest, " interface")) |interface_pos| {
            const name = std.mem.trim(u8, rest[0..interface_pos], " \t");
            if (name.len > 0) return .{ .label = "Interface", .name = name };
        }
    }
    return null;
}

fn parseJavaDefs(line: []const u8) ?ParsedSymbol {
    if (parseJavaTypeDef(line)) |symbol| return symbol;
    if (parseJavaMethodDef(line)) |name| {
        return .{ .label = "Method", .name = name };
    }
    return null;
}

fn parseJavaTypeDef(line: []const u8) ?ParsedSymbol {
    const trimmed = std.mem.trim(u8, line, " \t");
    const labels = [_]struct { keyword: []const u8, label: []const u8 }{
        .{ .keyword = " class ", .label = "Class" },
        .{ .keyword = " interface ", .label = "Interface" },
        .{ .keyword = " enum ", .label = "Class" },
        .{ .keyword = " record ", .label = "Class" },
    };
    for (labels) |entry| {
        if (std.mem.indexOf(u8, trimmed, entry.keyword)) |idx| {
            const rest = trimmed[idx + entry.keyword.len ..];
            if (firstIdentifier(rest)) |name| {
                return .{ .label = entry.label, .name = name };
            }
        }
    }
    return null;
}

fn parseJavaMethodDef(line: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, line, " \t");
    if (trimmed.len == 0) return null;
    if (std.mem.indexOfScalar(u8, trimmed, '(') == null or std.mem.indexOfScalar(u8, trimmed, ')') == null) return null;
    if (std.mem.indexOfScalar(u8, trimmed, '{') == null and !std.mem.endsWith(u8, trimmed, ";")) return null;
    const control_prefixes = [_][]const u8{ "if ", "for ", "while ", "switch ", "catch ", "return ", "new " };
    for (control_prefixes) |prefix| {
        if (std.mem.startsWith(u8, trimmed, prefix)) return null;
    }
    const paren = std.mem.indexOfScalar(u8, trimmed, '(') orelse return null;
    if (paren == 0) return null;
    var end = paren;
    while (end > 0 and std.ascii.isWhitespace(trimmed[end - 1])) : (end -= 1) {}
    var start = end;
    while (start > 0 and isIdentifierChar(trimmed[start - 1])) : (start -= 1) {}
    if (start == end or !isIdentifierStart(trimmed[start])) return null;
    return trimmed[start..end];
}

fn parseYamlDefs(line: []const u8) ?ParsedSymbol {
    const key = extractConfigKey(line, ':') orelse return null;
    return .{ .label = "Variable", .name = key };
}

fn parseTomlDefs(line: []const u8) ?ParsedSymbol {
    const trimmed = std.mem.trim(u8, line, " \t");
    if (trimmed.len >= 3 and trimmed[0] == '[' and trimmed[trimmed.len - 1] == ']') {
        const section = std.mem.trim(u8, trimmed[1 .. trimmed.len - 1], " \t");
        if (section.len == 0) return null;
        return .{ .label = "Class", .name = section };
    }
    const key = extractConfigKey(line, '=') orelse return null;
    return .{ .label = "Variable", .name = key };
}

fn extractConfigKey(line: []const u8, separator: u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, line, " \t");
    if (trimmed.len == 0 or trimmed[0] == '#' or trimmed[0] == '[') return null;
    const sep_idx = std.mem.indexOfScalar(u8, trimmed, separator) orelse return null;
    const key = std.mem.trim(u8, trimmed[0..sep_idx], " \t\"'");
    if (key.len == 0 or !isIdentifierStart(key[0])) return null;
    var end: usize = 1;
    while (end < key.len and (isIdentifierChar(key[end]) or key[end] == '-' or key[end] == '.')) end += 1;
    return key[0..end];
}

fn parseJsInheritance(line: []const u8) ?[]const u8 {
    const class_pos = std.mem.indexOf(u8, line, "class ");
    if (class_pos == null) return null;
    const after_class = std.mem.trim(u8, line[class_pos.? + "class ".len ..], " \t");
    const extends_pos = std.mem.indexOf(u8, after_class, " extends ");
    if (extends_pos == null) return null;
    const parent_raw = std.mem.trim(u8, after_class[extends_pos.? + " extends ".len ..], " \t{");
    return normalizeReferenceName(parent_raw);
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

fn parseDecoratorReference(line: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, line, " \t");
    if (!std.mem.startsWith(u8, trimmed, "@")) return null;
    return normalizeReferenceName(trimmed[1..]);
}

fn parsePythonInheritanceList(line: []const u8) ?[]const u8 {
    const class_pos = std.mem.indexOf(u8, line, "class ");
    if (class_pos == null) return null;
    const after_class = std.mem.trim(u8, line[class_pos.? + "class ".len ..], " \t");
    const open_paren = std.mem.indexOfScalar(u8, after_class, '(') orelse return null;
    const close_paren = std.mem.indexOfScalarPos(u8, after_class, open_paren + 1, ')') orelse return null;
    if (close_paren <= open_paren + 1) return null;
    const bases = std.mem.trim(u8, after_class[open_paren + 1 .. close_paren], " \t");
    if (bases.len == 0) return null;
    return bases;
}

fn parseTypeScriptImplements(line: []const u8) ?[]const u8 {
    const class_pos = std.mem.indexOf(u8, line, "class ");
    if (class_pos == null) return null;
    const after_class = std.mem.trim(u8, line[class_pos.? + "class ".len ..], " \t");
    const implements_pos = std.mem.indexOf(u8, after_class, " implements ") orelse return null;
    const raw = std.mem.trim(u8, after_class[implements_pos + " implements ".len ..], " \t{");
    if (raw.len == 0) return null;
    return raw;
}

fn parseTypeScriptInterfaceExtends(line: []const u8) ?[]const u8 {
    const interface_pos = std.mem.indexOf(u8, line, "interface ");
    if (interface_pos == null) return null;
    const after_interface = std.mem.trim(u8, line[interface_pos.? + "interface ".len ..], " \t");
    const extends_pos = std.mem.indexOf(u8, after_interface, " extends ") orelse return null;
    const raw = std.mem.trim(u8, after_interface[extends_pos + " extends ".len ..], " \t{");
    if (raw.len == 0) return null;
    return raw;
}

fn normalizeReferenceName(text: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, text, " \t");
    if (trimmed.len == 0) return null;

    var end = trimmed.len;
    for (trimmed, 0..) |ch, idx| {
        if (std.ascii.isWhitespace(ch) or ch == '<' or ch == '(' or ch == '{' or ch == '[' or ch == ';' or
            (ch == ':' and !isDoubleColonAt(trimmed, idx)))
        {
            end = idx;
            break;
        }
    }

    const candidate = std.mem.trim(u8, trimmed[0..end], " \t,)}]");
    if (candidate.len == 0) return null;
    return candidate;
}

fn isImportLine(language: discover.Language, line: []const u8) bool {
    const trimmed = std.mem.trim(u8, line, " \t");
    return switch (language) {
        .go, .java => std.mem.startsWith(u8, trimmed, "import "),
        .python => std.mem.startsWith(u8, trimmed, "import ") or std.mem.startsWith(u8, trimmed, "from "),
        .javascript, .typescript, .tsx => std.mem.startsWith(u8, trimmed, "import ") or std.mem.indexOf(u8, trimmed, "require(") != null,
        .rust => std.mem.startsWith(u8, trimmed, "use ") or std.mem.startsWith(u8, trimmed, "pub use "),
        .zig => std.mem.indexOf(u8, trimmed, "@import(") != null,
        else => false,
    };
}

fn appendTypeUsageCandidates(
    allocator: std.mem.Allocator,
    language: discover.Language,
    line: []const u8,
    out: *std.ArrayList([]const u8),
) !void {
    switch (language) {
        .python, .javascript, .typescript, .tsx, .zig => {
            try appendReferencesAfterMarker(allocator, line, ":", out);
            try appendReferencesAfterMarker(allocator, line, "->", out);
        },
        .rust => {
            try appendReferencesAfterMarker(allocator, line, ":", out);
            if (std.mem.indexOf(u8, line, " for ") == null) {
                try appendReferencesAfterMarker(allocator, line, "impl ", out);
            }
            try appendReferencesAfterMarker(allocator, line, "->", out);
        },
        else => {},
    }
}

fn appendReferencesAfterMarker(
    allocator: std.mem.Allocator,
    line: []const u8,
    marker: []const u8,
    out: *std.ArrayList([]const u8),
) !void {
    var search_start: usize = 0;
    while (std.mem.indexOfPos(u8, line, search_start, marker)) |marker_pos| {
        var start = marker_pos + marker.len;
        while (start < line.len and (std.ascii.isWhitespace(line[start]) or line[start] == '&' or line[start] == '?')) : (start += 1) {}
        if (start >= line.len) break;
        if (std.mem.startsWith(u8, line[start..], "mut ")) {
            start += "mut ".len;
        }
        if (normalizeReferenceName(line[start..])) |name| {
            if (!isKeywordCandidate(lastImportSegment(name))) {
                try out.append(allocator, try allocator.dupe(u8, name));
            }
        }
        search_start = marker_pos + marker.len;
    }
}

fn appendBareUsageCandidates(
    allocator: std.mem.Allocator,
    line: []const u8,
    language: discover.Language,
    out: *std.ArrayList([]const u8),
) !void {
    if (assignmentRhs(line)) |rhs| {
        try appendReferenceCandidatesFromExpr(allocator, rhs, language, out);
    }
    if (std.mem.indexOf(u8, line, "return ")) |return_pos| {
        try appendReferenceCandidatesFromExpr(allocator, line[return_pos + "return ".len ..], language, out);
    }
    try appendArgumentReferenceCandidates(allocator, line, language, out);
}

fn assignmentRhs(line: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        if (line[i] != '=') continue;
        if (i > 0 and (line[i - 1] == '=' or line[i - 1] == '!' or line[i - 1] == '<' or line[i - 1] == '>')) continue;
        if (i + 1 < line.len and (line[i + 1] == '=' or line[i + 1] == '>')) continue;
        return line[i + 1 ..];
    }
    return null;
}

/// Extract the variable name from the left-hand side of an assignment.
/// Handles Python (`x = ...`, `self.x = ...`), JS/TS (`const x = ...`, `let x = ...`, `var x = ...`),
/// Rust (`let x = ...`, `let mut x = ...`), and Zig bare assignments.
/// Skips compound assignments (`+=`, `-=`, etc.), destructuring, and non-identifier targets.
/// Extract the exception type from a throw statement.
/// JS/TS/TSX only: `throw new ErrorName(...)` -> `ErrorName`, `throw error` -> `error`.
/// Skips bare `throw;` (rethrow).
fn parseThrowException(language: discover.Language, line: []const u8) ?[]const u8 {
    switch (language) {
        .javascript, .typescript, .tsx => {},
        else => return null,
    }
    const trimmed = std.mem.trim(u8, line, " \t");
    if (!std.mem.startsWith(u8, trimmed, "throw ")) return null;
    var rest = std.mem.trim(u8, trimmed["throw ".len..], " \t");
    if (rest.len == 0) return null;
    // Skip bare "throw;" rethrow
    if (rest.len == 1 and rest[0] == ';') return null;
    // Strip trailing semicolon
    if (rest[rest.len - 1] == ';') {
        rest = std.mem.trim(u8, rest[0 .. rest.len - 1], " \t");
    }
    if (rest.len == 0) return null;

    // `throw new ErrorName(...)` -> extract ErrorName
    if (std.mem.startsWith(u8, rest, "new ")) {
        var name_part = std.mem.trim(u8, rest["new ".len..], " \t");
        // Trim off the constructor arguments: `ErrorName(...)` -> `ErrorName`
        if (std.mem.indexOf(u8, name_part, "(")) |paren_pos| {
            name_part = name_part[0..paren_pos];
        }
        name_part = std.mem.trim(u8, name_part, " \t");
        if (name_part.len == 0) return null;
        if (!isIdentStart(name_part[0])) return null;
        for (name_part[1..]) |ch| {
            if (!isIdentChar(ch)) return null;
        }
        return name_part;
    }

    // `throw error` -> extract identifier
    if (std.mem.indexOf(u8, rest, "(")) |paren_pos| {
        rest = rest[0..paren_pos];
    }
    rest = std.mem.trim(u8, rest, " \t");
    if (rest.len == 0) return null;
    if (!isIdentStart(rest[0])) return null;
    for (rest[1..]) |ch| {
        if (!isIdentChar(ch)) return null;
    }
    return rest;
}

fn isIdentStart(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or ch == '_';
}

fn isIdentChar(ch: u8) bool {
    return isIdentStart(ch) or (ch >= '0' and ch <= '9');
}

fn appendArgumentReferenceCandidates(
    allocator: std.mem.Allocator,
    line: []const u8,
    language: discover.Language,
    out: *std.ArrayList([]const u8),
) !void {
    var depth: usize = 0;
    var segment_start: ?usize = null;
    for (line, 0..) |ch, idx| {
        if (ch == '(') {
            if (depth == 0) {
                segment_start = idx + 1;
            }
            depth += 1;
            continue;
        }
        if (ch == ')' and depth > 0) {
            depth -= 1;
            if (depth == 0) {
                if (segment_start) |start| {
                    try appendReferenceCandidatesFromExpr(allocator, line[start..idx], language, out);
                    segment_start = null;
                }
            }
        }
    }
}

fn appendReferenceCandidatesFromExpr(
    allocator: std.mem.Allocator,
    expr: []const u8,
    language: discover.Language,
    out: *std.ArrayList([]const u8),
) !void {
    var i: usize = 0;
    while (i < expr.len) {
        if (expr[i] == '"' or expr[i] == '\'' or expr[i] == '`') {
            const quote = expr[i];
            i += 1;
            while (i < expr.len and expr[i] != quote) {
                if (expr[i] == '\\' and i + 1 < expr.len) {
                    i += 2;
                } else {
                    i += 1;
                }
            }
            if (i < expr.len) i += 1;
            continue;
        }
        if (!isIdentifierStart(expr[i])) {
            i += 1;
            continue;
        }

        const start = i;
        if (previousNonWhitespace(expr, start)) |prev_idx| {
            if (expr[prev_idx] == '.') {
                while (i < expr.len and isIdentifierChar(expr[i])) : (i += 1) {}
                continue;
            }
        }
        var end = i + 1;
        while (end < expr.len and isIdentifierChar(expr[end])) : (end += 1) {}

        var cursor = end;
        while (cursor < expr.len) {
            const maybe_sep = referenceSeparatorLength(expr, cursor);
            if (maybe_sep == 0) break;
            var part_start = cursor + maybe_sep;
            while (part_start < expr.len and std.ascii.isWhitespace(expr[part_start])) : (part_start += 1) {}
            if (part_start >= expr.len or !isIdentifierStart(expr[part_start])) break;
            var part_end = part_start + 1;
            while (part_end < expr.len and isIdentifierChar(expr[part_end])) : (part_end += 1) {}
            cursor = part_end;
            end = part_end;
        }

        const next = skipWhitespace(expr, end);
        const candidate = expr[start..end];
        const starts_struct_literal = next < expr.len and expr[next] == '{';
        if (candidate.len > 0 and (next >= expr.len or expr[next] != '(') and !(language == .rust and starts_struct_literal)) {
            const tail = lastImportSegment(candidate);
            if (!isKeywordCandidate(tail)) {
                try out.append(allocator, try allocator.dupe(u8, candidate));
            }
        }
        i = if (end > i) end else i + 1;
    }
}

fn referenceSeparatorLength(text: []const u8, idx: usize) usize {
    var cursor = idx;
    while (cursor < text.len and std.ascii.isWhitespace(text[cursor])) : (cursor += 1) {}
    if (cursor >= text.len) return 0;
    if (text[cursor] == '.') return cursor - idx + 1;
    if (text[cursor] == ':' and cursor + 1 < text.len and text[cursor + 1] == ':') {
        return cursor - idx + 2;
    }
    return 0;
}

fn skipWhitespace(text: []const u8, start: usize) usize {
    var idx = start;
    while (idx < text.len and std.ascii.isWhitespace(text[idx])) : (idx += 1) {}
    return idx;
}

fn previousNonWhitespace(text: []const u8, start: usize) ?usize {
    if (start == 0) return null;
    var idx = start;
    while (idx > 0) {
        idx -= 1;
        if (!std.ascii.isWhitespace(text[idx])) return idx;
    }
    return null;
}

fn isDoubleColonAt(text: []const u8, idx: usize) bool {
    if (text[idx] != ':') return false;
    if (idx + 1 < text.len and text[idx + 1] == ':') return true;
    if (idx > 0 and text[idx - 1] == ':') return true;
    return false;
}

fn dedupeStringArray(allocator: std.mem.Allocator, names: *std.ArrayList([]const u8)) void {
    var i: usize = 0;
    while (i < names.items.len) : (i += 1) {
        var j = i + 1;
        while (j < names.items.len) {
            if (std.mem.eql(u8, names.items[i], names.items[j])) {
                const dup = names.swapRemove(j);
                allocator.free(dup);
                continue;
            }
            j += 1;
        }
    }
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
    unresolved_usages: *std.ArrayList(UnresolvedUsage),
    unresolved_throws: *std.ArrayList(UnresolvedThrow),
    semantic_hints: *std.ArrayList(SemanticHint),
) !FileExtraction {
    errdefer allocator.free(file_path);

    const owned_symbols = try symbols.toOwnedSlice(allocator);
    errdefer freeExtractedSymbols(allocator, owned_symbols);

    const owned_calls = try unresolved_calls.toOwnedSlice(allocator);
    errdefer freeUnresolvedCalls(allocator, owned_calls);

    const owned_imports = try unresolved_imports.toOwnedSlice(allocator);
    errdefer freeUnresolvedImports(allocator, owned_imports);

    const owned_usages = try unresolved_usages.toOwnedSlice(allocator);
    errdefer freeUnresolvedUsages(allocator, owned_usages);

    const owned_throws = try unresolved_throws.toOwnedSlice(allocator);
    errdefer freeUnresolvedThrows(allocator, owned_throws);

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
        .unresolved_usages = owned_usages,
        .unresolved_throws = owned_throws,
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
        const trait_name = parseRustTypeName(trait_raw) orelse return null;
        const target_name = parseRustTypeName(target_raw) orelse return null;
        return .{
            .target_name = target_name,
            .trait_name = trait_name,
        };
    }

    const target_name = parseRustTypeName(trimmed) orelse return null;
    return .{
        .target_name = target_name,
        .trait_name = null,
    };
}

fn parseRustTypeName(text: []const u8) ?[]const u8 {
    var trimmed = std.mem.trim(u8, text, " \t");
    while (trimmed.len > 0 and (trimmed[0] == '&' or trimmed[0] == '*')) {
        trimmed = std.mem.trim(u8, trimmed[1..], " \t");
    }
    if (std.mem.startsWith(u8, trimmed, "mut ")) {
        trimmed = std.mem.trim(u8, trimmed["mut ".len..], " \t");
    }
    if (std.mem.startsWith(u8, trimmed, "dyn ")) {
        trimmed = std.mem.trim(u8, trimmed["dyn ".len..], " \t");
    }
    if (trimmed.len == 0) return null;

    var head_end = trimmed.len;
    for (trimmed, 0..) |ch, idx| {
        if (ch == '<' or ch == '(' or ch == '{' or ch == '[' or ch == ',' or std.ascii.isWhitespace(ch)) {
            head_end = idx;
            break;
        }
    }

    const head = std.mem.trim(u8, trimmed[0..head_end], " \t");
    if (head.len == 0) return null;
    if (std.mem.lastIndexOf(u8, head, "::")) |sep| {
        return firstIdentifier(head[sep + 2 ..]);
    }
    return firstIdentifier(head);
}

fn isDeclarationLine(language: discover.Language, line: []const u8) bool {
    if (parseSymbol(language, line)) |sym| {
        return isDeclarationLabel(sym.label);
    }
    if ((language == .typescript or language == .tsx) and isTypeScriptSignatureLine(line)) {
        return true;
    }
    return false;
}

fn isTypeScriptSignatureLine(line: []const u8) bool {
    const trimmed = std.mem.trim(u8, line, " \t");
    if (!std.mem.endsWith(u8, trimmed, ";")) return false;
    if (std.mem.indexOfScalar(u8, trimmed, '(') == null) return false;
    if (std.mem.indexOfScalar(u8, trimmed, ')') == null) return false;
    if (std.mem.indexOfScalar(u8, trimmed, ':') == null) return false;
    if (std.mem.indexOfScalar(u8, trimmed, '=') != null) return false;
    if (std.mem.indexOfScalar(u8, trimmed, '{') != null) return false;
    return true;
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

fn freePendingRouteDecorators(allocator: std.mem.Allocator, pending_routes: *std.ArrayList(PendingRouteDecorator)) void {
    for (pending_routes.items) |route| {
        allocator.free(route.route_path);
        allocator.free(route.route_method);
    }
    pending_routes.deinit(allocator);
}

fn freePendingAsyncDecorators(allocator: std.mem.Allocator, pending_routes: *std.ArrayList(PendingAsyncDecorator)) void {
    for (pending_routes.items) |route| {
        allocator.free(route.broker);
        allocator.free(route.topic);
    }
    pending_routes.deinit(allocator);
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
        if (c.full_callee_name.len > 0) allocator.free(c.full_callee_name);
        allocator.free(c.file_path);
        if (c.first_string_arg.len > 0) allocator.free(c.first_string_arg);
        if (c.route_path.len > 0) allocator.free(c.route_path);
        if (c.route_handler_ref.len > 0) allocator.free(c.route_handler_ref);
        if (c.route_method.len > 0) allocator.free(c.route_method);
    }
    calls.deinit(allocator);
}

fn freePendingUnresolvedImports(allocator: std.mem.Allocator, imports: *std.ArrayList(UnresolvedImport)) void {
    for (imports.items) |i| {
        allocator.free(i.import_name);
        allocator.free(i.binding_alias);
        allocator.free(i.file_path);
    }
    imports.deinit(allocator);
}

fn freePendingUnresolvedUsages(allocator: std.mem.Allocator, usages: *std.ArrayList(UnresolvedUsage)) void {
    for (usages.items) |usage| {
        allocator.free(usage.ref_name);
        allocator.free(usage.file_path);
    }
    usages.deinit(allocator);
}

fn freePendingUnresolvedThrows(allocator: std.mem.Allocator, throws: *std.ArrayList(UnresolvedThrow)) void {
    for (throws.items) |t| {
        allocator.free(t.exception_name);
        allocator.free(t.file_path);
    }
    throws.deinit(allocator);
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
        if (c.full_callee_name.len > 0) allocator.free(c.full_callee_name);
        allocator.free(c.file_path);
        if (c.first_string_arg.len > 0) allocator.free(c.first_string_arg);
        if (c.route_path.len > 0) allocator.free(c.route_path);
        if (c.route_handler_ref.len > 0) allocator.free(c.route_handler_ref);
        if (c.route_method.len > 0) allocator.free(c.route_method);
    }
    allocator.free(calls);
}

pub fn freeUnresolvedImports(allocator: std.mem.Allocator, imports: []UnresolvedImport) void {
    for (imports) |i| {
        allocator.free(i.import_name);
        allocator.free(i.binding_alias);
        allocator.free(i.file_path);
    }
    allocator.free(imports);
}

pub fn freeUnresolvedUsages(allocator: std.mem.Allocator, usages: []UnresolvedUsage) void {
    for (usages) |usage| {
        allocator.free(usage.ref_name);
        allocator.free(usage.file_path);
    }
    allocator.free(usages);
}

pub fn freeUnresolvedThrows(allocator: std.mem.Allocator, throws: []UnresolvedThrow) void {
    for (throws) |t| {
        allocator.free(t.exception_name);
        allocator.free(t.file_path);
    }
    allocator.free(throws);
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
    freeUnresolvedUsages(allocator, extraction.unresolved_usages);
    freeUnresolvedThrows(allocator, extraction.unresolved_throws);
    freeSemanticHints(allocator, extraction.semantic_hints);
}

test "extractor parses definitions for core languages" {
    try std.testing.expect(parseSymbol(.python, "def hello(x):") != null);
    try std.testing.expect(parseSymbol(.python, "class A(object):") != null);
    try std.testing.expect(parseSymbol(.go, "func greet(name string) string {") != null);
    try std.testing.expect(parseSymbol(.go, "type Worker struct {") != null);
    try std.testing.expect(parseSymbol(.java, "public class Worker {") != null);
    try std.testing.expect(parseSymbol(.java, "public String run() {") != null);
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

test "extractor preserves import aliases across language forms" {
    var imports = std.ArrayList(UnresolvedImport).empty;
    defer freePendingUnresolvedImports(std.testing.allocator, &imports);

    try parsePythonImports(std.testing.allocator, "from util import helper as renamed, other", 1, "app.py", &imports);
    try std.testing.expectEqual(@as(usize, 3), imports.items.len);
    try std.testing.expect(imports.items[0].emit_edge);
    try std.testing.expect(!imports.items[1].emit_edge);
    try std.testing.expect(!imports.items[2].emit_edge);
    try std.testing.expectEqualStrings("util.helper", imports.items[1].import_name);
    try std.testing.expectEqualStrings("renamed", imports.items[1].binding_alias);
    try std.testing.expectEqualStrings("util.other", imports.items[2].import_name);
    try std.testing.expectEqualStrings("other", imports.items[2].binding_alias);
    for (imports.items) |imp| {
        std.testing.allocator.free(imp.import_name);
        std.testing.allocator.free(imp.binding_alias);
        std.testing.allocator.free(imp.file_path);
    }
    imports.clearRetainingCapacity();

    try parseJsImports(std.testing.allocator, "import defaultThing, { helper as renamed, other } from \"./util\";", 1, "index.js", &imports);
    try std.testing.expectEqual(@as(usize, 3), imports.items.len);
    try std.testing.expectEqualStrings("./util", imports.items[0].import_name);
    try std.testing.expectEqualStrings("defaultThing", imports.items[0].binding_alias);
    try std.testing.expectEqualStrings("./util.helper", imports.items[1].import_name);
    try std.testing.expectEqualStrings("renamed", imports.items[1].binding_alias);
    for (imports.items) |imp| {
        std.testing.allocator.free(imp.import_name);
        std.testing.allocator.free(imp.binding_alias);
        std.testing.allocator.free(imp.file_path);
    }
    imports.clearRetainingCapacity();

    try parseRustImports(std.testing.allocator, "use crate::util::{helper as renamed, other};", 1, "main.rs", &imports);
    try std.testing.expectEqual(@as(usize, 2), imports.items.len);
    try std.testing.expectEqualStrings("crate::util::helper", imports.items[0].import_name);
    try std.testing.expectEqualStrings("renamed", imports.items[0].binding_alias);
    try std.testing.expectEqualStrings("crate::util::other", imports.items[1].import_name);
    try std.testing.expectEqualStrings("other", imports.items[1].binding_alias);
    for (imports.items) |imp| {
        std.testing.allocator.free(imp.import_name);
        std.testing.allocator.free(imp.binding_alias);
        std.testing.allocator.free(imp.file_path);
    }
    imports.clearRetainingCapacity();

    try parseGoImports(std.testing.allocator, "import alias \"example.com/tools/runtime\"", 1, "main.go", &imports);
    try std.testing.expectEqual(@as(usize, 1), imports.items.len);
    try std.testing.expectEqualStrings("example.com/tools/runtime", imports.items[0].import_name);
    try std.testing.expectEqualStrings("alias", imports.items[0].binding_alias);
    for (imports.items) |imp| {
        std.testing.allocator.free(imp.import_name);
        std.testing.allocator.free(imp.binding_alias);
        std.testing.allocator.free(imp.file_path);
    }
    imports.clearRetainingCapacity();

    try parseJavaImports(std.testing.allocator, "import java.util.List;", 1, "Main.java", &imports);
    try std.testing.expectEqual(@as(usize, 1), imports.items.len);
    try std.testing.expectEqualStrings("java.util.List", imports.items[0].import_name);
    try std.testing.expectEqualStrings("List", imports.items[0].binding_alias);
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

test "tree-sitter keeps javascript decorator-assigned named functions as variables" {
    var defs = std.ArrayList(TsDefinition).empty;
    defer freePendingTsDefinitions(std.testing.allocator, &defs);

    try collectDefinitionsWithTreeSitter(
        std.testing.allocator,
        \\function decorate(fn) {
        \\    return fn;
        \\}
        \\
        \\const boot = decorate(function boot() {
        \\    return 1;
        \\});
        \\
        \\const run = () => {
        \\    return boot();
        \\};
        \\
    ,
        .javascript,
        &defs,
    );

    try std.testing.expect(definitionPresent(defs.items, "Function", "decorate", 1));
    try std.testing.expect(definitionPresent(defs.items, "Variable", "boot", 5));
    try std.testing.expect(definitionPresent(defs.items, "Function", "run", 9));
    try std.testing.expect(!definitionPresent(defs.items, "Function", "boot", 5));
}

test "tree-sitter ignores javascript function-local variables" {
    var defs = std.ArrayList(TsDefinition).empty;
    defer freePendingTsDefinitions(std.testing.allocator, &defs);

    try collectDefinitionsWithTreeSitter(
        std.testing.allocator,
        \\const settings = { mode: "json" };
        \\
        \\function boot() {
        \\    const logger = createLogger();
        \\    return logger.run();
        \\}
        \\
    ,
        .javascript,
        &defs,
    );

    try std.testing.expect(definitionPresent(defs.items, "Variable", "settings", 1));
    try std.testing.expect(!definitionPresent(defs.items, "Variable", "logger", 4));
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
    try std.testing.expect(!definitionPresent(defs.items, "Method", "read", 2));
    try std.testing.expect(definitionPresent(defs.items, "Method", "read", 10));
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
    try std.testing.expect(definitionPresent(defs.items, "Interface", "Handler", 5));
    try std.testing.expect(definitionPresent(defs.items, "Function", "helper", 7));
    try std.testing.expect(definitionPresent(defs.items, "Function", "main", 11));
    try std.testing.expect(definitionPresent(defs.items, "Class", "Service", 15));
    try std.testing.expect(definitionPresent(defs.items, "Method", "run", 16));
    try std.testing.expectEqual(@as(i32, 9), definitionEndLine(defs.items, "Function", "helper", 7).?);
    try std.testing.expectEqual(@as(i32, 13), definitionEndLine(defs.items, "Function", "main", 11).?);
    try std.testing.expectEqual(@as(i32, 16), definitionEndLine(defs.items, "Method", "run", 16).?);
}

test "tree-sitter extracts go definitions with labels and method ownership" {
    var defs = std.ArrayList(TsDefinition).empty;
    defer freePendingTsDefinitions(std.testing.allocator, &defs);

    try collectDefinitionsWithTreeSitter(
        std.testing.allocator,
        \\package main
        \\
        \\type Runner interface {
        \\    Run() string
        \\}
        \\
        \\type Worker struct {
        \\    Mode string
        \\}
        \\
        \\func (w *Worker) Run() string {
        \\    return w.Mode
        \\}
        \\
        \\func boot() string {
        \\    return (&Worker{Mode: "batch"}).Run()
        \\}
        \\
    ,
        .go,
        &defs,
    );

    try std.testing.expect(definitionPresent(defs.items, "Interface", "Runner", 3));
    try std.testing.expect(definitionPresent(defs.items, "Class", "Worker", 7));
    try std.testing.expect(definitionWithContainerPresent(defs.items, "Method", "Run", "Worker", 11));
    try std.testing.expect(definitionPresent(defs.items, "Function", "boot", 15));
}

test "tree-sitter extracts java definitions with labels and method ownership" {
    var defs = std.ArrayList(TsDefinition).empty;
    defer freePendingTsDefinitions(std.testing.allocator, &defs);

    try collectDefinitionsWithTreeSitter(
        std.testing.allocator,
        \\package demo;
        \\
        \\interface Runner {
        \\    String run();
        \\}
        \\
        \\class Worker implements Runner {
        \\    Worker() {}
        \\
        \\    public String run() {
        \\        return "ok";
        \\    }
        \\}
        \\
        \\public class Main {
        \\    static String boot() {
        \\        return new Worker().run();
        \\    }
        \\}
        \\
    ,
        .java,
        &defs,
    );

    try std.testing.expect(definitionPresent(defs.items, "Interface", "Runner", 3));
    try std.testing.expect(definitionPresent(defs.items, "Class", "Worker", 7));
    try std.testing.expect(definitionWithContainerPresent(defs.items, "Method", "Worker", "Worker", 8));
    try std.testing.expect(definitionWithContainerPresent(defs.items, "Method", "run", "Worker", 10));
    try std.testing.expect(definitionPresent(defs.items, "Class", "Main", 15));
    try std.testing.expect(definitionWithContainerPresent(defs.items, "Method", "boot", "Main", 16));
}

test "tree-sitter extracts powershell definitions with method ownership" {
    const allocator = std.testing.allocator;
    const source =
        \\function Invoke-Users {
        \\    Get-Users
        \\}
        \\
        \\class Worker {
        \\    [void] Run() {
        \\        Write-Host "ok"
        \\    }
        \\}
        \\
    ;

    var defs = std.ArrayList(TsDefinition).empty;
    defer freePendingTsDefinitions(allocator, &defs);
    try collectDefinitionsWithTreeSitter(
        allocator,
        source,
        .powershell,
        &defs,
    );

    try std.testing.expect(definitionPresent(defs.items, "Function", "Invoke-Users", 1));
    try std.testing.expect(definitionPresent(defs.items, "Class", "Worker", 5));
    try std.testing.expect(definitionWithContainerPresent(defs.items, "Method", "Run", "Worker", 6));
}

test "tree-sitter extracts gdscript definitions with nested class ownership" {
    const allocator = std.testing.allocator;
    const source =
        \\class_name Hero
        \\
        \\func boot():
        \\    pass
        \\
        \\class Worker:
        \\    func run():
        \\        pass
        \\
    ;

    var defs = std.ArrayList(TsDefinition).empty;
    defer freePendingTsDefinitions(allocator, &defs);
    try collectDefinitionsWithTreeSitter(
        allocator,
        source,
        .gdscript,
        &defs,
    );

    try std.testing.expect(definitionPresent(defs.items, "Class", "Hero", 1));
    try std.testing.expect(definitionPresent(defs.items, "Function", "boot", 3));
    try std.testing.expect(definitionPresent(defs.items, "Class", "Worker", 6));
    try std.testing.expect(definitionWithContainerPresent(defs.items, "Method", "run", "Worker", 7));
}

test "tree-sitter tracks rust multiline body end lines" {
    var defs = std.ArrayList(TsDefinition).empty;
    defer freePendingTsDefinitions(std.testing.allocator, &defs);

    try collectDefinitionsWithTreeSitter(
        std.testing.allocator,
        \\pub fn boot() -> String {
        \\    let value = helper();
        \\    value
        \\}
        \\
        \\fn helper() -> String {
        \\    "ok".to_string()
        \\}
        \\
    ,
        .rust,
        &defs,
    );

    try std.testing.expectEqual(@as(i32, 4), definitionEndLine(defs.items, "Function", "boot", 1).?);
}

test "line parser estimates rust function spans with nested literals" {
    const source =
        \\pub struct Config {
        \\    pub mode: String,
        \\}
        \\
        \\pub struct Worker {
        \\    pub config: Config,
        \\}
        \\
        \\pub fn boot() -> String {
        \\    let worker = Worker {
        \\        config: Config {
        \\            mode: "batch".to_string(),
        \\        },
        \\    };
        \\    worker.config.mode
        \\}
        \\
    ;

    const symbol = parseSymbol(.rust, "pub fn boot() -> String {") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(i32, 16), estimateParsedSymbolEndLine(source, .rust, 9, symbol));
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
    var found_emit = false;
    var found_build = false;
    while (lines.next()) |line_raw| : (line_no += 1) {
        const line = std.mem.trim(u8, line_raw, " \t");
        if (line.len == 0) continue;
        const symbol = parseSymbol(.rust, line);
        if (symbol) |sym| {
            if (std.mem.eql(u8, sym.label, "Function") and std.mem.eql(u8, sym.name, "emit")) {
                found_emit = true;
            }
            if (std.mem.eql(u8, sym.label, "Function") and std.mem.eql(u8, sym.name, "build")) {
                found_build = true;
            }
        }
    }
    try std.testing.expect(found_emit);
    try std.testing.expect(found_build);
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

fn definitionWithContainerPresent(
    defs: []const TsDefinition,
    expected_label: []const u8,
    expected_name: []const u8,
    expected_container: []const u8,
    expected_line: i32,
) bool {
    for (defs) |def| {
        if (def.start_line != expected_line) continue;
        if (!std.mem.eql(u8, def.label, expected_label)) continue;
        if (!std.mem.eql(u8, def.name, expected_name)) continue;
        if (!std.mem.eql(u8, def.container_name, expected_container)) continue;
        return true;
    }
    return false;
}

fn definitionEndLine(
    defs: []const TsDefinition,
    expected_label: []const u8,
    expected_name: []const u8,
    expected_line: i32,
) ?i32 {
    for (defs) |def| {
        if (def.start_line != expected_line) continue;
        if (!std.mem.eql(u8, def.label, expected_label)) continue;
        if (!std.mem.eql(u8, def.name, expected_name)) continue;
        return def.end_line;
    }
    return null;
}

test "rust impl parsing keeps target and trait roles straight" {
    const parts = parseRustImplParts("impl Display for Foo {") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("Foo", parts.target_name);
    try std.testing.expect(parts.trait_name != null);
    try std.testing.expectEqualStrings("Display", parts.trait_name.?);

    const namespaced = parseRustImplParts("impl fmt::Display for crate::models::Foo<T> {") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("Foo", namespaced.target_name);
    try std.testing.expect(namespaced.trait_name != null);
    try std.testing.expectEqualStrings("Display", namespaced.trait_name.?);

    const hint = parseRustSemanticHint("impl Display for Foo {") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("Display", hint.trait_name);
}

test "call collection skips declaration lines" {
    try std.testing.expect((try collectCalls(std.testing.allocator, "fn main() void {}", .zig, null, 1, 1, false)) == null);
    try std.testing.expect((try collectCalls(std.testing.allocator, "def hello(x):", .python, null, 1, 1, false)) == null);
    try std.testing.expect((try collectCalls(std.testing.allocator, "class Foo(Base):", .python, null, 1, 1, false)) == null);
    const const_decl = parseSymbol(.zig, "const std = @import(\"std\");") orelse return error.TestUnexpectedResult;
    try std.testing.expect((try collectCalls(std.testing.allocator, "const std = @import(\"std\");", .zig, const_decl, 1, 1, false)) == null);

    const calls = (try collectCalls(std.testing.allocator, "result = helper(value)", .python, null, 2, 1, false)) orelse return error.TestUnexpectedResult;
    defer freeStringSlices(std.testing.allocator, calls);
    try std.testing.expectEqual(@as(usize, 1), calls.len);
    try std.testing.expectEqualStrings("helper", calls[0]);

    const const_calls = (try collectCalls(
        std.testing.allocator,
        "const doubled = add(value, 1)",
        .zig,
        null,
        2,
        1,
        false,
    )) orelse return error.TestUnexpectedResult;
    defer freeStringSlices(std.testing.allocator, const_calls);
    try std.testing.expectEqual(@as(usize, 1), const_calls.len);
    try std.testing.expectEqualStrings("add", const_calls[0]);

    const wrapped_decl = parseSymbol(.javascript, "const boot = decorate(function boot() {") orelse return error.TestUnexpectedResult;
    const wrapped_calls = (try collectCalls(
        std.testing.allocator,
        "const boot = decorate(function boot() {",
        .javascript,
        wrapped_decl,
        2,
        1,
        false,
    )) orelse return error.TestUnexpectedResult;
    defer freeStringSlices(std.testing.allocator, wrapped_calls);
    try std.testing.expectEqual(@as(usize, 2), wrapped_calls.len);
    try std.testing.expectEqualStrings("decorate", wrapped_calls[0]);
    try std.testing.expectEqualStrings("boot", wrapped_calls[1]);

    try std.testing.expect((try collectCalls(
        std.testing.allocator,
        "const worker = new Worker()",
        .typescript,
        null,
        2,
        1,
        false,
    )) == null);
    try std.testing.expect((try collectCalls(
        std.testing.allocator,
        "run(): string;",
        .typescript,
        null,
        2,
        1,
        false,
    )) == null);
}

test "route registration metadata captures path handler and method" {
    const route = parseRouteRegistrationMetadata("app.get(\"/users\", listUsers);") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("get", route.callee_leaf);
    try std.testing.expectEqualStrings("app.get", route.callee_full);
    try std.testing.expectEqualStrings("/users", route.route_path);
    try std.testing.expectEqualStrings("listUsers", route.handler_ref);
    try std.testing.expectEqualStrings("GET", route.method);

    const any_route = parseRouteRegistrationMetadata("router.route('/orders', handlers.list);") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("ANY", any_route.method);
    try std.testing.expectEqualStrings("handlers.list", any_route.handler_ref);

    try std.testing.expect(parseRouteRegistrationMetadata("requests.get(\"/api/users\")") == null);
}

test "call metadata captures dotted callee and first string arg" {
    const get_meta = parseCallLineMetadataForLeaf("response = requests.get(\"/api/users\")", "get") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("requests.get", get_meta.callee_full);
    try std.testing.expectEqualStrings("/api/users", get_meta.first_string_arg);

    const json_meta = parseCallLineMetadataForLeaf("return response.json()", "json") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("response.json", json_meta.callee_full);
    try std.testing.expectEqualStrings("", json_meta.first_string_arg);
}

test "route decorator metadata captures path and method" {
    const route = parseRouteDecoratorMetadata("@app.get(\"/users\")") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("app.get", route.callee_full);
    try std.testing.expectEqualStrings("/users", route.route_path);
    try std.testing.expectEqualStrings("GET", route.method);

    const any_route = parseRouteDecoratorMetadata("@router.route('/orders')") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("ANY", any_route.method);
    try std.testing.expect(parseRouteDecoratorMetadata("@trace") == null);
}

test "async decorator metadata captures broker and topic" {
    const route = parseAsyncDecoratorMetadata("@celery.task(\"users.refresh\")") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("celery.task", route.callee_full);
    try std.testing.expectEqualStrings("celery", route.broker);
    try std.testing.expectEqualStrings("users.refresh", route.topic);
    try std.testing.expect(parseAsyncDecoratorMetadata("@app.get(\"/users\")") == null);
}

test "usage collection captures callback refs and type references without direct call noise" {
    const callback_usages = (try collectUsages(
        std.testing.allocator,
        "register(helper, other.value)",
        .python,
        null,
        2,
        1,
    )) orelse return error.TestUnexpectedResult;
    defer freeStringSlices(std.testing.allocator, callback_usages);
    try std.testing.expectEqual(@as(usize, 2), callback_usages.len);
    try std.testing.expectEqualStrings("helper", callback_usages[0]);
    try std.testing.expectEqualStrings("other.value", callback_usages[1]);

    try std.testing.expect((try collectUsages(
        std.testing.allocator,
        "return helper()",
        .python,
        null,
        2,
        1,
    )) == null);

    const rust_decl = parseSymbol(.rust, "pub fn build(counter: &mut Counter, notifier: &impl Notifier) -> ResultType {") orelse return error.TestUnexpectedResult;
    const type_usages = (try collectUsages(
        std.testing.allocator,
        "pub fn build(counter: &mut Counter, notifier: &impl Notifier) -> ResultType {",
        .rust,
        rust_decl,
        2,
        1,
    )) orelse return error.TestUnexpectedResult;
    defer freeStringSlices(std.testing.allocator, type_usages);
    try std.testing.expectEqual(@as(usize, 3), type_usages.len);
    try std.testing.expectEqualStrings("Counter", type_usages[0]);
    try std.testing.expectEqualStrings("Notifier", type_usages[1]);
    try std.testing.expectEqualStrings("ResultType", type_usages[2]);
}

test "semantic helpers capture decorators and multi-parent relationships" {
    try std.testing.expectEqualStrings("trace", parseDecoratorReference("@trace") orelse return error.TestUnexpectedResult);
    try std.testing.expectEqualStrings("pkg.trace", parseDecoratorReference("@pkg.trace(arg)") orelse return error.TestUnexpectedResult);
    try std.testing.expectEqualStrings("Base, Mixin", parsePythonInheritanceList("class Worker(Base, Mixin):") orelse return error.TestUnexpectedResult);
    try std.testing.expectEqualStrings("Port, Disposable", parseTypeScriptImplements("class Worker implements Port, Disposable {") orelse return error.TestUnexpectedResult);
    try std.testing.expectEqualStrings("BasePort, ExtraPort", parseTypeScriptInterfaceExtends("interface WorkerPort extends BasePort, ExtraPort {") orelse return error.TestUnexpectedResult);
}

test "config definition helpers parse yaml and toml keys" {
    const yaml = parseSymbol(.yaml, "mode: batch") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("Variable", yaml.label);
    try std.testing.expectEqualStrings("mode", yaml.name);

    const toml_section = parseSymbol(.toml, "[package]") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("Class", toml_section.label);
    try std.testing.expectEqualStrings("package", toml_section.name);

    const toml_key = parseSymbol(.toml, "version = \"0.1.0\"") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("Variable", toml_key.label);
    try std.testing.expectEqualStrings("version", toml_key.name);
}

test "python variable helper keeps only simple module assignments" {
    try std.testing.expectEqualStrings("default_mode", parsePythonVariableName("default_mode = \"batch\"") orelse return error.TestUnexpectedResult);
    try std.testing.expectEqualStrings("status_flag", parsePythonVariableName("status_flag: str = \"ready\"") orelse return error.TestUnexpectedResult);
    try std.testing.expect(parsePythonVariableName("worker.status = \"done\"") == null);
    try std.testing.expect(parsePythonVariableName("left, right = pair") == null);
    try std.testing.expect(parsePythonVariableName("if status_flag == \"ready\":") == null);
}

test "rust field helper parses struct fields without matching functions" {
    try std.testing.expectEqualStrings("config", parseRustFieldName("    pub config: Config,") orelse return error.TestUnexpectedResult);
    try std.testing.expectEqualStrings("mode", parseRustFieldName("mode: String,") orelse return error.TestUnexpectedResult);
    try std.testing.expect(parseRustFieldName("fn run(&self) -> String {") == null);
}

test "parseThrowException extracts exception types from JS throw statements" {
    // `throw new ErrorName(...)` -> ErrorName
    try std.testing.expectEqualStrings("ValidationError", parseThrowException(.javascript, "throw new ValidationError(\"bad\");") orelse return error.TestUnexpectedResult);
    try std.testing.expectEqualStrings("Error", parseThrowException(.javascript, "throw new Error(\"fail\");") orelse return error.TestUnexpectedResult);
    try std.testing.expectEqualStrings("TypeError", parseThrowException(.typescript, "throw new TypeError(\"wrong type\");") orelse return error.TestUnexpectedResult);

    // Bare throw identifier
    try std.testing.expectEqualStrings("error", parseThrowException(.javascript, "throw error;") orelse return error.TestUnexpectedResult);
    try std.testing.expectEqualStrings("err", parseThrowException(.tsx, "throw err") orelse return error.TestUnexpectedResult);

    // Skip bare rethrow
    try std.testing.expect(parseThrowException(.javascript, "throw;") == null);

    // Non-JS languages return null
    try std.testing.expect(parseThrowException(.python, "raise ValueError(\"bad\")") == null);
    try std.testing.expect(parseThrowException(.rust, "panic!(\"fail\")") == null);
    try std.testing.expect(parseThrowException(.zig, "return error.OutOfMemory") == null);
}

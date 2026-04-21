const std = @import("std");
const discover = @import("discover.zig");
const store = @import("store.zig");

pub const vector_dim: usize = 128;
const min_token_len: usize = 2;
const min_edge_score: f64 = 0.45;
const max_edges_per_node: usize = 6;
const max_bucket_size: usize = 96;
const default_query_limit: usize = 25;

pub const SearchHit = struct {
    node: store.Node,
    score: f64,
};

pub const SearchPage = struct {
    total: usize,
    hits: []SearchHit,
};

const SemanticEntry = struct {
    node_id: i64,
    file_path: []u8,
    tokens: [][]u8,
    vector: [vector_dim]i8,
};

const FileCache = struct {
    content: []u8,
    line_starts: []usize,
};

const ScoredIndex = struct {
    idx: usize,
    score: f64,
};

pub fn refreshProject(
    allocator: std.mem.Allocator,
    db: *store.Store,
    project: []const u8,
    files: []const discover.FileInfo,
) !void {
    try db.clearSemanticVectors(project);

    const nodes = try db.listSemanticNodes(project);
    defer db.freeNodes(nodes);

    var file_cache = try buildFileCache(allocator, files);
    defer freeFileCache(allocator, &file_cache);

    var entries = std.ArrayList(SemanticEntry).empty;
    defer freeEntries(allocator, &entries);

    for (nodes) |node| {
        const maybe_entry = try buildEntry(allocator, node, &file_cache);
        if (maybe_entry) |entry| {
            try db.insertSemanticVector(project, entry.node_id, &entry.vector);
            try entries.append(allocator, entry);
        }
    }

    try emitSemanticEdges(allocator, db, project, entries.items);
}

pub fn search(
    allocator: std.mem.Allocator,
    db: *store.Store,
    project: []const u8,
    keywords: []const []const u8,
    limit: usize,
    offset: usize,
) !SearchPage {
    if (keywords.len == 0) {
        return .{ .total = 0, .hits = try allocator.alloc(SearchHit, 0) };
    }

    var query_vectors = std.ArrayList([vector_dim]i8).empty;
    defer query_vectors.deinit(allocator);
    for (keywords) |keyword| {
        const maybe_vector = try buildKeywordVector(allocator, keyword);
        if (maybe_vector) |vector| {
            try query_vectors.append(allocator, vector);
        }
    }
    if (query_vectors.items.len == 0) {
        return .{ .total = 0, .hits = try allocator.alloc(SearchHit, 0) };
    }

    const rows = try db.listSemanticVectors(project);
    defer db.freeSemanticVectorRows(rows);

    var scored = std.ArrayList(SearchHit).empty;
    errdefer freeSearchHitItems(allocator, scored.items);

    for (rows) |row| {
        const score = scoreQuery(query_vectors.items, row.vector);
        if (score <= 0) continue;
        try scored.append(allocator, .{
            .node = try cloneNode(allocator, row.node),
            .score = score,
        });
    }

    std.sort.block(SearchHit, scored.items, {}, searchHitLessThan);
    const total = scored.items.len;
    const start = @min(offset, total);
    const cap = if (limit == 0) default_query_limit else limit;
    const end = @min(start + cap, total);
    const out = try allocator.alloc(SearchHit, end - start);
    var out_idx: usize = 0;
    for (scored.items, 0..) |hit, idx| {
        if (idx >= start and idx < end) {
            out[out_idx] = hit;
            out_idx += 1;
        } else {
            freeSearchHit(allocator, hit);
        }
    }
    scored.deinit(allocator);

    return .{
        .total = total,
        .hits = out,
    };
}

pub fn freeSearchPage(allocator: std.mem.Allocator, page: SearchPage) void {
    freeSearchHitItems(allocator, page.hits);
    allocator.free(page.hits);
}

fn buildFileCache(
    allocator: std.mem.Allocator,
    files: []const discover.FileInfo,
) !std.StringHashMap(FileCache) {
    var out = std.StringHashMap(FileCache).init(allocator);
    errdefer {
        var it = out.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.content);
            allocator.free(entry.value_ptr.line_starts);
        }
        out.deinit();
    }

    for (files) |file| {
        const content = std.fs.cwd().readFileAlloc(allocator, file.path, 8 * 1024 * 1024) catch continue;
        const line_starts = try computeLineStarts(allocator, content);
        try out.put(
            try allocator.dupe(u8, file.rel_path),
            .{
                .content = content,
                .line_starts = line_starts,
            },
        );
    }
    return out;
}

fn freeFileCache(allocator: std.mem.Allocator, file_cache: *std.StringHashMap(FileCache)) void {
    var it = file_cache.iterator();
    while (it.next()) |entry| {
        allocator.free(entry.key_ptr.*);
        allocator.free(entry.value_ptr.content);
        allocator.free(entry.value_ptr.line_starts);
    }
    file_cache.deinit();
}

fn computeLineStarts(allocator: std.mem.Allocator, content: []const u8) ![]usize {
    var starts = std.ArrayList(usize).empty;
    errdefer starts.deinit(allocator);
    try starts.append(allocator, 0);
    for (content, 0..) |ch, idx| {
        if (ch == '\n' and idx + 1 <= content.len) {
            try starts.append(allocator, idx + 1);
        }
    }
    return starts.toOwnedSlice(allocator);
}

fn buildEntry(
    allocator: std.mem.Allocator,
    node: store.Node,
    file_cache: *const std.StringHashMap(FileCache),
) !?SemanticEntry {
    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();

    var tokens = std.ArrayList([]u8).empty;
    errdefer freeOwnedStringItems(allocator, tokens.items);
    errdefer tokens.deinit(allocator);

    try collectTokens(allocator, &seen, &tokens, node.name);
    try collectTokens(allocator, &seen, &tokens, node.qualified_name);
    try collectTokens(allocator, &seen, &tokens, node.file_path);
    try collectTokens(allocator, &seen, &tokens, node.label);
    try collectTokens(allocator, &seen, &tokens, node.properties_json);

    if (file_cache.get(node.file_path)) |cache| {
        if (sliceNodeSnippet(cache, node.start_line, node.end_line)) |snippet| {
            try collectTokens(allocator, &seen, &tokens, snippet);
        }
    }

    if (tokens.items.len == 0) return null;
    const vector = buildVector(tokens.items);
    const owned_tokens = try tokens.toOwnedSlice(allocator);

    return .{
        .node_id = node.id,
        .file_path = try allocator.dupe(u8, node.file_path),
        .tokens = owned_tokens,
        .vector = vector,
    };
}

fn sliceNodeSnippet(cache: FileCache, start_line: i32, end_line: i32) ?[]const u8 {
    if (start_line <= 0 or end_line < start_line) return null;
    const start_idx: usize = @intCast(start_line - 1);
    if (start_idx >= cache.line_starts.len) return null;
    const end_exclusive_idx: usize = @min(@as(usize, @intCast(end_line)), cache.line_starts.len);
    const start = cache.line_starts[start_idx];
    const finish = if (end_exclusive_idx < cache.line_starts.len)
        cache.line_starts[end_exclusive_idx]
    else
        cache.content.len;
    if (finish <= start or finish > cache.content.len) return null;
    return cache.content[start..finish];
}

fn collectTokens(
    allocator: std.mem.Allocator,
    seen: *std.StringHashMap(void),
    out: *std.ArrayList([]u8),
    text: []const u8,
) !void {
    var buffer = std.ArrayList(u8).empty;
    defer buffer.deinit(allocator);

    var prev_was_lower = false;
    for (text) |ch| {
        const is_alnum = std.ascii.isAlphanumeric(ch);
        if (!is_alnum) {
            try flushToken(allocator, seen, out, &buffer);
            prev_was_lower = false;
            continue;
        }

        if (std.ascii.isUpper(ch) and prev_was_lower and buffer.items.len > 0) {
            try flushToken(allocator, seen, out, &buffer);
        }

        try buffer.append(allocator, std.ascii.toLower(ch));
        prev_was_lower = std.ascii.isLower(ch);
    }
    try flushToken(allocator, seen, out, &buffer);
}

fn flushToken(
    allocator: std.mem.Allocator,
    seen: *std.StringHashMap(void),
    out: *std.ArrayList([]u8),
    buffer: *std.ArrayList(u8),
) !void {
    defer buffer.clearRetainingCapacity();
    if (buffer.items.len < min_token_len) return;
    if (isStopToken(buffer.items)) return;

    const owned = try allocator.dupe(u8, buffer.items);
    errdefer allocator.free(owned);
    const gop = try seen.getOrPut(owned);
    if (gop.found_existing) {
        allocator.free(owned);
        return;
    }
    try out.append(allocator, owned);
    try expandSynonyms(allocator, seen, out, owned);
}

fn expandSynonyms(
    allocator: std.mem.Allocator,
    seen: *std.StringHashMap(void),
    out: *std.ArrayList([]u8),
    token: []const u8,
) !void {
    const group = synonymGroup(token) orelse return;
    for (group) |synonym| {
        if (std.mem.eql(u8, synonym, token)) continue;
        const owned = try allocator.dupe(u8, synonym);
        errdefer allocator.free(owned);
        const gop = try seen.getOrPut(owned);
        if (gop.found_existing) {
            allocator.free(owned);
            continue;
        }
        try out.append(allocator, owned);
    }
}

fn synonymGroup(token: []const u8) ?[]const []const u8 {
    if (matchesAny(token, &.{ "send", "publish", "emit", "dispatch", "enqueue", "message", "event", "task" })) {
        return &.{ "send", "publish", "emit", "dispatch", "enqueue", "message", "event", "task" };
    }
    if (matchesAny(token, &.{ "route", "handler", "endpoint", "controller" })) {
        return &.{ "route", "handler", "endpoint", "controller" };
    }
    if (matchesAny(token, &.{ "error", "exception", "raise", "throw", "fail", "failure" })) {
        return &.{ "error", "exception", "raise", "throw", "fail", "failure" };
    }
    if (matchesAny(token, &.{ "log", "logger", "logging", "audit" })) {
        return &.{ "log", "logger", "logging", "audit" };
    }
    if (matchesAny(token, &.{ "auth", "authenticate", "authentication", "authorize", "authorization", "token" })) {
        return &.{ "auth", "authenticate", "authentication", "authorize", "authorization", "token" };
    }
    return null;
}

fn matchesAny(token: []const u8, group: []const []const u8) bool {
    for (group) |candidate| {
        if (std.mem.eql(u8, token, candidate)) return true;
    }
    return false;
}

fn isStopToken(token: []const u8) bool {
    return matchesAny(token, &.{
        "def",      "fn",     "let",    "var",  "const", "true", "false", "null", "self",  "this", "class",
        "function", "method", "return", "from", "with",  "into", "main",  "user", "users",
    });
}

fn buildVector(tokens: [][]u8) [vector_dim]i8 {
    var accum = [_]f32{0} ** vector_dim;
    for (tokens) |token| {
        const hash = std.hash.Wyhash.hash(0, token);
        const idx_a: usize = @intCast(hash % vector_dim);
        const idx_b: usize = @intCast((hash >> 17) % vector_dim);
        const idx_c: usize = @intCast((hash >> 33) % vector_dim);
        accum[idx_a] += 1.0;
        accum[idx_b] += 0.75;
        accum[idx_c] += 0.5;
    }

    var max_abs: f32 = 0;
    for (accum) |value| {
        const abs_value = @abs(value);
        if (abs_value > max_abs) max_abs = abs_value;
    }

    var out = [_]i8{0} ** vector_dim;
    if (max_abs == 0) return out;
    for (accum, 0..) |value, idx| {
        const normalized = (value / max_abs) * 127.0;
        const rounded = std.math.clamp(@round(normalized), -127.0, 127.0);
        out[idx] = @intFromFloat(rounded);
    }
    return out;
}

fn buildKeywordVector(allocator: std.mem.Allocator, keyword: []const u8) !?[vector_dim]i8 {
    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();

    var tokens = std.ArrayList([]u8).empty;
    defer {
        freeOwnedStringItems(allocator, tokens.items);
        tokens.deinit(allocator);
    }

    try collectTokens(allocator, &seen, &tokens, keyword);
    if (tokens.items.len == 0) return null;
    return buildVector(tokens.items);
}

fn emitSemanticEdges(
    allocator: std.mem.Allocator,
    db: *store.Store,
    project: []const u8,
    entries: []const SemanticEntry,
) !void {
    if (entries.len < 2) return;

    var buckets = std.StringHashMap(std.ArrayList(usize)).init(allocator);
    defer freeBuckets(allocator, &buckets);

    for (entries, 0..) |entry, idx| {
        for (entry.tokens) |token| {
            const gop = try buckets.getOrPut(token);
            if (!gop.found_existing) {
                gop.key_ptr.* = try allocator.dupe(u8, token);
                gop.value_ptr.* = .empty;
            }
            try gop.value_ptr.append(allocator, idx);
        }
    }

    for (entries, 0..) |entry, idx| {
        var seen = std.AutoHashMap(usize, void).init(allocator);
        defer seen.deinit();
        var scored = std.ArrayList(ScoredIndex).empty;
        defer scored.deinit(allocator);

        for (entry.tokens) |token| {
            const bucket = buckets.get(token) orelse continue;
            if (bucket.items.len > max_bucket_size) continue;
            for (bucket.items) |candidate_idx| {
                if (candidate_idx == idx) continue;
                if (seen.contains(candidate_idx)) continue;
                try seen.put(candidate_idx, {});
                const score = cosine(entry.vector, entries[candidate_idx].vector);
                if (score < min_edge_score) continue;
                try scored.append(allocator, .{
                    .idx = candidate_idx,
                    .score = score,
                });
            }
        }

        std.sort.block(ScoredIndex, scored.items, {}, scoredIndexLessThan);
        const capped = @min(scored.items.len, max_edges_per_node);
        for (scored.items[0..capped]) |match| {
            const target = entries[match.idx];
            const props = try std.fmt.allocPrint(
                allocator,
                "{{\"score\":{d:.3},\"same_file\":{s}}}",
                .{ match.score, if (std.mem.eql(u8, entry.file_path, target.file_path)) "true" else "false" },
            );
            defer allocator.free(props);
            _ = try db.upsertEdge(.{
                .project = project,
                .source_id = entry.node_id,
                .target_id = target.node_id,
                .edge_type = "SEMANTICALLY_RELATED",
                .properties_json = props,
            });
        }
    }
}

fn freeBuckets(
    allocator: std.mem.Allocator,
    buckets: *std.StringHashMap(std.ArrayList(usize)),
) void {
    var it = buckets.iterator();
    while (it.next()) |entry| {
        allocator.free(entry.key_ptr.*);
        entry.value_ptr.deinit(allocator);
    }
    buckets.deinit();
}

fn cosine(a: [vector_dim]i8, b: [vector_dim]i8) f64 {
    var dot: f64 = 0;
    var norm_a: f64 = 0;
    var norm_b: f64 = 0;
    for (a, 0..) |lhs, idx| {
        const rhs = b[idx];
        const lhs_f = @as(f64, @floatFromInt(lhs));
        const rhs_f = @as(f64, @floatFromInt(rhs));
        dot += lhs_f * rhs_f;
        norm_a += lhs_f * lhs_f;
        norm_b += rhs_f * rhs_f;
    }
    if (norm_a == 0 or norm_b == 0) return 0;
    return dot / (std.math.sqrt(norm_a) * std.math.sqrt(norm_b));
}

fn scoreQuery(query_vectors: []const [vector_dim]i8, node_vector: []const i8) f64 {
    if (node_vector.len != vector_dim) return 0;
    var fixed = [_]i8{0} ** vector_dim;
    @memcpy(fixed[0..], node_vector[0..vector_dim]);

    var min_score: ?f64 = null;
    for (query_vectors) |query_vector| {
        const score = cosine(query_vector, fixed);
        if (min_score == null or score < min_score.?) {
            min_score = score;
        }
    }
    return if (min_score) |score| score else 0;
}

fn cloneNode(allocator: std.mem.Allocator, node: store.Node) !store.Node {
    return .{
        .id = node.id,
        .project = try allocator.dupe(u8, node.project),
        .label = try allocator.dupe(u8, node.label),
        .name = try allocator.dupe(u8, node.name),
        .qualified_name = try allocator.dupe(u8, node.qualified_name),
        .file_path = try allocator.dupe(u8, node.file_path),
        .start_line = node.start_line,
        .end_line = node.end_line,
        .properties_json = try allocator.dupe(u8, node.properties_json),
    };
}

fn searchHitLessThan(_: void, lhs: SearchHit, rhs: SearchHit) bool {
    if (lhs.score == rhs.score) {
        return std.mem.order(u8, lhs.node.name, rhs.node.name) == .lt;
    }
    return lhs.score > rhs.score;
}

fn scoredIndexLessThan(_: void, lhs: ScoredIndex, rhs: ScoredIndex) bool {
    if (lhs.score == rhs.score) return lhs.idx < rhs.idx;
    return lhs.score > rhs.score;
}

fn freeEntries(allocator: std.mem.Allocator, entries: *std.ArrayList(SemanticEntry)) void {
    for (entries.items) |entry| {
        allocator.free(entry.file_path);
        freeOwnedStringsSlice(allocator, entry.tokens);
    }
    entries.deinit(allocator);
    entries.* = .empty;
}

fn freeOwnedStringItems(allocator: std.mem.Allocator, values: []const []u8) void {
    for (values) |value| allocator.free(value);
}

fn freeOwnedStringsSlice(allocator: std.mem.Allocator, values: []const []u8) void {
    freeOwnedStringItems(allocator, values);
    allocator.free(values);
}

fn freeSearchHit(allocator: std.mem.Allocator, hit: SearchHit) void {
    allocator.free(hit.node.project);
    allocator.free(hit.node.label);
    allocator.free(hit.node.name);
    allocator.free(hit.node.qualified_name);
    allocator.free(hit.node.file_path);
    allocator.free(hit.node.properties_json);
}

fn freeSearchHitItems(allocator: std.mem.Allocator, hits: []const SearchHit) void {
    for (hits) |hit| freeSearchHit(allocator, hit);
}

test "semantic index bridges publish to send_task style code" {
    const allocator = std.testing.allocator;

    const project_dir = "testdata/interop/semantic-expansion/celery_send_task";
    const files = try discover.discoverFiles(allocator, project_dir, .{ .mode = .full });
    defer {
        for (files) |file| {
            allocator.free(file.path);
            allocator.free(file.rel_path);
        }
        allocator.free(files);
    }

    var db = try store.Store.openMemory(allocator);
    defer db.deinit();

    var pipeline = @import("pipeline.zig").Pipeline.init(allocator, project_dir, .moderate);
    defer pipeline.deinit();
    try pipeline.run(&db);

    const rows = try db.listSemanticVectors("celery_send_task");
    defer db.freeSemanticVectorRows(rows);
    try std.testing.expectEqual(@as(usize, 2), rows.len);

    const query_vector = (try buildKeywordVector(allocator, "publish")).?;
    try std.testing.expect(scoreQuery(&.{query_vector}, rows[0].vector) > 0 or scoreQuery(&.{query_vector}, rows[1].vector) > 0);

    const page = try search(allocator, &db, "celery_send_task", &.{"publish"}, 5, 0);
    defer freeSearchPage(allocator, page);

    try std.testing.expect(page.total > 0);
    try std.testing.expect(std.mem.eql(u8, page.hits[0].node.name, "enqueue_users") or std.mem.eql(u8, page.hits[0].node.name, "refresh_users"));

    const related = try db.listEdges("celery_send_task", "SEMANTICALLY_RELATED");
    defer db.freeEdges(related);
    try std.testing.expect(related.len > 0);
}

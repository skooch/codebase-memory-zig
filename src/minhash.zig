// minhash.zig — MinHash fingerprinting + LSH for near-clone detection.
//
// The Zig port uses a normalized lexical token stream instead of full AST leaf
// walks for now. That keeps the similarity pass deterministic across the
// supported languages while still giving us durable near-clone detection and a
// stable `SIMILAR_TO` post-pass.

const std = @import("std");

pub const k: usize = 64;
pub const bands: usize = 32;
pub const rows: usize = 2;
pub const min_nodes: usize = 20;
pub const min_unique_trigrams: usize = 16;
pub const jaccard_threshold: f64 = 0.95;
pub const max_edges_per_node: usize = 10;
pub const max_bucket_size: usize = 200;

const normal_identifier = "I";
const normal_string = "S";
const normal_number = "N";

const TokenClass = enum {
    raw,
    identifier,
    string,
    number,
};

const Token = struct {
    slice: []const u8,
    class: TokenClass,
};

pub const Fingerprint = struct {
    values: [k]u32 = [_]u32{std.math.maxInt(u32)} ** k,
};

pub const Entry = struct {
    node_id: i64,
    fingerprint: Fingerprint,
    file_path: []const u8,
    file_ext: []const u8,
};

pub const LshIndex = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(Entry),
    buckets: std.AutoHashMap(u64, std.ArrayList(usize)),

    pub fn init(allocator: std.mem.Allocator) LshIndex {
        return .{
            .allocator = allocator,
            .entries = .empty,
            .buckets = std.AutoHashMap(u64, std.ArrayList(usize)).init(allocator),
        };
    }

    pub fn deinit(self: *LshIndex) void {
        var it = self.buckets.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.buckets.deinit();
        self.entries.deinit(self.allocator);
    }

    pub fn insert(self: *LshIndex, entry: Entry) !usize {
        const idx = self.entries.items.len;
        try self.entries.append(self.allocator, entry);
        for (0..bands) |band| {
            const key = bandKey(&entry.fingerprint, band);
            const gop = try self.buckets.getOrPut(key);
            if (!gop.found_existing) {
                gop.value_ptr.* = .empty;
            }
            try gop.value_ptr.append(self.allocator, idx);
        }
        return idx;
    }

    pub fn query(self: *const LshIndex, fp: *const Fingerprint, out: *std.ArrayList(usize)) !void {
        var seen = std.AutoHashMap(usize, void).init(self.allocator);
        defer seen.deinit();

        for (0..bands) |band| {
            const key = bandKey(fp, band);
            const bucket = self.buckets.get(key) orelse continue;
            if (bucket.items.len > max_bucket_size) continue;
            for (bucket.items) |idx| {
                if (seen.contains(idx)) continue;
                try seen.put(idx, {});
                try out.append(self.allocator, idx);
            }
        }
    }
};

pub fn computeFromSource(allocator: std.mem.Allocator, source: []const u8) !?Fingerprint {
    const tokens = try tokenizeSource(allocator, source);
    defer allocator.free(tokens);

    if (tokens.len < min_nodes) return null;

    var fp = Fingerprint{};
    var unique = std.AutoHashMap(u64, void).init(allocator);
    defer unique.deinit();

    var trigram_buf: [256]u8 = undefined;
    for (0..tokens.len - 2) |i| {
        const token_a = normalizedToken(tokens[i]);
        const token_b = normalizedToken(tokens[i + 1]);
        const token_c = normalizedToken(tokens[i + 2]);
        const weight = trigramWeight(tokens[i], tokens[i + 1], tokens[i + 2]);
        if (weight == 0) continue;

        const trigram = encodeTrigram(&trigram_buf, token_a, token_b, token_c) orelse continue;
        try unique.put(wyhash(0, trigram), {});
        applyWeightedMinhash(&fp, trigram, weight);
    }

    if (unique.count() < min_unique_trigrams) return null;
    return fp;
}

pub fn jaccard(a: *const Fingerprint, b: *const Fingerprint) f64 {
    var agree: u32 = 0;
    for (0..k) |i| {
        if (a.values[i] == b.values[i]) agree += 1;
    }
    return @as(f64, @floatFromInt(agree)) / @as(f64, @floatFromInt(k));
}

pub fn toHex(fp: *const Fingerprint, buf: *[k * 8]u8) void {
    for (fp.values, 0..) |val, i| {
        _ = std.fmt.bufPrint(buf[i * 8 .. i * 8 + 8], "{x:0>8}", .{val}) catch unreachable;
    }
}

pub fn fromHex(hex: []const u8) ?Fingerprint {
    if (hex.len != k * 8) return null;

    var fp = Fingerprint{};
    for (0..k) |i| {
        const start = i * 8;
        const end = start + 8;
        fp.values[i] = std.fmt.parseUnsigned(u32, hex[start..end], 16) catch return null;
    }
    return fp;
}

fn tokenizeSource(allocator: std.mem.Allocator, source: []const u8) ![]Token {
    var tokens = std.ArrayList(Token).empty;
    errdefer tokens.deinit(allocator);

    var idx: usize = 0;
    while (idx < source.len) {
        const ch = source[idx];
        if (std.ascii.isWhitespace(ch)) {
            idx += 1;
            continue;
        }

        if (ch == '#') {
            idx = skipToLineEnd(source, idx);
            continue;
        }
        if (ch == '/' and idx + 1 < source.len) {
            if (source[idx + 1] == '/') {
                idx = skipToLineEnd(source, idx + 2);
                continue;
            }
            if (source[idx + 1] == '*') {
                idx = skipBlockComment(source, idx + 2);
                continue;
            }
        }

        if (isStringDelimiter(ch)) {
            const end = scanStringLiteral(source, idx);
            try tokens.append(allocator, .{ .slice = source[idx..end], .class = .string });
            idx = end;
            continue;
        }

        if (std.ascii.isDigit(ch)) {
            const end = scanNumber(source, idx);
            try tokens.append(allocator, .{ .slice = source[idx..end], .class = .number });
            idx = end;
            continue;
        }

        if (isIdentifierStart(ch)) {
            const end = scanIdentifier(source, idx);
            const token_slice = source[idx..end];
            try tokens.append(allocator, .{
                .slice = token_slice,
                .class = if (isKeyword(token_slice)) .raw else .identifier,
            });
            idx = end;
            continue;
        }

        const punct_end = scanPunctuation(source, idx);
        try tokens.append(allocator, .{ .slice = source[idx..punct_end], .class = .raw });
        idx = punct_end;
    }

    return tokens.toOwnedSlice(allocator);
}

fn normalizedToken(token: Token) []const u8 {
    return switch (token.class) {
        .identifier => normal_identifier,
        .string => normal_string,
        .number => normal_number,
        .raw => token.slice,
    };
}

fn trigramWeight(a: Token, b: Token, c: Token) u32 {
    var weight: u32 = 0;
    if (a.class == .raw) weight += 1;
    if (b.class == .raw) weight += 1;
    if (c.class == .raw) weight += 1;
    return weight;
}

fn encodeTrigram(buf: []u8, a: []const u8, b: []const u8, c: []const u8) ?[]const u8 {
    var pos: usize = 0;
    pos = appendSlice(buf, pos, a) orelse return null;
    pos = appendByte(buf, pos, '|') orelse return null;
    pos = appendSlice(buf, pos, b) orelse return null;
    pos = appendByte(buf, pos, '|') orelse return null;
    pos = appendSlice(buf, pos, c) orelse return null;
    return buf[0..pos];
}

fn appendSlice(buf: []u8, pos: usize, slice: []const u8) ?usize {
    if (pos + slice.len > buf.len) return null;
    @memcpy(buf[pos .. pos + slice.len], slice);
    return pos + slice.len;
}

fn appendByte(buf: []u8, pos: usize, byte: u8) ?usize {
    if (pos >= buf.len) return null;
    buf[pos] = byte;
    return pos + 1;
}

fn applyWeightedMinhash(fp: *Fingerprint, trigram: []const u8, weight: u32) void {
    for (0..k) |idx| {
        var rep: u32 = 0;
        while (rep < weight) : (rep += 1) {
            const seed = @as(u64, @intCast(idx * 3)) + rep + 1;
            const value = @as(u32, @truncate(wyhash(seed, trigram)));
            if (value < fp.values[idx]) {
                fp.values[idx] = value;
            }
        }
    }
}

fn bandKey(fp: *const Fingerprint, band: usize) u64 {
    const base = band * rows;
    const pair = [2]u32{ fp.values[base], fp.values[base + 1] };
    const hash = @as(u32, @truncate(wyhash(0, std.mem.asBytes(&pair))));
    return (@as(u64, @intCast(band)) << 32) | hash;
}

fn wyhash(seed: u64, data: []const u8) u64 {
    return std.hash.Wyhash.hash(seed, data);
}

fn skipToLineEnd(source: []const u8, start: usize) usize {
    var idx = start;
    while (idx < source.len and source[idx] != '\n') : (idx += 1) {}
    return idx;
}

fn skipBlockComment(source: []const u8, start: usize) usize {
    var idx = start;
    while (idx + 1 < source.len) : (idx += 1) {
        if (source[idx] == '*' and source[idx + 1] == '/') {
            return idx + 2;
        }
    }
    return source.len;
}

fn isStringDelimiter(ch: u8) bool {
    return ch == '"' or ch == '\'' or ch == '`';
}

fn scanStringLiteral(source: []const u8, start: usize) usize {
    const delimiter = source[start];
    var idx = start + 1;
    while (idx < source.len) : (idx += 1) {
        if (source[idx] == '\\') {
            idx += 1;
            continue;
        }
        if (source[idx] == delimiter) return idx + 1;
    }
    return source.len;
}

fn scanNumber(source: []const u8, start: usize) usize {
    var idx = start + 1;
    while (idx < source.len) : (idx += 1) {
        const ch = source[idx];
        if (!(std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '.')) break;
    }
    return idx;
}

fn isIdentifierStart(ch: u8) bool {
    return std.ascii.isAlphabetic(ch) or ch == '_';
}

fn scanIdentifier(source: []const u8, start: usize) usize {
    var idx = start + 1;
    while (idx < source.len) : (idx += 1) {
        const ch = source[idx];
        if (!(std.ascii.isAlphanumeric(ch) or ch == '_')) break;
    }
    return idx;
}

fn scanPunctuation(source: []const u8, start: usize) usize {
    if (start + 1 < source.len) {
        const pair = source[start .. start + 2];
        if (std.mem.eql(u8, pair, "->") or
            std.mem.eql(u8, pair, "=>") or
            std.mem.eql(u8, pair, "::") or
            std.mem.eql(u8, pair, "==") or
            std.mem.eql(u8, pair, "!=") or
            std.mem.eql(u8, pair, "<=") or
            std.mem.eql(u8, pair, ">=") or
            std.mem.eql(u8, pair, "&&") or
            std.mem.eql(u8, pair, "||"))
        {
            return start + 2;
        }
    }
    return start + 1;
}

fn isKeyword(token: []const u8) bool {
    const keywords = [_][]const u8{
        "async",    "await",    "break", "case", "catch",  "class",  "const",
        "continue", "def",      "else",  "enum", "export", "fn",     "for",
        "from",     "function", "if",    "impl", "import", "in",     "interface",
        "let",      "match",    "new",   "pub",  "return", "struct", "switch",
        "trait",    "try",      "type",  "use",  "var",    "while",
    };
    for (keywords) |keyword| {
        if (std.mem.eql(u8, token, keyword)) return true;
    }
    return false;
}

test "jaccard identical" {
    var a = Fingerprint{};
    a.values[0] = 42;
    a.values[1] = 99;
    const j = jaccard(&a, &a);
    try std.testing.expectEqual(@as(f64, 1.0), j);
}

test "jaccard different" {
    var a = Fingerprint{};
    var b = Fingerprint{};
    for (0..k) |i| {
        a.values[i] = @intCast(i);
        b.values[i] = @intCast(i + k);
    }
    const j = jaccard(&a, &b);
    try std.testing.expectEqual(@as(f64, 0.0), j);
}

test "computeFromSource normalizes renamed identifiers" {
    const allocator = std.testing.allocator;
    const source_a =
        \\def run(value):
        \\    total = value + 1
        \\    if total > 10:
        \\        return total
        \\    return value
        \\
    ;
    const source_b =
        \\def run(item):
        \\    total = item + 1
        \\    if total > 10:
        \\        return total
        \\    return item
        \\
    ;

    const fp_a = (try computeFromSource(allocator, source_a)).?;
    const fp_b = (try computeFromSource(allocator, source_b)).?;
    try std.testing.expect(jaccard(&fp_a, &fp_b) >= 0.95);
}

test "hex roundtrip preserves fingerprint" {
    var fp = Fingerprint{};
    for (0..k) |idx| {
        fp.values[idx] = @intCast(idx * 17);
    }

    var buf: [k * 8]u8 = undefined;
    toHex(&fp, &buf);
    const parsed = fromHex(&buf).?;
    try std.testing.expectEqualDeep(fp, parsed);
}

test "lsh query returns inserted near-duplicate candidate" {
    const allocator = std.testing.allocator;
    const source_a =
        \\function run(value) {
        \\  const total = value + 1;
        \\  if (total > 10) {
        \\    return total;
        \\  }
        \\  return value;
        \\}
        \\
    ;
    const source_b =
        \\function run(item) {
        \\  const total = item + 1;
        \\  if (total > 10) {
        \\    return total;
        \\  }
        \\  return item;
        \\}
        \\
    ;
    const fp_a = (try computeFromSource(allocator, source_a)).?;
    const fp_b = (try computeFromSource(allocator, source_b)).?;

    var index = LshIndex.init(allocator);
    defer index.deinit();
    _ = try index.insert(.{
        .node_id = 1,
        .fingerprint = fp_a,
        .file_path = "a.js",
        .file_ext = ".js",
    });

    var candidates = std.ArrayList(usize).empty;
    defer candidates.deinit(allocator);
    try index.query(&fp_b, &candidates);
    try std.testing.expectEqual(@as(usize, 1), candidates.items.len);
}

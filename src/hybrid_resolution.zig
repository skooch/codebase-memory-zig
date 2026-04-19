const std = @import("std");

const max_sidecar_bytes = 2 * 1024 * 1024;
const sidecar_rel_path = ".codebase-memory/hybrid-resolution.json";

const SidecarFile = struct {
    version: []const u8 = "0.1",
    source: []const u8 = "hybrid-resolution",
    documents: []const Document = &.{},
};

const Document = struct {
    rel_path: []const u8,
    language: []const u8 = "",
    resolved_calls: []const ResolvedCall = &.{},
};

const ResolvedCall = struct {
    caller_qualified_name: []const u8,
    callee_name: []const u8 = "",
    full_callee_name: []const u8 = "",
    resolved_qualified_name: []const u8,
    strategy: []const u8 = "hybrid_sidecar",
    confidence: f64 = 0.95,
};

pub const Resolution = struct {
    qualified_name: []const u8,
    strategy: []const u8,
    confidence: f64,
};

pub const Sidecar = struct {
    allocator: std.mem.Allocator = undefined,
    bytes: ?[]u8 = null,
    parsed: ?std.json.Parsed(SidecarFile) = null,

    pub fn initEmpty() Sidecar {
        return .{ .allocator = undefined };
    }

    pub fn load(allocator: std.mem.Allocator, repo_path: []const u8) !Sidecar {
        const path = try std.fs.path.join(allocator, &.{ repo_path, sidecar_rel_path });
        defer allocator.free(path);

        const bytes = std.fs.cwd().readFileAlloc(allocator, path, max_sidecar_bytes) catch |err| switch (err) {
            error.FileNotFound => return .{},
            else => return err,
        };
        errdefer allocator.free(bytes);

        return .{
            .allocator = allocator,
            .bytes = bytes,
            .parsed = try std.json.parseFromSlice(SidecarFile, allocator, bytes, .{
                .ignore_unknown_fields = true,
            }),
        };
    }

    pub fn deinit(self: *Sidecar) void {
        if (self.parsed) |*parsed| {
            parsed.deinit();
            self.parsed = null;
        }
        if (self.bytes) |bytes| {
            self.allocator.free(bytes);
            self.bytes = null;
        }
    }

    pub fn resolveCall(
        self: *const Sidecar,
        file_path: []const u8,
        caller_qualified_name: []const u8,
        callee_name: []const u8,
        full_callee_name: []const u8,
    ) ?Resolution {
        const parsed = self.parsed orelse return null;
        for (parsed.value.documents) |document| {
            if (!std.mem.eql(u8, document.rel_path, file_path)) continue;
            if (!supportsDocument(document.language)) continue;
            for (document.resolved_calls) |call| {
                if (!std.mem.eql(u8, call.caller_qualified_name, caller_qualified_name)) continue;
                if (!callMatches(call, callee_name, full_callee_name)) continue;
                return .{
                    .qualified_name = call.resolved_qualified_name,
                    .strategy = call.strategy,
                    .confidence = call.confidence,
                };
            }
        }
        return null;
    }
};

fn supportsDocument(language: []const u8) bool {
    if (language.len == 0) return true;
    return std.ascii.eqlIgnoreCase(language, "go") or
        std.ascii.eqlIgnoreCase(language, "golang");
}

fn callMatches(
    resolved_call: ResolvedCall,
    callee_name: []const u8,
    full_callee_name: []const u8,
) bool {
    if (resolved_call.full_callee_name.len > 0 and
        std.mem.eql(u8, resolved_call.full_callee_name, full_callee_name))
    {
        return true;
    }
    if (resolved_call.callee_name.len > 0 and
        std.mem.eql(u8, resolved_call.callee_name, callee_name))
    {
        return true;
    }
    return false;
}

test "hybrid resolution sidecar is optional when missing" {
    const allocator = std.testing.allocator;
    const repo_dir = try std.fmt.allocPrint(allocator, "/tmp/cbm-hybrid-missing-{x}", .{std.crypto.random.int(u64)});
    defer allocator.free(repo_dir);
    try std.fs.cwd().makePath(repo_dir);
    defer std.fs.cwd().deleteTree(repo_dir) catch {};

    var sidecar = try Sidecar.load(allocator, repo_dir);
    defer sidecar.deinit();

    try std.testing.expectEqual(@as(?Resolution, null), sidecar.resolveCall(
        "main.go",
        "demo:main.go:go:symbol:go:run",
        "Handle",
        "selected.Handle",
    ));
}

test "hybrid resolution fixture-backed lookup resolves explicit call target" {
    const allocator = std.testing.allocator;
    const repo_dir = "testdata/interop/hybrid-resolution/go-sidecar";

    var sidecar = try Sidecar.load(allocator, repo_dir);
    defer sidecar.deinit();

    const resolved = sidecar.resolveCall(
        "main.go",
        "go-sidecar:main.go:go:symbol:go:run",
        "Handle",
        "selected.Handle",
    ) orelse return error.TestUnexpectedResult;

    try std.testing.expectEqualStrings(
        "go-sidecar:workers.go:go:symbol:go:Primary.Handle",
        resolved.qualified_name,
    );
    try std.testing.expectEqualStrings("hybrid_sidecar", resolved.strategy);
    try std.testing.expectApproxEqAbs(@as(f64, 0.97), resolved.confidence, 0.0001);
}

test "hybrid resolution supports language aliases and callee-name fallback" {
    const allocator = std.testing.allocator;
    const repo_dir = "testdata/interop/hybrid-resolution/go-sidecar-expanded";

    var sidecar = try Sidecar.load(allocator, repo_dir);
    defer sidecar.deinit();

    const explicit = sidecar.resolveCall(
        "main.go",
        "go-sidecar-expanded:main.go:go:symbol:go:run",
        "Handle",
        "selected.Handle",
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(
        "go-sidecar-expanded:workers.go:go:symbol:go:Primary.Handle",
        explicit.qualified_name,
    );
    try std.testing.expectApproxEqAbs(@as(f64, 0.96), explicit.confidence, 0.0001);

    const fallback = sidecar.resolveCall(
        "extras.go",
        "go-sidecar-expanded:extras.go:go:symbol:go:execute",
        "Handle",
        "worker.Handle",
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(
        "go-sidecar-expanded:workers.go:go:symbol:go:Worker.Handle",
        fallback.qualified_name,
    );
    try std.testing.expectEqualStrings("hybrid_sidecar", fallback.strategy);
    try std.testing.expectApproxEqAbs(@as(f64, 0.95), fallback.confidence, 0.0001);
}

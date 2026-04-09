const std = @import("std");
const cbm = @import("cbm");
const build_options = @import("build_options");

const usage =
    \\Usage: cbm [COMMAND] [OPTIONS]
    \\
    \\Codebase knowledge graph — MCP server and CLI.
    \\
    \\Commands:
    \\  cli <tool> [json]       Run a single tool call
    \\  install [-y|-n]         Install MCP server config for supported agents
    \\  uninstall [-y|-n]       Remove MCP server config
    \\  update [-y|-n]          Update to latest version
    \\  config <list|get|set>   Manage runtime configuration
    \\
    \\Options:
    \\  --version               Print version and exit
    \\  --help                  Print this help message
    \\
    \\When run without a command, starts the MCP server on stdio.
    \\
;

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next(); // skip argv[0]

    const stdout_file = std.fs.File.stdout();

    // Check for subcommand / flags.
    if (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--version")) {
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "codebase-memory {s}\n", .{build_options.version}) catch "codebase-memory dev\n";
            try stdout_file.writeAll(msg);
            return;
        }
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try stdout_file.writeAll(usage);
            return;
        }
        if (std.mem.eql(u8, arg, "cli")) {
            try runCliToolCall(allocator);
            return;
        }
        if (std.mem.eql(u8, arg, "install")) {
            std.debug.print("install not yet implemented\n", .{});
            return;
        }
        if (std.mem.eql(u8, arg, "uninstall")) {
            std.debug.print("uninstall not yet implemented\n", .{});
            return;
        }
        if (std.mem.eql(u8, arg, "update")) {
            std.debug.print("update not yet implemented\n", .{});
            return;
        }
        if (std.mem.eql(u8, arg, "config")) {
            std.debug.print("config not yet implemented\n", .{});
            return;
        }
        std.debug.print("Error: unknown command \"{s}\"\n", .{arg});
        std.debug.print("{s}", .{usage});
        std.process.exit(1);
    }

    // Default: run MCP server on stdio.
    try runMcpServer(allocator);
}

fn runMcpServer(allocator: std.mem.Allocator) !void {
    var db = try cbm.Store.openMemory(allocator);
    defer db.deinit();

    var server = cbm.McpServer.init(allocator, &db);
    defer server.deinit();

    // MCP reads newline-delimited JSON-RPC from stdin, writes to stdout.
    // For now, use the low-level file APIs. The MCP server handles buffering.
    const stdin_file = std.fs.File.stdin();
    const stdout_file = std.fs.File.stdout();

    try server.runFiles(stdin_file, stdout_file);
}

const CliToolRequest = struct {
    jsonrpc: []const u8 = "2.0",
    id: i32 = 1,
    method: []const u8 = "tools/call",
    params: CliToolParams,
};

const CliToolParams = struct {
    name: []const u8,
    arguments: std.json.Value,
};

fn runCliToolCall(allocator: std.mem.Allocator) !void {
    const stdout_file = std.fs.File.stdout();

    var args_iter = try std.process.argsWithAllocator(allocator);
    defer args_iter.deinit();
    _ = args_iter.next(); // skip argv[0]
    _ = args_iter.next(); // skip "cli"

    const tool_name = args_iter.next() orelse {
        try stdout_file.writeAll("Error: cli requires <tool>\n");
        std.process.exit(1);
    };

    const raw_args = args_iter.next() orelse "{}";
    if (args_iter.next()) |_| {
        try stdout_file.writeAll("Error: too many cli arguments\n");
        std.process.exit(1);
    }

    const parsed_args = try std.json.parseFromSlice(std.json.Value, allocator, raw_args, .{});
    defer parsed_args.deinit();
    if (parsed_args.value != .object) {
        try stdout_file.writeAll("Error: cli arguments must be a JSON object\n");
        std.process.exit(1);
    }

    const request = CliToolRequest{
        .params = .{
            .name = tool_name,
            .arguments = parsed_args.value,
        },
    };

    var request_bytes = std.ArrayList(u8).empty;
    defer request_bytes.deinit(allocator);
    try std.json.stringify(request, .{}, request_bytes.writer(allocator));
    const request_payload = try request_bytes.toOwnedSlice(allocator);
    defer allocator.free(request_payload);

    var db = try cbm.Store.openMemory(allocator);
    defer db.deinit();
    var server = cbm.McpServer.init(allocator, &db);
    defer server.deinit();

    if (try server.handleRequest(request_payload)) |resp| {
        defer allocator.free(resp);
        try stdout_file.writeAll(resp);
        try stdout_file.writeByte('\n');
    }
}

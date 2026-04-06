// mcp.zig — MCP (Model Context Protocol) JSON-RPC server.
//
// Implements JSON-RPC 2.0 over stdio with the MCP tool calling protocol.
// Provides graph analysis tools (search, trace, query, index, etc.)

const std = @import("std");

pub const Tool = enum {
    index_repository,
    search_graph,
    query_graph,
    trace_call_path,
    get_code_snippet,
    get_graph_schema,
    get_architecture,
    search_code,
    list_projects,
    delete_project,
    index_status,
    detect_changes,
    manage_adr,
    ingest_traces,
};

pub const McpServer = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) McpServer {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *McpServer) void {
        _ = self;
    }

    /// Run the MCP server reading JSON-RPC from stdin_file, writing to stdout_file.
    pub fn runFiles(self: *McpServer, stdin_file: std.fs.File, stdout_file: std.fs.File) !void {
        var line_buf: [64 * 1024]u8 = undefined;

        while (true) {
            // Read one line from stdin.
            const n = stdin_file.read(&line_buf) catch |err| {
                if (err == error.BrokenPipe) return;
                return err;
            };
            if (n == 0) return; // EOF

            const response = self.handleLine(line_buf[0..n]);
            if (response) |resp| {
                try stdout_file.writeAll(resp);
                try stdout_file.writeAll("\n");
            }
        }
    }

    /// Old generic interface for testing.
    pub fn run(self: *McpServer, reader: anytype, writer: anytype) !void {
        var buf: [64 * 1024]u8 = undefined;

        while (true) {
            const line = reader.readUntilDelimiter(&buf, '\n') catch |err| {
                if (err == error.EndOfStream) return;
                return err;
            };

            const response = self.handleLine(line);
            if (response) |resp| {
                try writer.writeAll(resp);
                try writer.writeByte('\n');
            }
        }
    }

    fn handleLine(self: *McpServer, line: []const u8) ?[]const u8 {
        _ = self;
        _ = line;
        // TODO: parse JSON-RPC, dispatch to tool handler
        return null;
    }
};

test "mcp server init/deinit" {
    var srv = McpServer.init(std.testing.allocator);
    defer srv.deinit();
}

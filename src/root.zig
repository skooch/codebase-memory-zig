// codebase-memory — Knowledge graph indexing engine for codebases.
//
// Module root. Re-exports the public API surface.

pub const store = @import("store.zig");
pub const adr = @import("adr.zig");
pub const graph_buffer = @import("graph_buffer.zig");
pub const pipeline = @import("pipeline.zig");
pub const test_tagging = @import("test_tagging.zig");
pub const runtime_lifecycle = @import("runtime_lifecycle.zig");
pub const mcp = @import("mcp.zig");
pub const cypher = @import("cypher.zig");
pub const discover = @import("discover.zig");
pub const watcher = @import("watcher.zig");
pub const registry = @import("registry.zig");
pub const minhash = @import("minhash.zig");

// Re-export core types at top level for convenience.
pub const Store = store.Store;
pub const Node = store.Node;
pub const Edge = store.Edge;
pub const GraphBuffer = graph_buffer.GraphBuffer;
pub const Pipeline = pipeline.Pipeline;
pub const IndexMode = pipeline.IndexMode;
pub const McpServer = mcp.McpServer;
pub const Language = discover.Language;

test {
    _ = store;
    _ = adr;
    _ = graph_buffer;
    _ = pipeline;
    _ = test_tagging;
    _ = runtime_lifecycle;
    _ = mcp;
    _ = cypher;
    _ = discover;
    _ = watcher;
    _ = registry;
    _ = minhash;
    _ = @import("store_test.zig");
}

# Language Support

This repo uses three different support labels and does not treat them as
interchangeable.

## Detection Only

A language can be recognized by file extension and still have no parser-backed
extraction. Detection alone only means the file is classified, not that code
definitions or graph edges will be useful.

## Parser-Backed Extraction

Parser-backed support means the repo wires a tree-sitter grammar into the build,
detects the language explicitly, and proves a bounded extraction contract with
tests or fixture-backed indexing checks.

Current parser-backed languages in the Zig port:
- Python
- JavaScript
- TypeScript
- TSX
- Rust
- Zig
- Go
- Java
- PowerShell
- GDScript

For some of these, the verified contract is still intentionally narrow. Parser
support does not automatically imply full call resolution, data-flow fidelity,
or parity with the original implementation.

## Higher-Level Semantic Parity

Semantic parity is stricter than parser-backed extraction. It covers the
language-specific behavior that users actually query for, such as:
- stable definition ownership
- basic search visibility
- call-edge resolution
- type or framework-specific enrichment

The Zig port only claims semantic parity where a language or feature lane is
explicitly verified in the repo docs and tests.

## Deferred Languages

QML is intentionally deferred after the PowerShell and GDScript tranche. The
grammar exists, but the first useful contract is already tied to the QML object
model, properties, signals, and inline components, which makes it a larger
onboarding slice than this tranche allows.

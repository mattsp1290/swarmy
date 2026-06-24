# MCP v1 Protocol Decision

Swarmy v1 exposes a small local JSON-RPC stdio adapter for MCP-shaped tool calls.
The advertised MCP protocol version is `2025-06-18`.

The local `~/git/nimcp` fork was inspected during implementation. It supports
MCP `2025-06-18`, stdio transport, and macro/manual tool registration. Swarmy is
not taking a direct NimCP dependency in this slice because the current product
surface only needs four narrow tools and already has tested CLI handlers for the
same writes. Keeping v1 thin avoids committing the package graph before the MCP
surface stabilizes.

The adapter intentionally mirrors MCP method names for:

- `initialize`
- `tools/list`
- `tools/call`

Tools:

- `swarmy_init`
- `swarmy_agent`
- `swarmy_stage`
- `swarmy_snapshot`

The write tools route through the same command handlers as the CLI so event
validation, idempotency, run scoping, and persistence behavior stay equivalent.

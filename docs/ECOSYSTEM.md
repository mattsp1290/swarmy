# Upstream ecosystem requests and fallbacks

Swarmy is built on young Nim ecosystem libraries. Where a library is missing
something Swarmy wants, we file a request with the owning project (see
[`../AGENTS.md`](../AGENTS.md#filing-nim-ecosystem-gaps) for routing) **and ship
a local fallback** so product work never blocks on an external project. This
document records those decisions and when to revisit them.

Principle: an upstream gap is **non-blocking**. Pick a fallback that keeps
Swarmy shippable, note the request, and only revisit when the upstream change
actually lands.

## Open gaps and fallbacks

### Jazzy: no first-class realtime (WebSocket/SSE) route helper

- **Gap:** Jazzy Framework's public routing API has no first-class
  WebSocket/SSE helper (its own `SUGGESTED_ISSUES.md` lists a real-time log
  viewer as future work).
- **Fallback (shipped):** the UI uses **REST polling against a run-scoped event
  cursor** — `GET /api/runs/:id/events?after=<seq>` — with a clean service seam
  for future push updates. Per-run event sequence numbers are contiguous and
  monotonic, so polling reconciles deterministically without missing or
  duplicating events.
- **Status:** non-blocking. Request belongs to the Jazzy project bucket.
- **Revisit when:** Jazzy ships a first-class realtime route helper and the
  dashboard's polling cadence becomes a real UX limit. Until then, polling is
  sufficient for the first milestone.

### NimCP: advertised MCP protocol version lags the spec Swarmy targets

- **Gap:** NimCP advertises MCP `2024-11-05` in its README and code
  (`MCP_PROTOCOL_VERSION`), while its `STREAMABLE.md` claims `2025-06-18`
  streamable-HTTP compliance — a mismatch to resolve upstream before depending
  on current-spec behavior.
- **Fallback (shipped):** Swarmy implements its MCP stdio surface **directly**
  (`src/swarmy_cli/mcp_stdio.nim`), advertising `2025-06-18` and exposing the
  `swarmy_init`/`swarmy_agent`/`swarmy_stage`/`swarmy_snapshot` tools, the
  `swarmy://guidance/bead-swarm` resource, and the `bead-swarm` prompt, rather
  than depending on NimCP's current protocol version.
- **Status:** non-blocking. Request belongs to the NimCP project bucket.
- **Revisit when:** NimCP confirms `2025-06-18` (or later) support in code and
  README consistently, at which point Swarmy can evaluate adopting it instead of
  the hand-rolled stdio layer.

## How to revisit

When upstream resolves a gap above:

1. Confirm the upstream change in a tagged release (not just a branch/claim).
2. Re-evaluate whether the local fallback still wins on simplicity/reliability.
3. If adopting upstream, do it behind the existing seam (the polling/event API or
   the MCP transport layer) so the swap is contained, and update this file plus
   `.agents/plans/swarmy-bead-swarm-observability/research.md`.

See the research notes
([`research.md`](../.agents/plans/swarmy-bead-swarm-observability/research.md))
for the full findings behind these decisions.

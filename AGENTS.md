# Swarmy for agents

Swarmy makes `/goal /bead-swarm` progress visible. Beads (`bd`) stays the
canonical issue tracker; Swarmy records run-local agent activity and stage
overlays so concurrent bead-swarm work can be observed without changing
canonical Beads status early. **Use `bd` for issue state — never `bn`.**

## When to record what

Record state through the **CLI** (`swarmy <command>`) or the equivalent **MCP
tools** (`swarmy mcp`). Both transports delegate to the same handlers and
produce equivalent event records, so use whichever your harness supports.

1. **Initialize the run before writing any state.** This writes a unique run ID
   and metadata under `./.swarmy/` (idempotent — safe to re-run).

   - CLI: `swarmy init --repo PATH`
   - MCP tool: `swarmy_init` with `{ "repo": "PATH" }`

2. **Register an agent before it writes bead progress.**

   - CLI: `swarmy agent --repo PATH --event-id EVENT --agent AGENT_ID --name NAME [--kind KIND]`
   - MCP tool: `swarmy_agent` with `{ "repo": "PATH", "event_id": "...", "agent_id": "...", "name": "..." }`

3. **Record bead stage transitions.** Writable stage names are exactly:
   `coding`, `validation`, `review`, `merge`, `blocked`, and `complete`.
   (`unknown` is reserved for reduced/legacy values and is not written
   directly.) Emit a stage as the agent enters it; emit `blocked` with a payload
   reason when work stalls.

   - CLI: `swarmy stage --repo PATH --event-id EVENT --bead BEAD_ID --stage coding --agent AGENT_ID`
   - MCP tool: `swarmy_stage` with `{ "repo": "PATH", "event_id": "...", "bead_id": "...", "stage": "review", "agent_id": "..." }`

   `--event-id` must be unique per event; re-sending the same id with the same
   content is idempotent (it does not advance the run cursor), so retries are
   safe.

4. **Fetch the current snapshot when another agent needs context.**

   - CLI: `swarmy snapshot --repo PATH --source SOURCE --snapshot-json JSON`
   - MCP tool: `swarmy_snapshot` with `{ "repo": "PATH" }` (read-only)

## Discovering this guidance over MCP

The `swarmy` binary serves this workflow over MCP so agents can discover it
without reading the repo:

- Resource: `swarmy://guidance/bead-swarm` (`resources/read`)
- Prompt: `bead-swarm` (`prompts/get`)

The canonical text lives in `src/swarmy_core/guidance.nim` (`BeadSwarmGuidance`)
and is exposed identically through both the resource and the prompt.

## If Swarmy is unavailable

Swarmy is an **observability companion**, not a gate. If `swarmy init`/`stage`
fail (binary missing, store unwritable), continue the bead-swarm work and rely
on `bd` as the source of truth — do not block progress on Swarmy. When Swarmy is
available again, re-run `swarmy init` (idempotent) and resume recording stages;
the timeline simply resumes from the next event. See
[`docs/RUNBOOK.md`](docs/RUNBOOK.md) for recovery from stale `.swarmy` metadata
or missing events.

## Filing Nim ecosystem gaps

When Swarmy needs something a Nim dependency does not yet provide (a Jazzy route
helper, an MCP protocol behavior, a missing library feature), file the gap as a
markdown request in the **owning project's** request folder under the
established convention:

```
~/.agents/projects/<owning-project>/requests/<short-name>.md
```

Routing rules:

- File the request against the project that actually owns the code — e.g. Jazzy
  framework gaps go to the `jazzy` bucket, MCP/NimCP gaps to the `nimcp` bucket.
- **Only create a new project bucket when the owning repo/project is genuinely
  unknown.** Prefer an existing bucket over inventing one.
- Project/bucket names used as examples in docs are **illustrative, not a
  guarantee that such a project exists** — verify the owning project before
  filing, and do not assume an example name maps to a real repo.

A filed request is non-blocking: keep shipping Swarmy on a local fallback (see
[`docs/ECOSYSTEM.md`](docs/ECOSYSTEM.md)) and revisit the request only when the
upstream change actually lands.

## Research context for implementers

Background research and the task-graph plan that shaped Swarmy live under
`.agents/plans/swarmy-bead-swarm-observability/`:

- [`research.md`](.agents/plans/swarmy-bead-swarm-observability/research.md) —
  web/local research notes and planning defaults.
- [`plan.md`](.agents/plans/swarmy-bead-swarm-observability/plan.md) — the
  implementation plan.
- [`full-bd-show-audit.md`](.agents/plans/swarmy-bead-swarm-observability/full-bd-show-audit.md)
  — per-bead acceptance audit.

Findings that directly shaped implementation choices (see `research.md` for the
full detail — not duplicated here):

- **Jazzy has no first-class WebSocket/SSE route helper**, so Swarmy v1 uses
  **REST polling with a run-scoped event-sequence cursor**
  (`GET /api/runs/:id/events?after=<seq>`) as the realtime fallback, with a clean
  seam for future push updates.
- **NimCP advertises MCP `2024-11-05`** while Swarmy targets the newer
  `2025-06-18` protocol, so Swarmy implements its MCP stdio surface directly
  (`src/swarmy_cli/mcp_stdio.nim`) rather than depending on NimCP's current
  protocol version.
- **SQLite via `tiny_sqlite`** is the store (embedded, no external service);
  events are append-only with per-run sequence numbers, run metadata uses
  full-replace semantics.
- **Local-first security defaults**: loopback binds need no token; binding
  outside loopback requires `--auth-token`/`SWARMY_AUTH_TOKEN`.

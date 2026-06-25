# Swarmy operations runbook

How to operate Swarmy in a production-like local deployment and recover from
common failures. Swarmy runs entirely locally against an embedded SQLite store;
there are no external services to provision.

## 1. Configure the MCP host

Expose Swarmy's MCP tools and `/bead-swarm` guidance to your agent by adding the
`swarmy mcp` stdio server to the host's MCP configuration. The exact file
depends on the host, but the shape is:

```json
{
  "mcpServers": {
    "swarmy": {
      "command": "/absolute/path/to/swarmy",
      "args": ["mcp"]
    }
  }
}
```

The server speaks MCP `2025-06-18` over stdio and advertises the tools
`swarmy_init`, `swarmy_agent`, `swarmy_stage`, `swarmy_snapshot`, the resource
`swarmy://guidance/bead-swarm`, and the prompt `bead-swarm`. Agents that cannot
use MCP can use the equivalent CLI commands (see [`../AGENTS.md`](../AGENTS.md));
both paths write the same event records.

## 2. Initialize a run

From the repository the swarm operates on:

```sh
swarmy init --repo .
```

This creates `./.swarmy/run.json` (run identity + metadata). The SQLite event
store (`swarmy.db`, plus `swarmy.db-wal`/`swarmy.db-shm` sidecars) is created
lazily on the first recorded event or when the server starts — not by `init`
itself. (`swarmy doctor` reports a `config_path`, but a `config.json` file is
not written today.) `init` is idempotent — re-running it reuses the existing run
rather than creating a new one. Use `--db PATH` to place the store outside the
repo (the path is canonicalized and symlinks are rejected).

## 3. Start the UI

Build the web bundle once (`npm run build --workspace apps/web`), then serve it:

```sh
swarmy serve --repo . --static-dir apps/web/dist
```

Defaults bind `127.0.0.1:8080`. Loopback binds require no token. To bind outside
loopback you must supply a token:

```sh
SWARMY_AUTH_TOKEN="$(openssl rand -base64 32)" swarmy serve --host 0.0.0.0
```

The dashboard opens directly on the run list; selecting a run shows its bead
stage board, a **Review health** tile, agents, a failures panel, and a polling
activity timeline. To pass the token to the browser, append
`#swarmy_token=YOUR_TOKEN` to the URL once — the client stores it and strips it
from the address bar.

The **Review health** tile surfaces, for the selected run: the current iteration,
the last review verdict, whether a `REQUEST_CHANGES` is outstanding (a verdict not
yet fixed-and-re-reviewed), and the degraded-review state when the iteration's
**review** ran in a degraded mode. The degraded-review label is derived from the
review-assurance signal (`review_assurance` ≠ `normal`), **not** from
`execution_mode` — a degraded *orchestration* mode such as `parent-degraded`
(the orchestrator wrote the change directly) is still a normal review and is not
labelled degraded, consistent with [`LOOPS.md`](LOOPS.md#degraded-review-states).
The tile is backed by the read-only HTTP endpoint
`GET /api/runs/:run_id/health`, which reuses the `swarmy summary` generator (see
§7) for the run-health manifest and adds per-iteration review verdicts and
signals (`review_assurance`, `review_mode`, `findings_fixed_re_reviewed`, and the
orchestration-level `execution_mode`/`degraded_reason`). See
[`LOOPS.md`](LOOPS.md#degraded-review-states) for the degraded-review vocabulary.

## 4. Interpret stages

Each bead shows a Swarmy **stage overlay** (distinct from its canonical `bd`
status). Stage names and their meaning:

| Stage        | Meaning                                          |
|--------------|--------------------------------------------------|
| `coding`     | An agent is implementing the bead.               |
| `validation` | Tests/build are running against the change.      |
| `review`     | The change is under review.                      |
| `merge`      | The change is being merged.                      |
| `blocked`    | Work is stalled; the event payload carries why.  |
| `complete`   | The bead's swarm work is finished.               |
| `unknown`    | A reduced/legacy value; not written directly.    |

The bead's `swarm_stage` is the latest stage event by sequence. The **Failures**
panel surfaces blocked stage events (with timestamp and source agent) plus any
recorded run errors; the **Activity** timeline lists recent events newest-first.

## 5. Diagnostics

Run the built-in diagnostic to inspect configuration and recent errors without
mutating the store:

```sh
swarmy doctor --repo .
```

It reports the canonical repo path, initialization status, run ID, database
path, whether the database file is present, and up to the 10 most recent error
rows. All output is passed through the secret redactor. Exit codes: `0` (even
for an uninitialized repo, which it reports), `1` on filesystem/database errors,
`2` on bad arguments. The server also emits structured, redacted logs to stderr
with a per-request `request_id` and the `run_id`; CLI stage writes log a
`stage transition` line.

## 6. Loop readiness (preflight)

Before starting a `/bead-swarm` or `/ralph` iteration, confirm the checkout is in
a clean, loop-ready state:

```sh
swarmy preflight --repo .
swarmy preflight --repo . --json | jq .
```

Unlike `doctor` (which reports swarmy's own run health from the SQLite store),
`preflight` inspects **loop readiness** with strictly read-only git and `bd`
calls — it never fetches, mutates refs, or writes Beads state. It reports eight
checks, each `PASS` / `WARN` / `FAIL` (the last folds Beads readiness and the
epic/task mix into one `beads` check):

| Check | Meaning |
|-------|---------|
| `working-tree` | `git status --porcelain` is empty (FAIL if dirty). |
| `branch` | On the expected base branch (default `main`, override with `--main`). |
| `sync` | Up to date with `origin/<main>` (FAIL if behind, WARN if ahead). |
| `origin` | `origin` remote is reachable. |
| `stale-branches` | No leftover `ralph/iteration-*`, `bead-swarm/iteration-*`, or `bead-swarm/recovery-*` branches (local or remote). |
| `lock-file` | No `.git/bead-swarm.lock` left from a prior run. |
| `reviews-excluded` | `reviews/` is git-ignored (swarmy keeps it in `.git/info/exclude`, not the tracked `.gitignore`). |
| `beads` | `bd ready` returns actionable work, and at least one item is concrete (not epic-only). |

The `beads` check is intentionally a **WARN, never a FAIL**: an empty ready queue
(or an epics-only queue) means there is nothing to do right now — possibly a
complete graph — not that the checkout is unready. So a clean checkout with no
ready beads still exits `0`. Scripts that gate on the exit code should therefore
treat `0` as "the checkout is loop-ready", not "there is work to do" — read the
`beads` check (or `swarmy summary`'s `recommended_next`) for the latter.

`--main BRANCH` overrides the expected base branch; otherwise a `.ralph` file's
`main_branch=BRANCH` line is honored when present (the format the loop tooling
writes). Exit codes match `doctor`: `0` when ready (warnings are allowed), `1`
when any check FAILs, `2` on bad arguments. All output is passed through the
secret redactor.

The epic/task split in the `beads` check uses the shared `classifyReady` helper
in `swarmy_core/bd_adapter` (also consumed by `swarmy summary`), so "only epics
ready" is surfaced consistently across both commands.

## 7. Recovery

### Recover run state with `swarmy summary`

To answer "where is this run and what's next" without reading every
`.agents/bead-swarm/history/iteration-*.json` file, generate a compact manifest:

```sh
swarmy summary --repo .              # human-readable manifest to stdout
swarmy summary --repo . --json | jq . # machine-readable
swarmy summary --repo . --write       # also write .agents/bead-swarm/latest.md + summary.json
```

It reconciles three sources — swarmy's SQLite store (run id, recent error count),
the iteration history dir, and live `bd` readiness — into one manifest:
cumulative completed beads, last iteration's branch/status/reviews, a pass/fail
view of the last iteration's `validation` entries, unresolved risks (review
blockers + partially-satisfied beads), open bead count (computed from `bd`, never
read from history), and the recommended next concrete (non-epic) beads. Open
count and recommended-next reuse the shared `classifyReady` helper from
`swarmy preflight`. `summary` is read-only apart from the `latest.md` /
`summary.json` audit artifacts it writes under `--write`; it never mutates the
store or history JSON, and tolerates missing or malformed history files (a bad
file is skipped, not fatal).

### Missing or out-of-order events

Events carry a per-run, contiguous, monotonic sequence number. If the UI looks
stale, the client polls `GET /api/runs/:id/events?after=<seq>` and reconciles by
sequence, so a refresh recovers missed events. If a bead shows no stage overlay,
no stage event was recorded for it yet — re-emit the stage with `swarmy stage`.
Re-sending an event with an existing `--event-id` and identical content is
idempotent and safe.

### Stale or corrupt `.swarmy` metadata

- **Wrong/stale `run.json`:** `swarmy doctor --repo .` shows the recorded run ID
  and db path. If they are wrong for this checkout, stop the server, remove the
  stale `.swarmy/run.json` (or the whole `./.swarmy/` directory to start a fresh
  run), and re-run `swarmy init --repo .`.
- **Unreadable/locked database:** ensure no `swarmy serve` process is holding the
  store, then re-run `swarmy doctor` to confirm it opens. The store uses WAL
  mode; the `swarmy.db-wal`/`swarmy.db-shm` sidecar files are normal and are
  recreated as needed.
- **Symlinked `.swarmy` or db path:** Swarmy refuses to operate on symlinked
  metadata/db paths for safety. Replace the symlink with a real file/directory
  and re-initialize.

Swarmy never blocks bead-swarm progress: if recovery is not immediate, continue
the work with `bd` as the source of truth and resume Swarmy recording afterward.

## 8. Browser-validation fallback

When Playwright or browser tooling is unavailable, the UI cannot be validated by
rendering it — but the dashboard's behavior can still be exercised through the
build and the HTTP API. Use this fallback checklist, and **record honestly** that
the UI was validated via build + HTTP, not via a browser; do not imply browser
coverage that did not run.

1. **Compile/bundle pass.** `nimble build` and `npm run build --workspace
   apps/web` (or `npm run build` for both) must succeed — this catches Svelte
   compile and Vite bundling regressions without a browser.
2. **API behavior.** Run `tests/smoke_serve.sh` (boots `swarmy serve`, probes the
   server) and/or `tests/smoke_e2e.sh` (full path: temp Beads repo → `swarmy
   init` → synthetic `coding`/`review` stage events → API). They assert the
   UI-facing endpoints — `/api/runs`, `/api/runs/:run_id`, and the
   `/api/runs/:run_id/events` polling cursor — return the expected JSON shape and
   event order.
3. **Client logic.** `npm run test --workspace apps/web` runs the `node --test`
   suite (e.g. `apps/web/src/api.test.ts`), which exercises the client's data
   transforms without a DOM.
4. **Record the gap.** In the iteration record, state that UI validation was
   build + HTTP only and that browser rendering was not exercised.

When Playwright *is* available, `npm run test:ui --workspace apps/web` (also run
in CI) is the authoritative browser check and supersedes this fallback.

## 9. Degraded-review states

The four named degraded-review states (`reviewers_unavailable`,
`local_fallback`, `findings_fixed_unreviewed`, `approved`) are defined
canonically by swarmy's published guidance (`swarmy bead-swarm`) and glossed,
with their mapping onto the `bead-swarm-history-v1` schema fields, in
[`LOOPS.md` → Degraded-review states](LOOPS.md#degraded-review-states). See also
[`LOOPS.md`](LOOPS.md) for how `/bead-swarm` and `/ralph` compare.

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
stage board, agents, a failures panel, and a polling activity timeline. To pass
the token to the browser, append `#swarmy_token=YOUR_TOKEN` to the URL once — the
client stores it and strips it from the address bar.

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

## 6. Recovery

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

# swarmy
Loops made visible

Swarmy is a Nim + Svelte monorepo that makes concurrent `/goal /bead-swarm` runs
visible: agents record run-local state through a CLI or MCP surface, and a Svelte
dashboard shows active beads, their coding/review stages, agents, failures, and a
polling activity timeline.

## Documentation

- [`AGENTS.md`](AGENTS.md) — how agents record bead-swarm state (CLI + MCP).
- [`docs/RUNBOOK.md`](docs/RUNBOOK.md) — operating Swarmy and recovery.
- [`docs/RELEASING.md`](docs/RELEASING.md) — CI gates and release packaging.
- [`docs/ECOSYSTEM.md`](docs/ECOSYSTEM.md) — upstream Nim ecosystem requests and fallbacks.
- [`docs/mcp-v1.md`](docs/mcp-v1.md) — MCP surface reference.

## Build and run locally

Prerequisites: Nim `>= 2.2.4` (with Nimble) and Node `>= 22` (with npm). The
backend uses an embedded SQLite store, so no external database is required.

Install Node workspaces once, then build each half (or both via the root script):

```sh
npm ci                                   # install web workspace deps
nimble build                             # build the ./swarmy backend binary
npm run build --workspace apps/web       # build the Svelte bundle to apps/web/dist
npm run build                            # convenience: nimble build + web build
```

Run the test suites:

```sh
nimble test                              # Nim backend unit/integration tests
npm run test --workspace apps/web        # frontend unit tests (node:test)
npm run test:ui --workspace apps/web     # Playwright UI smoke (desktop + mobile)
npm run test:smoke                       # end-to-end shell smoke (tests/smoke.sh)
```

Start the local server (after building the web bundle):

```sh
swarmy init --repo .                     # create ./.swarmy/run.json (store is created on first write)
swarmy serve --repo . --static-dir apps/web/dist
```

See [`docs/RUNBOOK.md`](docs/RUNBOOK.md) for the MCP host setup, stage
interpretation, diagnostics (`swarmy doctor`), and recovery.

## Serve

`swarmy serve` binds to `127.0.0.1:8080` by default and serves `apps/web/dist`.
Loopback binds do not require a token so local development stays one command.

Binding outside loopback, such as `--host 0.0.0.0`, requires a local token:

```sh
SWARMY_AUTH_TOKEN="$(openssl rand -base64 32)"
export SWARMY_AUTH_TOKEN
swarmy serve --host 0.0.0.0

# or
swarmy serve --host 0.0.0.0 --auth-token "$(openssl rand -base64 32)"
```

API clients send the token with `X-Swarmy-Token: $SWARMY_AUTH_TOKEN` or
`Authorization: Bearer $SWARMY_AUTH_TOKEN`. `/api/auth` reports whether auth is
required and which header is supported; it never returns the token. For browser
dashboard use, open `/#swarmy_token=$SWARMY_AUTH_TOKEN` once. The dashboard
stores the token in browser-local storage, removes it from the address bar, and
sends it as `X-Swarmy-Token` on later API requests. API request bodies are capped
at 1 MiB by default and can be adjusted with `--max-body-bytes`. Requests with a
larger declared `Content-Length` are rejected before JSON parsing, and any actual
body over the configured limit receives `413`.

## Logging and diagnostics

The server emits structured, single-line logs to **stderr** (stdout stays clean
for the JSON/CLI contract). Each API request is logged as `level=info msg="api
request"` with a per-request `request_id`, the HTTP `method`, the `path`, the
resolved `run_id`, and the response `status` (200, 400, or 404). CLI stage
writes emit a `msg="stage transition"` line carrying `run_id`, `bead_id`,
`stage`, `event_id`, and `seq`. Field values and messages are passed through the
shared redactor, which masks recognized secret shapes (`token=`, `bearer <…>`,
`authorization: bearer …`, `x-swarmy-token: …`, `password=`, and the matching
JSON keys) as `[REDACTED]`. Redaction is marker-based, so callers should still
avoid logging raw secret material that carries no recognized marker. Newlines and
control characters in values are escaped, so a value can never forge a second log
record.

`swarmy doctor [--repo PATH]` prints a diagnostic report: the canonical repo
path, initialization status, and (when initialized) the `run_id`, `db_path`,
`db_path_trusted`, `config_path`, `created_at`, whether the database file is
present, and up to the 10 most recent error rows. The database is opened
read-only so the diagnostic does not mutate it. The entire report is run through
the redactor described above. It exits `0` even for an uninitialized repo
(reporting that state), `1` on filesystem/database errors, and `2` on unexpected
arguments.

## Smoke tests

`npm run test:smoke` runs `tests/smoke.sh`, which builds the backend and web app
and exercises the running server. The end-to-end milestone check
(`tests/smoke_e2e.sh`) proves the user-facing path in one command: it initializes
a temp Beads repo, runs `swarmy init`, records synthetic `coding` and `review`
events through the real CLI, starts the API against that repo, and verifies the
UI-facing state endpoints (`/api/runs`, `/api/runs/:id`, and the
`/api/runs/:id/events` polling cursor) reflect the recorded run, bead stage, and
event order. Override ports with `SWARMY_SMOKE_PORT` / `SWARMY_SMOKE_E2E_PORT`.

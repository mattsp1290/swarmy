# Full bd show Audit
Generated: 2026-06-21

## swarmy-djn
```text
○ swarmy-djn · Implement .swarmy run initialization   [● P0 · OPEN]
Owner: Matt Spurlin · Type: feature
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Implement swarmy init for repo-local run metadata. Acceptance: swarmy init creates idempotent ./.swarmy/ metadata with run ID, canonical repo path, created_at, schema version, and database/config pointers; unsafe symlinked paths are rejected or resolved predictably. Files/seams: CLI init command, metadata model, filesystem helpers, tests. Constraints: generated ID uniquely identifies simultaneous swarm runs.

LABELS: data

PARENT
  ↑ ○ swarmy-4b2: (EPIC) Persistent Swarm State Model ● P1

DEPENDS ON
  → ○ swarmy-ami: Establish thin binary and internal package boundaries ● P1

BLOCKS
  ← ○ swarmy-0g2: Create SQLite schema and event store ● P1


```

## swarmy-yx5
```text
○ swarmy-yx5 · Scaffold Nim/Svelte monorepo and build targets   [● P0 · OPEN]
Owner: Matt Spurlin · Type: task
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Create the Nim backend and Svelte frontend monorepo skeleton. Acceptance: nimble build, the Svelte app build, and a root build command work from a fresh checkout. Files/seams: root layout, .nimble, src/, apps/web/, package manifests, root scripts. Constraints: use Nim outside frontend and Svelte for frontend.

LABELS: setup

PARENT
  ↑ ○ swarmy-cs5: (EPIC) Foundation and Monorepo Shape ● P1

BLOCKS
  ← ○ swarmy-1zi: Build dashboard shell and navigation ● P1
  ← ○ swarmy-6jm: Document local build and run workflow ● P2
  ← ○ swarmy-ami: Establish thin binary and internal package boundaries ● P1
  ← ○ swarmy-wow: Add smoke test harness skeleton ● P1
  ← ○ swarmy-zvh: Scaffold Jazzy server and static app hosting ● P1


```

## swarmy-e24
```text
○ swarmy-e24 · Add full end-to-end first-milestone smoke test   [● P1 · OPEN]
Owner: Matt Spurlin · Type: task
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Prove the user-facing first milestone end to end. Acceptance: one smoke command initializes a temp Beads repo, runs swarmy init, records synthetic coding and review events through CLI or MCP, starts the API, and verifies the UI-facing state endpoint. Files/seams: smoke test runner, temp Beads fixture, backend process harness. Constraints: use real CLI or MCP path.

LABELS: verify

PARENT
  ↑ ○ swarmy-78o: (EPIC) Verification Operations and Packaging ● P1

DEPENDS ON
  → ○ swarmy-9kh: Add focused backend unit and integration tests ● P1
  → ○ swarmy-gyl: Add event cursor endpoint for polling ● P2

BLOCKS
  ← ○ swarmy-1ek: Add CI and release packaging ● P2


```

## swarmy-n1s
```text
○ swarmy-n1s · Add frontend build and UI smoke tests   [● P1 · OPEN]
Owner: Matt Spurlin · Type: task
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Cover frontend build and dashboard rendering. Acceptance: Svelte build and one browser smoke test prove the dashboard renders active bead coding/review state from fixture API data and handles local-token auth errors. Files/seams: frontend test config, fixture API, Playwright or equivalent. Constraints: verify desktop and mobile framing.

LABELS: verify

PARENT
  ↑ ○ swarmy-78o: (EPIC) Verification Operations and Packaging ● P1

DEPENDS ON
  → ○ swarmy-7lo: Show bead stage board for coding and review ● P1
  → ○ swarmy-9xh: Handle local token auth in the frontend client ● P2

BLOCKS
  ← ○ swarmy-1ek: Add CI and release packaging ● P2


```

## swarmy-78o
```text
○ swarmy-78o [EPIC] · Verification Operations and Packaging   [● P1 · OPEN]
Owner: Matt Spurlin · Type: epic
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Add production-oriented quality gates, packaging, diagnostics, and runbooks. Acceptance: tests cover backend/frontend/e2e, CI runs them, and users can install/run/recover Swarmy. Files/seams: tests, CI, scripts, diagnostics, docs. Constraints: verification must match actual Nim/Svelte stack.

LABELS: verify

CHILDREN
  ↳ ○ swarmy-1ek: Add CI and release packaging ● P2
  ↳ ○ swarmy-3mk: Write production runbook and recovery guide ● P2
  ↳ ○ swarmy-513: Add production logging and diagnostics ● P2
  ↳ ○ swarmy-9kh: Add focused backend unit and integration tests ● P1
  ↳ ○ swarmy-e24: Add full end-to-end first-milestone smoke test ● P1
  ↳ ○ swarmy-n1s: Add frontend build and UI smoke tests ● P1
  ◐ 0/6 complete (0%)


```

## swarmy-9kh
```text
○ swarmy-9kh · Add focused backend unit and integration tests   [● P1 · OPEN]
Owner: Matt Spurlin · Type: task
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Cover backend behavior with Nim tests. Acceptance: tests cover event writes, reducers, bd snapshot parsing including edge cases, merged read models, API serializers, concurrent writes, and MCP/CLI parity. Files/seams: tests/, fixtures, Nimble test config. Constraints: run under nimble test.

LABELS: verify

PARENT
  ↑ ○ swarmy-78o: (EPIC) Verification Operations and Packaging ● P1

DEPENDS ON
  → ○ swarmy-1j8: Prove concurrent run isolation and writer safety ● P1
  → ○ swarmy-s36: Expose bead, agent, and stage detail endpoints ● P1
  → ○ swarmy-vvw: Keep CLI and MCP behavior in parity ● P2

BLOCKS
  ← ○ swarmy-e24: Add full end-to-end first-milestone smoke test ● P1


```

## swarmy-7lo
```text
○ swarmy-7lo · Show bead stage board for coding and review   [● P1 · OPEN]
Owner: Matt Spurlin · Type: feature
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Visualize current bead stages. Acceptance: selected run detail shows bd-discovered beads grouped or labeled by coding, validation, review, merge, blocked, and complete with assigned agent where known. Files/seams: bead board/table components, stage badges, stores. Constraints: coding and review stages must be first-class.

LABELS: ui

PARENT
  ↑ ○ swarmy-4pg: (EPIC) Svelte Multi-Swarm Dashboard ● P1

DEPENDS ON
  → ○ swarmy-1zi: Build dashboard shell and navigation ● P1
  → ○ swarmy-s36: Expose bead, agent, and stage detail endpoints ● P1

BLOCKS
  ← ○ swarmy-n1s: Add frontend build and UI smoke tests ● P1


```

## swarmy-2cz
```text
○ swarmy-2cz · Display concurrent swarm run overview   [● P1 · OPEN]
Owner: Matt Spurlin · Type: feature
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Show multiple active swarm runs. Acceptance: users can distinguish simultaneous runs by repo, run ID, age, status, active bead count, and last activity. Files/seams: run list components, stores, API client tests. Constraints: preserve selection across refresh.

LABELS: ui

PARENT
  ↑ ○ swarmy-4pg: (EPIC) Svelte Multi-Swarm Dashboard ● P1

DEPENDS ON
  → ○ swarmy-1zi: Build dashboard shell and navigation ● P1
  → ○ swarmy-4nu: Expose run and swarm list endpoints ● P1


```

## swarmy-1zi
```text
○ swarmy-1zi · Build dashboard shell and navigation   [● P1 · OPEN]
Owner: Matt Spurlin · Type: task
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Create the Svelte dashboard shell. Acceptance: app renders run list, selected-run detail area, loading, empty, and error states. Files/seams: apps/web/src/, routes/components, API client. Constraints: application UI, not marketing layout.

LABELS: ui

PARENT
  ↑ ○ swarmy-4pg: (EPIC) Svelte Multi-Swarm Dashboard ● P1

DEPENDS ON
  → ○ swarmy-yx5: Scaffold Nim/Svelte monorepo and build targets ● P0

BLOCKS
  ← ○ swarmy-2cz: Display concurrent swarm run overview ● P1
  ← ○ swarmy-7lo: Show bead stage board for coding and review ● P1
  ← ○ swarmy-9xh: Handle local token auth in the frontend client ● P2


```

## swarmy-4pg
```text
○ swarmy-4pg [EPIC] · Svelte Multi-Swarm Dashboard   [● P1 · OPEN]
Owner: Matt Spurlin · Type: epic
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Build the browser dashboard for concurrent bead-swarm visibility. Acceptance: users can select runs, see beads by stage, inspect agent activity, and watch polling updates without layout issues. Files/seams: Svelte app, API client, stores, components, tests. Constraints: no landing page; first screen is the dashboard.

LABELS: ui

CHILDREN
  ↳ ○ swarmy-1zi: Build dashboard shell and navigation ● P1
  ↳ ○ swarmy-2cz: Display concurrent swarm run overview ● P1
  ↳ ○ swarmy-5lt: Add event timeline and failure visibility ● P2
  ↳ ○ swarmy-7lo: Show bead stage board for coding and review ● P1
  ↳ ○ swarmy-9xh: Handle local token auth in the frontend client ● P2
  ↳ ○ swarmy-rid: Implement polling refresh without layout shifts ● P2
  ◐ 0/6 complete (0%)


```

## swarmy-el7
```text
○ swarmy-el7 · Harden repo/db path and MCP trust boundaries   [● P1 · OPEN]
Owner: Matt Spurlin · Type: task
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Harden Swarmy inputs and diagnostics. Acceptance: --repo and --db inputs are canonicalized, symlinked .swarmy metadata is handled safely, diagnostics redact secrets, MCP tool descriptions state trust boundaries, and invalid stage/payload inputs return typed errors. Files/seams: config/path helpers, diagnostics, MCP descriptions, validation tests. Constraints: production safety is required.

LABELS: ops

PARENT
  ↑ ○ swarmy-t4r: (EPIC) Jazzy Backend API ● P1

DEPENDS ON
  → ○ swarmy-3p0: Record idempotent agent and stage events ● P1
  → ○ swarmy-55y: Add local auth and request validation defaults ● P1

BLOCKS
  ← ○ swarmy-513: Add production logging and diagnostics ● P2


```

## swarmy-55y
```text
○ swarmy-55y · Add local auth and request validation defaults   [● P1 · OPEN]
Owner: Matt Spurlin · Type: task
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Add production-safe local auth and validation. Acceptance: production mode requires a local token or Jazzy auth guard, defines how the token is generated or discovered for browser use, validates JSON payloads, enforces payload-size limits, and rejects unsafe bind/config combinations. Files/seams: middleware, config, validation helpers, docs/tests. Constraints: local development remains ergonomic.

LABELS: api

PARENT
  ↑ ○ swarmy-t4r: (EPIC) Jazzy Backend API ● P1

DEPENDS ON
  → ○ swarmy-zvh: Scaffold Jazzy server and static app hosting ● P1

BLOCKS
  ← ○ swarmy-9xh: Handle local token auth in the frontend client ● P2
  ← ○ swarmy-el7: Harden repo/db path and MCP trust boundaries ● P1


```

## swarmy-s36
```text
○ swarmy-s36 · Expose bead, agent, and stage detail endpoints   [● P1 · OPEN]
Owner: Matt Spurlin · Type: feature
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Add selected-run detail endpoints. Acceptance: API returns current bead assignments, agent identities, coding/review stage, canonical Beads status, last event time, and error/blocker details, including bd-only beads. Files/seams: controllers/routes, reducer queries, JSON serializers, tests. Constraints: status from bd remains canonical.

LABELS: api

PARENT
  ↑ ○ swarmy-t4r: (EPIC) Jazzy Backend API ● P1

DEPENDS ON
  → ○ swarmy-4nu: Expose run and swarm list endpoints ● P1
  → ○ swarmy-iph: Build merged Beads plus Swarmy read model ● P1

BLOCKS
  ← ○ swarmy-7lo: Show bead stage board for coding and review ● P1
  ← ○ swarmy-9kh: Add focused backend unit and integration tests ● P1
  ← ○ swarmy-gyl: Add event cursor endpoint for polling ● P2


```

## swarmy-4nu
```text
○ swarmy-4nu · Expose run and swarm list endpoints   [● P1 · OPEN]
Owner: Matt Spurlin · Type: feature
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Add API endpoints for known swarm runs. Acceptance: API returns active/recent runs with run IDs, repo paths, status, timestamps, aggregate counts, and no cross-run data leakage. Files/seams: Jazzy controllers/routes, read models, JSON serializers, tests. Constraints: use merged read model.

LABELS: api

PARENT
  ↑ ○ swarmy-t4r: (EPIC) Jazzy Backend API ● P1

DEPENDS ON
  → ○ swarmy-iph: Build merged Beads plus Swarmy read model ● P1
  → ○ swarmy-zvh: Scaffold Jazzy server and static app hosting ● P1

BLOCKS
  ← ○ swarmy-2cz: Display concurrent swarm run overview ● P1
  ← ○ swarmy-s36: Expose bead, agent, and stage detail endpoints ● P1


```

## swarmy-zvh
```text
○ swarmy-zvh · Scaffold Jazzy server and static app hosting   [● P1 · OPEN]
Owner: Matt Spurlin · Type: task
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Add the backend server skeleton. Acceptance: swarmy serve starts a Jazzy server on a safe local bind address and can serve built Svelte assets. Files/seams: server module, route registration, static file config. Constraints: safe local bind by default.

LABELS: api

PARENT
  ↑ ○ swarmy-t4r: (EPIC) Jazzy Backend API ● P1

DEPENDS ON
  → ○ swarmy-yx5: Scaffold Nim/Svelte monorepo and build targets ● P0

BLOCKS
  ← ○ swarmy-4nu: Expose run and swarm list endpoints ● P1
  ← ○ swarmy-55y: Add local auth and request validation defaults ● P1


```

## swarmy-t4r
```text
○ swarmy-t4r [EPIC] · Jazzy Backend API   [● P1 · OPEN]
Owner: Matt Spurlin · Type: epic
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Serve Swarmy state through a Jazzy API and local static app host. Acceptance: routes expose run lists, bead details, event cursors, and production-safe auth defaults. Files/seams: Jazzy server, routes, controllers, serializers, middleware. Constraints: start with REST polling, not realtime push.

LABELS: api

CHILDREN
  ↳ ○ swarmy-4nu: Expose run and swarm list endpoints ● P1
  ↳ ○ swarmy-55y: Add local auth and request validation defaults ● P1
  ↳ ○ swarmy-el7: Harden repo/db path and MCP trust boundaries ● P1
  ↳ ○ swarmy-gyl: Add event cursor endpoint for polling ● P2
  ↳ ○ swarmy-s36: Expose bead, agent, and stage detail endpoints ● P1
  ↳ ○ swarmy-zvh: Scaffold Jazzy server and static app hosting ● P1
  ◐ 0/6 complete (0%)


```

## swarmy-bde
```text
○ swarmy-bde · Add CLI equivalent for /bead-swarm instructions   [● P1 · OPEN]
Owner: Matt Spurlin · Type: feature
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Expose bead-swarm workflow guidance through the CLI. Acceptance: swarmy bead-swarm or swarmy instructions bead-swarm prints the same guidance exposed through MCP, including swarmy init and stage event conventions. Files/seams: CLI command, shared instruction template, tests. Constraints: keep MCP and CLI text in one source.

LABELS: agent

PARENT
  ↑ ○ swarmy-yyx: (EPIC) Agent-Facing CLI and MCP Surface ● P1

DEPENDS ON
  → ○ swarmy-otx: Serve /bead-swarm MCP resource or prompt ● P1

BLOCKS
  ← ○ swarmy-36i: Integrate /bead-swarm workflow guidance ● P2
  ← ○ swarmy-vvw: Keep CLI and MCP behavior in parity ● P2


```

## swarmy-otx
```text
○ swarmy-otx · Serve /bead-swarm MCP resource or prompt   [● P1 · OPEN]
Owner: Matt Spurlin · Type: feature
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Expose bead-swarm workflow guidance through MCP. Acceptance: the swarmy binary exposes a /bead-swarm resource or prompt instructing agents to run swarmy init and record coding/review progress. Files/seams: MCP resources/prompts, skill text template, tests. Constraints: use the same guidance source as the CLI instruction command.

LABELS: agent

PARENT
  ↑ ○ swarmy-yyx: (EPIC) Agent-Facing CLI and MCP Surface ● P1

DEPENDS ON
  → ○ swarmy-l2z: Serve MCP write tools for swarm events ● P1

BLOCKS
  ← ○ swarmy-bde: Add CLI equivalent for /bead-swarm instructions ● P1


```

## swarmy-l2z
```text
○ swarmy-l2z · Serve MCP write tools for swarm events   [● P1 · OPEN]
Owner: Matt Spurlin · Type: feature
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Add MCP stdio tools for Swarmy writes and reads. Acceptance: an MCP client can list and call tools to initialize a run, record an agent event, set bead stage, and fetch a snapshot; v1 documents whether it uses NimCP or a thin local JSON-RPC adapter and what protocol version it advertises. Files/seams: MCP server module, tool schemas, protocol decision note, handler tests or replay fixtures. Constraints: keep tool trust boundaries explicit.

LABELS: agent

PARENT
  ↑ ○ swarmy-yyx: (EPIC) Agent-Facing CLI and MCP Surface ● P1

DEPENDS ON
  → ○ swarmy-3p0: Record idempotent agent and stage events ● P1

BLOCKS
  ← ○ swarmy-otx: Serve /bead-swarm MCP resource or prompt ● P1
  ← ○ swarmy-vvw: Keep CLI and MCP behavior in parity ● P2


```

## swarmy-2a5
```text
○ swarmy-2a5 · Implement advisor-style CLI event commands   [● P1 · OPEN]
Owner: Matt Spurlin · Type: feature
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Add CLI commands for agent writes. Acceptance: swarmy event, swarmy stage, swarmy agent, and swarmy snapshot write the same state as the internal event API with stable exit codes. Files/seams: CLI parser, command handlers, stdout/stderr contracts, command tests. Constraints: match advisor-style CLI discipline where practical.

LABELS: agent

PARENT
  ↑ ○ swarmy-yyx: (EPIC) Agent-Facing CLI and MCP Surface ● P1

DEPENDS ON
  → ○ swarmy-3p0: Record idempotent agent and stage events ● P1

BLOCKS
  ← ○ swarmy-vvw: Keep CLI and MCP behavior in parity ● P2


```

## swarmy-yyx
```text
○ swarmy-yyx [EPIC] · Agent-Facing CLI and MCP Surface   [● P1 · OPEN]
Owner: Matt Spurlin · Type: epic
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Give agents CLI and MCP surfaces to record Swarmy state and discover bead-swarm instructions. Acceptance: CLI and MCP produce equivalent events and expose /bead-swarm guidance. Files/seams: CLI parser, MCP server, shared handlers, templates, tests. Constraints: no bn usage.

LABELS: agent

CHILDREN
  ↳ ○ swarmy-2a5: Implement advisor-style CLI event commands ● P1
  ↳ ○ swarmy-36i: Integrate /bead-swarm workflow guidance ● P2
  ↳ ○ swarmy-bde: Add CLI equivalent for /bead-swarm instructions ● P1
  ↳ ○ swarmy-l2z: Serve MCP write tools for swarm events ● P1
  ↳ ○ swarmy-otx: Serve /bead-swarm MCP resource or prompt ● P1
  ↳ ○ swarmy-vvw: Keep CLI and MCP behavior in parity ● P2
  ◐ 0/6 complete (0%)


```

## swarmy-5ph
```text
○ swarmy-5ph · Prove persistence across process restarts   [● P1 · OPEN]
Owner: Matt Spurlin · Type: task
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Add restart persistence coverage for Swarmy state. Acceptance: a test writes a run/event, restarts the Swarmy process, and reads back the same run and bead stage from the same database. Files/seams: integration tests, temp repo/test process harness. Constraints: use a real process restart, not only an in-process handle reopen.

LABELS: verify

PARENT
  ↑ ○ swarmy-4b2: (EPIC) Persistent Swarm State Model ● P1

DEPENDS ON
  → ○ swarmy-iph: Build merged Beads plus Swarmy read model ● P1


```

## swarmy-iph
```text
○ swarmy-iph · Build merged Beads plus Swarmy read model   [● P1 · OPEN]
Owner: Matt Spurlin · Type: feature
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Merge canonical Beads snapshots with Swarmy agent/stage events. Acceptance: queries return beads discovered from bd even without Swarmy events, overlay Swarmy events when present, and preserve canonical Beads status. Files/seams: reducer/read model, bd snapshot merger, fixtures. Constraints: Swarmy is not the source of truth for Beads status.

LABELS: data

PARENT
  ↑ ○ swarmy-4b2: (EPIC) Persistent Swarm State Model ● P1

DEPENDS ON
  → ○ swarmy-3p0: Record idempotent agent and stage events ● P1
  → ○ swarmy-3z4: Reconstruct bead snapshots from bd ● P1

BLOCKS
  ← ○ swarmy-4nu: Expose run and swarm list endpoints ● P1
  ← ○ swarmy-5ph: Prove persistence across process restarts ● P1
  ← ○ swarmy-s36: Expose bead, agent, and stage detail endpoints ● P1


```

## swarmy-3z4
```text
○ swarmy-3z4 · Reconstruct bead snapshots from bd   [● P1 · OPEN]
Owner: Matt Spurlin · Type: feature
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Read canonical Beads state without mutating it. Acceptance: Swarmy reads bd ready/list/show snapshots and handles missing bd, non-Beads repos, malformed output, deleted or renamed beads, stale snapshots, and command timeouts with typed errors. Files/seams: bd adapter, parsers, snapshot service, fixtures. Constraints: all bd usage is read-only.

LABELS: data

PARENT
  ↑ ○ swarmy-4b2: (EPIC) Persistent Swarm State Model ● P1

DEPENDS ON
  → ○ swarmy-0g2: Create SQLite schema and event store ● P1

BLOCKS
  ← ○ swarmy-iph: Build merged Beads plus Swarmy read model ● P1


```

## swarmy-1j8
```text
○ swarmy-1j8 · Prove concurrent run isolation and writer safety   [● P1 · OPEN]
Owner: Matt Spurlin · Type: task
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Validate simultaneous Swarmy writers and runs. Acceptance: a test with two simultaneous run IDs and at least two writer processes records events without cross-run bleed, duplicate cursor assignment, or SQLite lock failures. Files/seams: persistence transactions, event writer, integration tests. Constraints: run-scoped cursors are required.

LABELS: data

PARENT
  ↑ ○ swarmy-4b2: (EPIC) Persistent Swarm State Model ● P1

DEPENDS ON
  → ○ swarmy-3p0: Record idempotent agent and stage events ● P1

BLOCKS
  ← ○ swarmy-9kh: Add focused backend unit and integration tests ● P1


```

## swarmy-3p0
```text
○ swarmy-3p0 · Record idempotent agent and stage events   [● P1 · OPEN]
Owner: Matt Spurlin · Type: feature
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Add append-only event writes and stage reduction. Acceptance: duplicate event IDs do not double-count state, allowed stage names are validated, unknown legacy stages reduce to unknown, and latest bead stage is deterministic. Files/seams: event model, stage enum, write API, reducer/read model tests. Constraints: stage enum includes coding, validation, review, merge, blocked, complete, unknown.

LABELS: data

PARENT
  ↑ ○ swarmy-4b2: (EPIC) Persistent Swarm State Model ● P1

DEPENDS ON
  → ○ swarmy-0g2: Create SQLite schema and event store ● P1

BLOCKS
  ← ○ swarmy-1j8: Prove concurrent run isolation and writer safety ● P1
  ← ○ swarmy-2a5: Implement advisor-style CLI event commands ● P1
  ← ○ swarmy-el7: Harden repo/db path and MCP trust boundaries ● P1
  ← ○ swarmy-iph: Build merged Beads plus Swarmy read model ● P1
  ← ○ swarmy-l2z: Serve MCP write tools for swarm events ● P1


```

## swarmy-0g2
```text
○ swarmy-0g2 · Create SQLite schema and event store   [● P1 · OPEN]
Owner: Matt Spurlin · Type: feature
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Add durable tables and setup for Swarmy state. Acceptance: schema creates runs, agents, beads, stages, events, snapshots, and errors with RFC3339 timestamps, WAL/busy-timeout settings, unique event IDs, and run-scoped sequence cursors. Files/seams: persistence module, schema builder or SQL, repository tests. Constraints: SQLite is the default store.

LABELS: data

PARENT
  ↑ ○ swarmy-4b2: (EPIC) Persistent Swarm State Model ● P1

DEPENDS ON
  → ○ swarmy-djn: Implement .swarmy run initialization ● P0

BLOCKS
  ← ○ swarmy-3p0: Record idempotent agent and stage events ● P1
  ← ○ swarmy-3z4: Reconstruct bead snapshots from bd ● P1


```

## swarmy-4b2
```text
○ swarmy-4b2 [EPIC] · Persistent Swarm State Model   [● P1 · OPEN]
Owner: Matt Spurlin · Type: epic
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Build durable Swarmy run identity, event storage, Beads snapshots, and merged read models. Acceptance: runs survive restart and concurrent event writers remain isolated by run. Files/seams: .swarmy metadata, SQLite persistence, bd adapter, reducers. Constraints: Beads remains canonical for bead status where reliable.

LABELS: data

CHILDREN
  ↳ ○ swarmy-0g2: Create SQLite schema and event store ● P1
  ↳ ○ swarmy-1j8: Prove concurrent run isolation and writer safety ● P1
  ↳ ○ swarmy-3p0: Record idempotent agent and stage events ● P1
  ↳ ○ swarmy-3z4: Reconstruct bead snapshots from bd ● P1
  ↳ ○ swarmy-5ph: Prove persistence across process restarts ● P1
  ↳ ○ swarmy-djn: Implement .swarmy run initialization ● P0
  ↳ ○ swarmy-iph: Build merged Beads plus Swarmy read model ● P1
  ◐ 0/7 complete (0%)


```

## swarmy-wow
```text
○ swarmy-wow · Add smoke test harness skeleton   [● P1 · OPEN]
Owner: Matt Spurlin · Type: task
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Add isolated smoke-test scaffolding before product behavior exists. Acceptance: test utilities create a temp repo, temp Swarmy database path, and placeholder backend/frontend smoke commands. Files/seams: tests/, test fixtures, root test script, temp repo helpers. Constraints: do not require init, API, or event behavior yet.

LABELS: verify

PARENT
  ↑ ○ swarmy-cs5: (EPIC) Foundation and Monorepo Shape ● P1

DEPENDS ON
  → ○ swarmy-yx5: Scaffold Nim/Svelte monorepo and build targets ● P0


```

## swarmy-ami
```text
○ swarmy-ami · Establish thin binary and internal package boundaries   [● P1 · OPEN]
Owner: Matt Spurlin · Type: task
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Shape the Swarmy binary like advisor with a thin entrypoint and testable internals. Acceptance: swarmy --version, swarmy serve, and swarmy mcp dispatch through internal modules. Files/seams: src/swarmy.nim, src/swarmy_cli/, src/swarmy_core/, tests. Constraints: keep binary wrapper minimal.

LABELS: core

PARENT
  ↑ ○ swarmy-cs5: (EPIC) Foundation and Monorepo Shape ● P1

DEPENDS ON
  → ○ swarmy-yx5: Scaffold Nim/Svelte monorepo and build targets ● P0

BLOCKS
  ← ○ swarmy-43p: Integrate research notes into contributor context ● P3
  ← ○ swarmy-djn: Implement .swarmy run initialization ● P0


```

## swarmy-cs5
```text
○ swarmy-cs5 [EPIC] · Foundation and Monorepo Shape   [● P1 · OPEN]
Owner: Matt Spurlin · Type: epic
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Establish the Swarmy monorepo baseline. Acceptance: the repo has runnable backend, frontend, smoke-harness, and contributor docs work organized under one epic. Files/seams: root layout, build scripts, docs, tests. Constraints: greenfield repo; do not assume existing source.

LABELS: setup

CHILDREN
  ↳ ○ swarmy-6jm: Document local build and run workflow ● P2
  ↳ ○ swarmy-ami: Establish thin binary and internal package boundaries ● P1
  ↳ ○ swarmy-wow: Add smoke test harness skeleton ● P1
  ↳ ○ swarmy-yx5: Scaffold Nim/Svelte monorepo and build targets ● P0
  ◐ 0/4 complete (0%)


```

## swarmy-z9e
```text
○ swarmy-z9e · Add agent-facing project instructions   [● P2 · OPEN]
Owner: Matt Spurlin · Type: chore
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Add durable instructions for future agents. Acceptance: AGENTS.md tells agents to use bd, avoid bn, follow Swarmy event conventions, and route ecosystem requests to the owning project folder. Files/seams: AGENTS.md, possibly CLAUDE.md. Constraints: this project is Beads-only.

LABELS: docs

PARENT
  ↑ ○ swarmy-8t5: (EPIC) Agent Knowledge and Ecosystem Follow-up ● P3

DEPENDS ON
  → ○ swarmy-36i: Integrate /bead-swarm workflow guidance ● P2
  → ○ swarmy-yuf: Document ecosystem request routing policy ● P3


```

## swarmy-3mk
```text
○ swarmy-3mk · Write production runbook and recovery guide   [● P2 · OPEN]
Owner: Matt Spurlin · Type: chore
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Document production-like operation and recovery. Acceptance: docs explain configuring MCP host, running swarmy init, starting the UI, interpreting stages, and recovering from missing events or stale .swarmy metadata. Files/seams: README, docs/runbook, AGENTS guidance. Constraints: include both CLI and MCP paths.

LABELS: docs

PARENT
  ↑ ○ swarmy-78o: (EPIC) Verification Operations and Packaging ● P1

DEPENDS ON
  → ○ swarmy-1ek: Add CI and release packaging ● P2
  → ○ swarmy-513: Add production logging and diagnostics ● P2


```

## swarmy-513
```text
○ swarmy-513 · Add production logging and diagnostics   [● P2 · OPEN]
Owner: Matt Spurlin · Type: task
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Add operational logging and swarmy doctor. Acceptance: server logs include run ID/request ID/stage transitions without leaking secrets, and a diagnostic CLI reports config, database path, and recent errors. Files/seams: logging module, swarmy doctor, docs/tests. Constraints: redact tokens and secrets.

LABELS: ops

PARENT
  ↑ ○ swarmy-78o: (EPIC) Verification Operations and Packaging ● P1

DEPENDS ON
  → ○ swarmy-el7: Harden repo/db path and MCP trust boundaries ● P1

BLOCKS
  ← ○ swarmy-3mk: Write production runbook and recovery guide ● P2


```

## swarmy-1ek
```text
○ swarmy-1ek · Add CI and release packaging   [● P2 · OPEN]
Owner: Matt Spurlin · Type: chore
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Add automated quality gates and packaging recipe. Acceptance: CI runs backend tests, frontend build/tests, and produces a local binary/package artifact recipe. Files/seams: .github/workflows/, packaging scripts, release notes. Constraints: do not require external services for core CI.

LABELS: ops

PARENT
  ↑ ○ swarmy-78o: (EPIC) Verification Operations and Packaging ● P1

DEPENDS ON
  → ○ swarmy-e24: Add full end-to-end first-milestone smoke test ● P1
  → ○ swarmy-n1s: Add frontend build and UI smoke tests ● P1

BLOCKS
  ← ○ swarmy-3mk: Write production runbook and recovery guide ● P2


```

## swarmy-rid
```text
○ swarmy-rid · Implement polling refresh without layout shifts   [● P2 · OPEN]
Owner: Matt Spurlin · Type: task
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Add refresh behavior for active runs. Acceptance: dashboard refreshes active runs from the cursor endpoint, preserves selection, and does not overlap or resize core controls on mobile or desktop. Files/seams: stores, timers, responsive CSS, Playwright/screenshot checks. Constraints: no viewport-scaled fonts; stable layout dimensions.

LABELS: ui

PARENT
  ↑ ○ swarmy-4pg: (EPIC) Svelte Multi-Swarm Dashboard ● P1

DEPENDS ON
  → ○ swarmy-5lt: Add event timeline and failure visibility ● P2


```

## swarmy-5lt
```text
○ swarmy-5lt · Add event timeline and failure visibility   [● P2 · OPEN]
Owner: Matt Spurlin · Type: feature
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Show recent activity and failures for a selected run. Acceptance: selected run detail shows recent events and clearly surfaces blocked/failed events with timestamps and source agent. Files/seams: timeline components, error states, event API client. Constraints: use run-scoped cursor endpoint.

LABELS: ui

PARENT
  ↑ ○ swarmy-4pg: (EPIC) Svelte Multi-Swarm Dashboard ● P1

DEPENDS ON
  → ○ swarmy-9xh: Handle local token auth in the frontend client ● P2
  → ○ swarmy-gyl: Add event cursor endpoint for polling ● P2

BLOCKS
  ← ○ swarmy-rid: Implement polling refresh without layout shifts ● P2


```

## swarmy-9xh
```text
○ swarmy-9xh · Handle local token auth in the frontend client   [● P2 · OPEN]
Owner: Matt Spurlin · Type: task
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Wire frontend auth behavior. Acceptance: Svelte API client can discover or receive the configured local token through the documented local-hosting path, send it on requests, show auth failures clearly, and keep safe empty/error states. Files/seams: API client, stores, auth/error components, tests. Constraints: match backend token discovery contract.

LABELS: ui

PARENT
  ↑ ○ swarmy-4pg: (EPIC) Svelte Multi-Swarm Dashboard ● P1

DEPENDS ON
  → ○ swarmy-1zi: Build dashboard shell and navigation ● P1
  → ○ swarmy-55y: Add local auth and request validation defaults ● P1

BLOCKS
  ← ○ swarmy-5lt: Add event timeline and failure visibility ● P2
  ← ○ swarmy-n1s: Add frontend build and UI smoke tests ● P1


```

## swarmy-gyl
```text
○ swarmy-gyl · Add event cursor endpoint for polling   [● P2 · OPEN]
Owner: Matt Spurlin · Type: feature
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Add incremental event polling for the UI. Acceptance: frontend can poll after a run-scoped cursor and receive deterministic ordering without missing, duplicating, or mixing events across simultaneous swarms. Files/seams: event query API, cursor encoding, tests. Constraints: polling is the v1 realtime fallback.

LABELS: api

PARENT
  ↑ ○ swarmy-t4r: (EPIC) Jazzy Backend API ● P1

DEPENDS ON
  → ○ swarmy-s36: Expose bead, agent, and stage detail endpoints ● P1

BLOCKS
  ← ○ swarmy-5lt: Add event timeline and failure visibility ● P2
  ← ○ swarmy-e24: Add full end-to-end first-milestone smoke test ● P1


```

## swarmy-36i
```text
○ swarmy-36i · Integrate /bead-swarm workflow guidance   [● P2 · OPEN]
Owner: Matt Spurlin · Type: chore
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Document how agents use Swarmy during bead-swarm runs. Acceptance: docs and MCP prompt/resource tell agents when to call swarmy init, which stage names to emit, and how to recover if Swarmy is unavailable. Files/seams: AGENTS.md, MCP template, examples. Constraints: use bd, never bn.

LABELS: docs

PARENT
  ↑ ○ swarmy-yyx: (EPIC) Agent-Facing CLI and MCP Surface ● P1

DEPENDS ON
  → ○ swarmy-bde: Add CLI equivalent for /bead-swarm instructions ● P1

BLOCKS
  ← ○ swarmy-z9e: Add agent-facing project instructions ● P2


```

## swarmy-vvw
```text
○ swarmy-vvw · Keep CLI and MCP behavior in parity   [● P2 · OPEN]
Owner: Matt Spurlin · Type: task
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Add shared handler parity coverage for CLI and MCP. Acceptance: shared tests prove CLI and MCP handlers produce equivalent event records, and golden fixtures cover initialize, list-tools, call-tool, and resource-or-prompt behavior. Files/seams: handler abstraction, fixtures, golden/replay tests. Constraints: do not duplicate business logic in transports.

LABELS: verify

PARENT
  ↑ ○ swarmy-yyx: (EPIC) Agent-Facing CLI and MCP Surface ● P1

DEPENDS ON
  → ○ swarmy-2a5: Implement advisor-style CLI event commands ● P1
  → ○ swarmy-bde: Add CLI equivalent for /bead-swarm instructions ● P1
  → ○ swarmy-l2z: Serve MCP write tools for swarm events ● P1

BLOCKS
  ← ○ swarmy-9kh: Add focused backend unit and integration tests ● P1


```

## swarmy-6jm
```text
○ swarmy-6jm · Document local build and run workflow   [● P2 · OPEN]
Owner: Matt Spurlin · Type: chore
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Document how contributors build and run Swarmy locally. Acceptance: README or runbook covers backend build, frontend build, tests, and local server startup. Files/seams: README.md, AGENTS.md or contributor notes. Constraints: keep docs accurate for the greenfield scaffold.

LABELS: docs

PARENT
  ↑ ○ swarmy-cs5: (EPIC) Foundation and Monorepo Shape ● P1

DEPENDS ON
  → ○ swarmy-yx5: Scaffold Nim/Svelte monorepo and build targets ● P0


```

## swarmy-yuf
```text
○ swarmy-yuf · Document ecosystem request routing policy   [● P3 · OPEN]
Owner: Matt Spurlin · Type: chore
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Tell agents where to file Nim ecosystem gaps. Acceptance: docs tell agents to file gaps in the owning project request folder, creating a new project bucket only when the owning repo/project is not known. Files/seams: AGENTS.md, contributor docs. Constraints: do not assume example names are real projects.

LABELS: docs

PARENT
  ↑ ○ swarmy-8t5: (EPIC) Agent Knowledge and Ecosystem Follow-up ● P3

DEPENDS ON
  → ○ swarmy-43p: Integrate research notes into contributor context ● P3

BLOCKS
  ← ○ swarmy-z9e: Add agent-facing project instructions ● P2


```

## swarmy-9zz
```text
○ swarmy-9zz · Track upstream request fallbacks   [● P3 · OPEN]
Owner: Matt Spurlin · Type: chore
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Document fallback choices for nonblocking upstream gaps. Acceptance: docs record that Jazzy realtime and NimCP current-spec requests are nonblocking, name local polling/MCP fallback choices, and explain when to revisit upstream requests. Files/seams: docs/runbook or ADR, links to project request folders. Constraints: do not block product work on external projects.

LABELS: docs

PARENT
  ↑ ○ swarmy-8t5: (EPIC) Agent Knowledge and Ecosystem Follow-up ● P3

DEPENDS ON
  → ○ swarmy-43p: Integrate research notes into contributor context ● P3


```

## swarmy-43p
```text
○ swarmy-43p · Integrate research notes into contributor context   [● P3 · OPEN]
Owner: Matt Spurlin · Type: chore
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Link research findings from future-agent docs. Acceptance: docs link to checked-in research notes and explain which Jazzy/NimCP findings affect Swarmy implementation choices. Files/seams: AGENTS.md, README.md, research notes. Constraints: do not duplicate long research verbatim.

LABELS: docs

PARENT
  ↑ ○ swarmy-8t5: (EPIC) Agent Knowledge and Ecosystem Follow-up ● P3

DEPENDS ON
  → ○ swarmy-ami: Establish thin binary and internal package boundaries ● P1

BLOCKS
  ← ○ swarmy-9zz: Track upstream request fallbacks ● P3
  ← ○ swarmy-yuf: Document ecosystem request routing policy ● P3


```

## swarmy-8t5
```text
○ swarmy-8t5 [EPIC] · Agent Knowledge and Ecosystem Follow-up   [● P3 · OPEN]
Owner: Matt Spurlin · Type: epic
Created: 2026-06-21 · Updated: 2026-06-21

DESCRIPTION
What: Keep future agents aligned with research and request-routing conventions. Acceptance: docs explain research findings, nonblocking upstream requests, and bd-only project tracking. Files/seams: AGENTS.md, README, ADRs/runbook. Constraints: ecosystem requests are follow-up docs, not product blockers.

LABELS: docs

CHILDREN
  ↳ ○ swarmy-43p: Integrate research notes into contributor context ● P3
  ↳ ○ swarmy-9zz: Track upstream request fallbacks ● P3
  ↳ ○ swarmy-yuf: Document ecosystem request routing policy ● P3
  ↳ ○ swarmy-z9e: Add agent-facing project instructions ● P2
  ◐ 0/4 complete (0%)


```


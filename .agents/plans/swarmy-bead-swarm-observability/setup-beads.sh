#!/usr/bin/env bash
set -euo pipefail

[ -d .beads ] || bd init --non-interactive --skip-agents

# --- Epic: Foundation and Monorepo Shape ---
EPIC_FOUNDATION=$(bd create 'Foundation and Monorepo Shape' \
  -d 'What: Establish the Swarmy monorepo baseline. Acceptance: the repo has runnable backend, frontend, smoke-harness, and contributor docs work organized under one epic. Files/seams: root layout, build scripts, docs, tests. Constraints: greenfield repo; do not assume existing source.' \
  -p 1 -l setup -t epic --silent)

SCAFFOLD=$(bd create 'Scaffold Nim/Svelte monorepo and build targets' \
  -d 'What: Create the Nim backend and Svelte frontend monorepo skeleton. Acceptance: nimble build, the Svelte app build, and a root build command work from a fresh checkout. Files/seams: root layout, .nimble, src/, apps/web/, package manifests, root scripts. Constraints: use Nim outside frontend and Svelte for frontend.' \
  -p 0 -l setup -t task --silent)
bd dep add "$SCAFFOLD" "$EPIC_FOUNDATION" -t parent-child

THIN_BINARY=$(bd create 'Establish thin binary and internal package boundaries' \
  -d 'What: Shape the Swarmy binary like advisor with a thin entrypoint and testable internals. Acceptance: swarmy --version, swarmy serve, and swarmy mcp dispatch through internal modules. Files/seams: src/swarmy.nim, src/swarmy_cli/, src/swarmy_core/, tests. Constraints: keep binary wrapper minimal.' \
  -p 1 -l core -t task --silent)
bd dep add "$THIN_BINARY" "$EPIC_FOUNDATION" -t parent-child
bd dep add "$THIN_BINARY" "$SCAFFOLD"

SMOKE_SKELETON=$(bd create 'Add smoke test harness skeleton' \
  -d 'What: Add isolated smoke-test scaffolding before product behavior exists. Acceptance: test utilities create a temp repo, temp Swarmy database path, and placeholder backend/frontend smoke commands. Files/seams: tests/, test fixtures, root test script, temp repo helpers. Constraints: do not require init, API, or event behavior yet.' \
  -p 1 -l verify -t task --silent)
bd dep add "$SMOKE_SKELETON" "$EPIC_FOUNDATION" -t parent-child
bd dep add "$SMOKE_SKELETON" "$SCAFFOLD"

LOCAL_RUNBOOK=$(bd create 'Document local build and run workflow' \
  -d 'What: Document how contributors build and run Swarmy locally. Acceptance: README or runbook covers backend build, frontend build, tests, and local server startup. Files/seams: README.md, AGENTS.md or contributor notes. Constraints: keep docs accurate for the greenfield scaffold.' \
  -p 2 -l docs -t chore --silent)
bd dep add "$LOCAL_RUNBOOK" "$EPIC_FOUNDATION" -t parent-child
bd dep add "$LOCAL_RUNBOOK" "$SCAFFOLD"

# --- Epic: Persistent Swarm State Model ---
EPIC_STATE=$(bd create 'Persistent Swarm State Model' \
  -d 'What: Build durable Swarmy run identity, event storage, Beads snapshots, and merged read models. Acceptance: runs survive restart and concurrent event writers remain isolated by run. Files/seams: .swarmy metadata, SQLite persistence, bd adapter, reducers. Constraints: Beads remains canonical for bead status where reliable.' \
  -p 1 -l data -t epic --silent)

INIT_RUN=$(bd create 'Implement .swarmy run initialization' \
  -d 'What: Implement swarmy init for repo-local run metadata. Acceptance: swarmy init creates idempotent ./.swarmy/ metadata with run ID, canonical repo path, created_at, schema version, and database/config pointers; unsafe symlinked paths are rejected or resolved predictably. Files/seams: CLI init command, metadata model, filesystem helpers, tests. Constraints: generated ID uniquely identifies simultaneous swarm runs.' \
  -p 0 -l data -t feature --silent)
bd dep add "$INIT_RUN" "$EPIC_STATE" -t parent-child
bd dep add "$INIT_RUN" "$THIN_BINARY"

EVENT_SCHEMA=$(bd create 'Create SQLite schema and event store' \
  -d 'What: Add durable tables and setup for Swarmy state. Acceptance: schema creates runs, agents, beads, stages, events, snapshots, and errors with RFC3339 timestamps, WAL/busy-timeout settings, unique event IDs, and run-scoped sequence cursors. Files/seams: persistence module, schema builder or SQL, repository tests. Constraints: SQLite is the default store.' \
  -p 1 -l data -t feature --silent)
bd dep add "$EVENT_SCHEMA" "$EPIC_STATE" -t parent-child
bd dep add "$EVENT_SCHEMA" "$INIT_RUN"

EVENTS=$(bd create 'Record idempotent agent and stage events' \
  -d 'What: Add append-only event writes and stage reduction. Acceptance: duplicate event IDs do not double-count state, allowed stage names are validated, unknown legacy stages reduce to unknown, and latest bead stage is deterministic. Files/seams: event model, stage enum, write API, reducer/read model tests. Constraints: stage enum includes coding, validation, review, merge, blocked, complete, unknown.' \
  -p 1 -l data -t feature --silent)
bd dep add "$EVENTS" "$EPIC_STATE" -t parent-child
bd dep add "$EVENTS" "$EVENT_SCHEMA"

CONCURRENCY=$(bd create 'Prove concurrent run isolation and writer safety' \
  -d 'What: Validate simultaneous Swarmy writers and runs. Acceptance: a test with two simultaneous run IDs and at least two writer processes records events without cross-run bleed, duplicate cursor assignment, or SQLite lock failures. Files/seams: persistence transactions, event writer, integration tests. Constraints: run-scoped cursors are required.' \
  -p 1 -l data -t task --silent)
bd dep add "$CONCURRENCY" "$EPIC_STATE" -t parent-child
bd dep add "$CONCURRENCY" "$EVENTS"

BD_SNAPSHOT=$(bd create 'Reconstruct bead snapshots from bd' \
  -d 'What: Read canonical Beads state without mutating it. Acceptance: Swarmy reads bd ready/list/show snapshots and handles missing bd, non-Beads repos, malformed output, deleted or renamed beads, stale snapshots, and command timeouts with typed errors. Files/seams: bd adapter, parsers, snapshot service, fixtures. Constraints: all bd usage is read-only.' \
  -p 1 -l data -t feature --silent)
bd dep add "$BD_SNAPSHOT" "$EPIC_STATE" -t parent-child
bd dep add "$BD_SNAPSHOT" "$EVENT_SCHEMA"

MERGED_MODEL=$(bd create 'Build merged Beads plus Swarmy read model' \
  -d 'What: Merge canonical Beads snapshots with Swarmy agent/stage events. Acceptance: queries return beads discovered from bd even without Swarmy events, overlay Swarmy events when present, and preserve canonical Beads status. Files/seams: reducer/read model, bd snapshot merger, fixtures. Constraints: Swarmy is not the source of truth for Beads status.' \
  -p 1 -l data -t feature --silent)
bd dep add "$MERGED_MODEL" "$EPIC_STATE" -t parent-child
bd dep add "$MERGED_MODEL" "$BD_SNAPSHOT"
bd dep add "$MERGED_MODEL" "$EVENTS"

RESTART_TEST=$(bd create 'Prove persistence across process restarts' \
  -d 'What: Add restart persistence coverage for Swarmy state. Acceptance: a test writes a run/event, restarts the Swarmy process, and reads back the same run and bead stage from the same database. Files/seams: integration tests, temp repo/test process harness. Constraints: use a real process restart, not only an in-process handle reopen.' \
  -p 1 -l verify -t task --silent)
bd dep add "$RESTART_TEST" "$EPIC_STATE" -t parent-child
bd dep add "$RESTART_TEST" "$MERGED_MODEL"

# --- Epic: Agent-Facing CLI and MCP Surface ---
EPIC_AGENT=$(bd create 'Agent-Facing CLI and MCP Surface' \
  -d 'What: Give agents CLI and MCP surfaces to record Swarmy state and discover bead-swarm instructions. Acceptance: CLI and MCP produce equivalent events and expose /bead-swarm guidance. Files/seams: CLI parser, MCP server, shared handlers, templates, tests. Constraints: no bn usage.' \
  -p 1 -l agent -t epic --silent)

CLI_EVENTS=$(bd create 'Implement advisor-style CLI event commands' \
  -d 'What: Add CLI commands for agent writes. Acceptance: swarmy event, swarmy stage, swarmy agent, and swarmy snapshot write the same state as the internal event API with stable exit codes. Files/seams: CLI parser, command handlers, stdout/stderr contracts, command tests. Constraints: match advisor-style CLI discipline where practical.' \
  -p 1 -l agent -t feature --silent)
bd dep add "$CLI_EVENTS" "$EPIC_AGENT" -t parent-child
bd dep add "$CLI_EVENTS" "$EVENTS"

MCP_TOOLS=$(bd create 'Serve MCP write tools for swarm events' \
  -d 'What: Add MCP stdio tools for Swarmy writes and reads. Acceptance: an MCP client can list and call tools to initialize a run, record an agent event, set bead stage, and fetch a snapshot; v1 documents whether it uses NimCP or a thin local JSON-RPC adapter and what protocol version it advertises. Files/seams: MCP server module, tool schemas, protocol decision note, handler tests or replay fixtures. Constraints: keep tool trust boundaries explicit.' \
  -p 1 -l agent -t feature --silent)
bd dep add "$MCP_TOOLS" "$EPIC_AGENT" -t parent-child
bd dep add "$MCP_TOOLS" "$EVENTS"

MCP_BEAD_SWARM=$(bd create 'Serve /bead-swarm MCP resource or prompt' \
  -d 'What: Expose bead-swarm workflow guidance through MCP. Acceptance: the swarmy binary exposes a /bead-swarm resource or prompt instructing agents to run swarmy init and record coding/review progress. Files/seams: MCP resources/prompts, skill text template, tests. Constraints: use the same guidance source as the CLI instruction command.' \
  -p 1 -l agent -t feature --silent)
bd dep add "$MCP_BEAD_SWARM" "$EPIC_AGENT" -t parent-child
bd dep add "$MCP_BEAD_SWARM" "$MCP_TOOLS"

CLI_BEAD_SWARM=$(bd create 'Add CLI equivalent for /bead-swarm instructions' \
  -d 'What: Expose bead-swarm workflow guidance through the CLI. Acceptance: swarmy bead-swarm or swarmy instructions bead-swarm prints the same guidance exposed through MCP, including swarmy init and stage event conventions. Files/seams: CLI command, shared instruction template, tests. Constraints: keep MCP and CLI text in one source.' \
  -p 1 -l agent -t feature --silent)
bd dep add "$CLI_BEAD_SWARM" "$EPIC_AGENT" -t parent-child
bd dep add "$CLI_BEAD_SWARM" "$MCP_BEAD_SWARM"

PARITY=$(bd create 'Keep CLI and MCP behavior in parity' \
  -d 'What: Add shared handler parity coverage for CLI and MCP. Acceptance: shared tests prove CLI and MCP handlers produce equivalent event records, and golden fixtures cover initialize, list-tools, call-tool, and resource-or-prompt behavior. Files/seams: handler abstraction, fixtures, golden/replay tests. Constraints: do not duplicate business logic in transports.' \
  -p 2 -l verify -t task --silent)
bd dep add "$PARITY" "$EPIC_AGENT" -t parent-child
bd dep add "$PARITY" "$CLI_EVENTS"
bd dep add "$PARITY" "$MCP_TOOLS"
bd dep add "$PARITY" "$CLI_BEAD_SWARM"

WORKFLOW_GUIDANCE=$(bd create 'Integrate /bead-swarm workflow guidance' \
  -d 'What: Document how agents use Swarmy during bead-swarm runs. Acceptance: docs and MCP prompt/resource tell agents when to call swarmy init, which stage names to emit, and how to recover if Swarmy is unavailable. Files/seams: AGENTS.md, MCP template, examples. Constraints: use bd, never bn.' \
  -p 2 -l docs -t chore --silent)
bd dep add "$WORKFLOW_GUIDANCE" "$EPIC_AGENT" -t parent-child
bd dep add "$WORKFLOW_GUIDANCE" "$CLI_BEAD_SWARM"

# --- Epic: Jazzy Backend API ---
EPIC_API=$(bd create 'Jazzy Backend API' \
  -d 'What: Serve Swarmy state through a Jazzy API and local static app host. Acceptance: routes expose run lists, bead details, event cursors, and production-safe auth defaults. Files/seams: Jazzy server, routes, controllers, serializers, middleware. Constraints: start with REST polling, not realtime push.' \
  -p 1 -l api -t epic --silent)

JAZZY_SERVER=$(bd create 'Scaffold Jazzy server and static app hosting' \
  -d 'What: Add the backend server skeleton. Acceptance: swarmy serve starts a Jazzy server on a safe local bind address and can serve built Svelte assets. Files/seams: server module, route registration, static file config. Constraints: safe local bind by default.' \
  -p 1 -l api -t task --silent)
bd dep add "$JAZZY_SERVER" "$EPIC_API" -t parent-child
bd dep add "$JAZZY_SERVER" "$SCAFFOLD"

RUN_ENDPOINTS=$(bd create 'Expose run and swarm list endpoints' \
  -d 'What: Add API endpoints for known swarm runs. Acceptance: API returns active/recent runs with run IDs, repo paths, status, timestamps, aggregate counts, and no cross-run data leakage. Files/seams: Jazzy controllers/routes, read models, JSON serializers, tests. Constraints: use merged read model.' \
  -p 1 -l api -t feature --silent)
bd dep add "$RUN_ENDPOINTS" "$EPIC_API" -t parent-child
bd dep add "$RUN_ENDPOINTS" "$MERGED_MODEL"
bd dep add "$RUN_ENDPOINTS" "$JAZZY_SERVER"

DETAIL_ENDPOINTS=$(bd create 'Expose bead, agent, and stage detail endpoints' \
  -d 'What: Add selected-run detail endpoints. Acceptance: API returns current bead assignments, agent identities, coding/review stage, canonical Beads status, last event time, and error/blocker details, including bd-only beads. Files/seams: controllers/routes, reducer queries, JSON serializers, tests. Constraints: status from bd remains canonical.' \
  -p 1 -l api -t feature --silent)
bd dep add "$DETAIL_ENDPOINTS" "$EPIC_API" -t parent-child
bd dep add "$DETAIL_ENDPOINTS" "$MERGED_MODEL"
bd dep add "$DETAIL_ENDPOINTS" "$RUN_ENDPOINTS"

CURSOR_ENDPOINT=$(bd create 'Add event cursor endpoint for polling' \
  -d 'What: Add incremental event polling for the UI. Acceptance: frontend can poll after a run-scoped cursor and receive deterministic ordering without missing, duplicating, or mixing events across simultaneous swarms. Files/seams: event query API, cursor encoding, tests. Constraints: polling is the v1 realtime fallback.' \
  -p 2 -l api -t feature --silent)
bd dep add "$CURSOR_ENDPOINT" "$EPIC_API" -t parent-child
bd dep add "$CURSOR_ENDPOINT" "$DETAIL_ENDPOINTS"

LOCAL_AUTH=$(bd create 'Add local auth and request validation defaults' \
  -d 'What: Add production-safe local auth and validation. Acceptance: production mode requires a local token or Jazzy auth guard, defines how the token is generated or discovered for browser use, validates JSON payloads, enforces payload-size limits, and rejects unsafe bind/config combinations. Files/seams: middleware, config, validation helpers, docs/tests. Constraints: local development remains ergonomic.' \
  -p 1 -l api -t task --silent)
bd dep add "$LOCAL_AUTH" "$EPIC_API" -t parent-child
bd dep add "$LOCAL_AUTH" "$JAZZY_SERVER"

TRUST_BOUNDARIES=$(bd create 'Harden repo/db path and MCP trust boundaries' \
  -d 'What: Harden Swarmy inputs and diagnostics. Acceptance: --repo and --db inputs are canonicalized, symlinked .swarmy metadata is handled safely, diagnostics redact secrets, MCP tool descriptions state trust boundaries, and invalid stage/payload inputs return typed errors. Files/seams: config/path helpers, diagnostics, MCP descriptions, validation tests. Constraints: production safety is required.' \
  -p 1 -l ops -t task --silent)
bd dep add "$TRUST_BOUNDARIES" "$EPIC_API" -t parent-child
bd dep add "$TRUST_BOUNDARIES" "$LOCAL_AUTH"
bd dep add "$TRUST_BOUNDARIES" "$EVENTS"

# --- Epic: Svelte Multi-Swarm Dashboard ---
EPIC_UI=$(bd create 'Svelte Multi-Swarm Dashboard' \
  -d 'What: Build the browser dashboard for concurrent bead-swarm visibility. Acceptance: users can select runs, see beads by stage, inspect agent activity, and watch polling updates without layout issues. Files/seams: Svelte app, API client, stores, components, tests. Constraints: no landing page; first screen is the dashboard.' \
  -p 1 -l ui -t epic --silent)

UI_SHELL=$(bd create 'Build dashboard shell and navigation' \
  -d 'What: Create the Svelte dashboard shell. Acceptance: app renders run list, selected-run detail area, loading, empty, and error states. Files/seams: apps/web/src/, routes/components, API client. Constraints: application UI, not marketing layout.' \
  -p 1 -l ui -t task --silent)
bd dep add "$UI_SHELL" "$EPIC_UI" -t parent-child
bd dep add "$UI_SHELL" "$SCAFFOLD"

RUN_OVERVIEW=$(bd create 'Display concurrent swarm run overview' \
  -d 'What: Show multiple active swarm runs. Acceptance: users can distinguish simultaneous runs by repo, run ID, age, status, active bead count, and last activity. Files/seams: run list components, stores, API client tests. Constraints: preserve selection across refresh.' \
  -p 1 -l ui -t feature --silent)
bd dep add "$RUN_OVERVIEW" "$EPIC_UI" -t parent-child
bd dep add "$RUN_OVERVIEW" "$RUN_ENDPOINTS"
bd dep add "$RUN_OVERVIEW" "$UI_SHELL"

STAGE_BOARD=$(bd create 'Show bead stage board for coding and review' \
  -d 'What: Visualize current bead stages. Acceptance: selected run detail shows bd-discovered beads grouped or labeled by coding, validation, review, merge, blocked, and complete with assigned agent where known. Files/seams: bead board/table components, stage badges, stores. Constraints: coding and review stages must be first-class.' \
  -p 1 -l ui -t feature --silent)
bd dep add "$STAGE_BOARD" "$EPIC_UI" -t parent-child
bd dep add "$STAGE_BOARD" "$DETAIL_ENDPOINTS"
bd dep add "$STAGE_BOARD" "$UI_SHELL"

UI_AUTH=$(bd create 'Handle local token auth in the frontend client' \
  -d 'What: Wire frontend auth behavior. Acceptance: Svelte API client can discover or receive the configured local token through the documented local-hosting path, send it on requests, show auth failures clearly, and keep safe empty/error states. Files/seams: API client, stores, auth/error components, tests. Constraints: match backend token discovery contract.' \
  -p 2 -l ui -t task --silent)
bd dep add "$UI_AUTH" "$EPIC_UI" -t parent-child
bd dep add "$UI_AUTH" "$LOCAL_AUTH"
bd dep add "$UI_AUTH" "$UI_SHELL"

EVENT_TIMELINE=$(bd create 'Add event timeline and failure visibility' \
  -d 'What: Show recent activity and failures for a selected run. Acceptance: selected run detail shows recent events and clearly surfaces blocked/failed events with timestamps and source agent. Files/seams: timeline components, error states, event API client. Constraints: use run-scoped cursor endpoint.' \
  -p 2 -l ui -t feature --silent)
bd dep add "$EVENT_TIMELINE" "$EPIC_UI" -t parent-child
bd dep add "$EVENT_TIMELINE" "$CURSOR_ENDPOINT"
bd dep add "$EVENT_TIMELINE" "$UI_AUTH"

POLLING_UI=$(bd create 'Implement polling refresh without layout shifts' \
  -d 'What: Add refresh behavior for active runs. Acceptance: dashboard refreshes active runs from the cursor endpoint, preserves selection, and does not overlap or resize core controls on mobile or desktop. Files/seams: stores, timers, responsive CSS, Playwright/screenshot checks. Constraints: no viewport-scaled fonts; stable layout dimensions.' \
  -p 2 -l ui -t task --silent)
bd dep add "$POLLING_UI" "$EPIC_UI" -t parent-child
bd dep add "$POLLING_UI" "$EVENT_TIMELINE"

# --- Epic: Verification, Operations, and Packaging ---
EPIC_VERIFY=$(bd create 'Verification Operations and Packaging' \
  -d 'What: Add production-oriented quality gates, packaging, diagnostics, and runbooks. Acceptance: tests cover backend/frontend/e2e, CI runs them, and users can install/run/recover Swarmy. Files/seams: tests, CI, scripts, diagnostics, docs. Constraints: verification must match actual Nim/Svelte stack.' \
  -p 1 -l verify -t epic --silent)

BACKEND_TESTS=$(bd create 'Add focused backend unit and integration tests' \
  -d 'What: Cover backend behavior with Nim tests. Acceptance: tests cover event writes, reducers, bd snapshot parsing including edge cases, merged read models, API serializers, concurrent writes, and MCP/CLI parity. Files/seams: tests/, fixtures, Nimble test config. Constraints: run under nimble test.' \
  -p 1 -l verify -t task --silent)
bd dep add "$BACKEND_TESTS" "$EPIC_VERIFY" -t parent-child
bd dep add "$BACKEND_TESTS" "$PARITY"
bd dep add "$BACKEND_TESTS" "$DETAIL_ENDPOINTS"
bd dep add "$BACKEND_TESTS" "$CONCURRENCY"

FRONTEND_TESTS=$(bd create 'Add frontend build and UI smoke tests' \
  -d 'What: Cover frontend build and dashboard rendering. Acceptance: Svelte build and one browser smoke test prove the dashboard renders active bead coding/review state from fixture API data and handles local-token auth errors. Files/seams: frontend test config, fixture API, Playwright or equivalent. Constraints: verify desktop and mobile framing.' \
  -p 1 -l verify -t task --silent)
bd dep add "$FRONTEND_TESTS" "$EPIC_VERIFY" -t parent-child
bd dep add "$FRONTEND_TESTS" "$STAGE_BOARD"
bd dep add "$FRONTEND_TESTS" "$UI_AUTH"

E2E_SMOKE=$(bd create 'Add full end-to-end first-milestone smoke test' \
  -d 'What: Prove the user-facing first milestone end to end. Acceptance: one smoke command initializes a temp Beads repo, runs swarmy init, records synthetic coding and review events through CLI or MCP, starts the API, and verifies the UI-facing state endpoint. Files/seams: smoke test runner, temp Beads fixture, backend process harness. Constraints: use real CLI or MCP path.' \
  -p 1 -l verify -t task --silent)
bd dep add "$E2E_SMOKE" "$EPIC_VERIFY" -t parent-child
bd dep add "$E2E_SMOKE" "$BACKEND_TESTS"
bd dep add "$E2E_SMOKE" "$CURSOR_ENDPOINT"

CI_PACKAGING=$(bd create 'Add CI and release packaging' \
  -d 'What: Add automated quality gates and packaging recipe. Acceptance: CI runs backend tests, frontend build/tests, and produces a local binary/package artifact recipe. Files/seams: .github/workflows/, packaging scripts, release notes. Constraints: do not require external services for core CI.' \
  -p 2 -l ops -t chore --silent)
bd dep add "$CI_PACKAGING" "$EPIC_VERIFY" -t parent-child
bd dep add "$CI_PACKAGING" "$E2E_SMOKE"
bd dep add "$CI_PACKAGING" "$FRONTEND_TESTS"

DIAGNOSTICS=$(bd create 'Add production logging and diagnostics' \
  -d 'What: Add operational logging and swarmy doctor. Acceptance: server logs include run ID/request ID/stage transitions without leaking secrets, and a diagnostic CLI reports config, database path, and recent errors. Files/seams: logging module, swarmy doctor, docs/tests. Constraints: redact tokens and secrets.' \
  -p 2 -l ops -t task --silent)
bd dep add "$DIAGNOSTICS" "$EPIC_VERIFY" -t parent-child
bd dep add "$DIAGNOSTICS" "$TRUST_BOUNDARIES"

PROD_RUNBOOK=$(bd create 'Write production runbook and recovery guide' \
  -d 'What: Document production-like operation and recovery. Acceptance: docs explain configuring MCP host, running swarmy init, starting the UI, interpreting stages, and recovering from missing events or stale .swarmy metadata. Files/seams: README, docs/runbook, AGENTS guidance. Constraints: include both CLI and MCP paths.' \
  -p 2 -l docs -t chore --silent)
bd dep add "$PROD_RUNBOOK" "$EPIC_VERIFY" -t parent-child
bd dep add "$PROD_RUNBOOK" "$CI_PACKAGING"
bd dep add "$PROD_RUNBOOK" "$DIAGNOSTICS"

# --- Epic: Agent Knowledge and Ecosystem Follow-up ---
EPIC_KNOWLEDGE=$(bd create 'Agent Knowledge and Ecosystem Follow-up' \
  -d 'What: Keep future agents aligned with research and request-routing conventions. Acceptance: docs explain research findings, nonblocking upstream requests, and bd-only project tracking. Files/seams: AGENTS.md, README, ADRs/runbook. Constraints: ecosystem requests are follow-up docs, not product blockers.' \
  -p 3 -l docs -t epic --silent)

RESEARCH_CONTEXT=$(bd create 'Integrate research notes into contributor context' \
  -d 'What: Link research findings from future-agent docs. Acceptance: docs link to checked-in research notes and explain which Jazzy/NimCP findings affect Swarmy implementation choices. Files/seams: AGENTS.md, README.md, research notes. Constraints: do not duplicate long research verbatim.' \
  -p 3 -l docs -t chore --silent)
bd dep add "$RESEARCH_CONTEXT" "$EPIC_KNOWLEDGE" -t parent-child
bd dep add "$RESEARCH_CONTEXT" "$THIN_BINARY"

UPSTREAM_FALLBACKS=$(bd create 'Track upstream request fallbacks' \
  -d 'What: Document fallback choices for nonblocking upstream gaps. Acceptance: docs record that Jazzy realtime and NimCP current-spec requests are nonblocking, name local polling/MCP fallback choices, and explain when to revisit upstream requests. Files/seams: docs/runbook or ADR, links to project request folders. Constraints: do not block product work on external projects.' \
  -p 3 -l docs -t chore --silent)
bd dep add "$UPSTREAM_FALLBACKS" "$EPIC_KNOWLEDGE" -t parent-child
bd dep add "$UPSTREAM_FALLBACKS" "$RESEARCH_CONTEXT"

REQUEST_POLICY=$(bd create 'Document ecosystem request routing policy' \
  -d 'What: Tell agents where to file Nim ecosystem gaps. Acceptance: docs tell agents to file gaps in the owning project request folder, creating a new project bucket only when the owning repo/project is not known. Files/seams: AGENTS.md, contributor docs. Constraints: do not assume example names are real projects.' \
  -p 3 -l docs -t chore --silent)
bd dep add "$REQUEST_POLICY" "$EPIC_KNOWLEDGE" -t parent-child
bd dep add "$REQUEST_POLICY" "$RESEARCH_CONTEXT"

AGENT_INSTRUCTIONS=$(bd create 'Add agent-facing project instructions' \
  -d 'What: Add durable instructions for future agents. Acceptance: AGENTS.md tells agents to use bd, avoid bn, follow Swarmy event conventions, and route ecosystem requests to the owning project folder. Files/seams: AGENTS.md, possibly CLAUDE.md. Constraints: this project is Beads-only.' \
  -p 2 -l docs -t chore --silent)
bd dep add "$AGENT_INSTRUCTIONS" "$EPIC_KNOWLEDGE" -t parent-child
bd dep add "$AGENT_INSTRUCTIONS" "$WORKFLOW_GUIDANCE"
bd dep add "$AGENT_INSTRUCTIONS" "$REQUEST_POLICY"

echo "Created Swarmy Beads graph."

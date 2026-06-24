# Swarmy Beads Graph Snapshot
Generated: 2026-06-21

## bd list --limit 100 --flat
```text
● swarmy-djn [● P0] [feature] [data] - Implement .swarmy run initialization (parent: swarmy-4b2, blocked by: swarmy-ami, blocks: swarmy-0g2)
○ swarmy-yx5 [● P0] [task] [setup] - Scaffold Nim/Svelte monorepo and build targets (parent: swarmy-cs5, blocks: swarmy-1zi, swarmy-6jm, swarmy-ami, swarmy-wow, swarmy-zvh)
● swarmy-e24 [● P1] [task] [verify] - Add full end-to-end first-milestone smoke test (parent: swarmy-78o, blocked by: swarmy-9kh, swarmy-gyl, blocks: swarmy-1ek)
● swarmy-n1s [● P1] [task] [verify] - Add frontend build and UI smoke tests (parent: swarmy-78o, blocked by: swarmy-7lo, swarmy-9xh, blocks: swarmy-1ek)
○ swarmy-78o [● P1] [epic] [verify] - Verification Operations and Packaging
● swarmy-9kh [● P1] [task] [verify] - Add focused backend unit and integration tests (parent: swarmy-78o, blocked by: swarmy-1j8, swarmy-s36, swarmy-vvw, blocks: swarmy-e24)
● swarmy-7lo [● P1] [feature] [ui] - Show bead stage board for coding and review (parent: swarmy-4pg, blocked by: swarmy-1zi, swarmy-s36, blocks: swarmy-n1s)
● swarmy-2cz [● P1] [feature] [ui] - Display concurrent swarm run overview (parent: swarmy-4pg, blocked by: swarmy-1zi, swarmy-4nu)
● swarmy-1zi [● P1] [task] [ui] - Build dashboard shell and navigation (parent: swarmy-4pg, blocked by: swarmy-yx5, blocks: swarmy-2cz, swarmy-7lo, swarmy-9xh)
○ swarmy-4pg [● P1] [epic] [ui] - Svelte Multi-Swarm Dashboard
● swarmy-el7 [● P1] [task] [ops] - Harden repo/db path and MCP trust boundaries (parent: swarmy-t4r, blocked by: swarmy-3p0, swarmy-55y, blocks: swarmy-513)
● swarmy-55y [● P1] [task] [api] - Add local auth and request validation defaults (parent: swarmy-t4r, blocked by: swarmy-zvh, blocks: swarmy-9xh, swarmy-el7)
● swarmy-s36 [● P1] [feature] [api] - Expose bead, agent, and stage detail endpoints (parent: swarmy-t4r, blocked by: swarmy-4nu, swarmy-iph, blocks: swarmy-7lo, swarmy-9kh, swarmy-gyl)
● swarmy-4nu [● P1] [feature] [api] - Expose run and swarm list endpoints (parent: swarmy-t4r, blocked by: swarmy-iph, swarmy-zvh, blocks: swarmy-2cz, swarmy-s36)
● swarmy-zvh [● P1] [task] [api] - Scaffold Jazzy server and static app hosting (parent: swarmy-t4r, blocked by: swarmy-yx5, blocks: swarmy-4nu, swarmy-55y)
○ swarmy-t4r [● P1] [epic] [api] - Jazzy Backend API
● swarmy-bde [● P1] [feature] [agent] - Add CLI equivalent for /bead-swarm instructions (parent: swarmy-yyx, blocked by: swarmy-otx, blocks: swarmy-36i, swarmy-vvw)
● swarmy-otx [● P1] [feature] [agent] - Serve /bead-swarm MCP resource or prompt (parent: swarmy-yyx, blocked by: swarmy-l2z, blocks: swarmy-bde)
● swarmy-l2z [● P1] [feature] [agent] - Serve MCP write tools for swarm events (parent: swarmy-yyx, blocked by: swarmy-3p0, blocks: swarmy-otx, swarmy-vvw)
● swarmy-2a5 [● P1] [feature] [agent] - Implement advisor-style CLI event commands (parent: swarmy-yyx, blocked by: swarmy-3p0, blocks: swarmy-vvw)
○ swarmy-yyx [● P1] [epic] [agent] - Agent-Facing CLI and MCP Surface
● swarmy-5ph [● P1] [task] [verify] - Prove persistence across process restarts (parent: swarmy-4b2, blocked by: swarmy-iph)
● swarmy-iph [● P1] [feature] [data] - Build merged Beads plus Swarmy read model (parent: swarmy-4b2, blocked by: swarmy-3p0, swarmy-3z4, blocks: swarmy-4nu, swarmy-5ph, swarmy-s36)
● swarmy-3z4 [● P1] [feature] [data] - Reconstruct bead snapshots from bd (parent: swarmy-4b2, blocked by: swarmy-0g2, blocks: swarmy-iph)
● swarmy-1j8 [● P1] [task] [data] - Prove concurrent run isolation and writer safety (parent: swarmy-4b2, blocked by: swarmy-3p0, blocks: swarmy-9kh)
● swarmy-3p0 [● P1] [feature] [data] - Record idempotent agent and stage events (parent: swarmy-4b2, blocked by: swarmy-0g2, blocks: swarmy-1j8, swarmy-2a5, swarmy-el7, swarmy-iph, swarmy-l2z)
● swarmy-0g2 [● P1] [feature] [data] - Create SQLite schema and event store (parent: swarmy-4b2, blocked by: swarmy-djn, blocks: swarmy-3p0, swarmy-3z4)
○ swarmy-4b2 [● P1] [epic] [data] - Persistent Swarm State Model
● swarmy-wow [● P1] [task] [verify] - Add smoke test harness skeleton (parent: swarmy-cs5, blocked by: swarmy-yx5)
● swarmy-ami [● P1] [task] [core] - Establish thin binary and internal package boundaries (parent: swarmy-cs5, blocked by: swarmy-yx5, blocks: swarmy-43p, swarmy-djn)
○ swarmy-cs5 [● P1] [epic] [setup] - Foundation and Monorepo Shape
● swarmy-z9e [● P2] [chore] [docs] - Add agent-facing project instructions (parent: swarmy-8t5, blocked by: swarmy-36i, swarmy-yuf)
● swarmy-3mk [● P2] [chore] [docs] - Write production runbook and recovery guide (parent: swarmy-78o, blocked by: swarmy-1ek, swarmy-513)
● swarmy-513 [● P2] [task] [ops] - Add production logging and diagnostics (parent: swarmy-78o, blocked by: swarmy-el7, blocks: swarmy-3mk)
● swarmy-1ek [● P2] [chore] [ops] - Add CI and release packaging (parent: swarmy-78o, blocked by: swarmy-e24, swarmy-n1s, blocks: swarmy-3mk)
● swarmy-rid [● P2] [task] [ui] - Implement polling refresh without layout shifts (parent: swarmy-4pg, blocked by: swarmy-5lt)
● swarmy-5lt [● P2] [feature] [ui] - Add event timeline and failure visibility (parent: swarmy-4pg, blocked by: swarmy-9xh, swarmy-gyl, blocks: swarmy-rid)
● swarmy-9xh [● P2] [task] [ui] - Handle local token auth in the frontend client (parent: swarmy-4pg, blocked by: swarmy-1zi, swarmy-55y, blocks: swarmy-5lt, swarmy-n1s)
● swarmy-gyl [● P2] [feature] [api] - Add event cursor endpoint for polling (parent: swarmy-t4r, blocked by: swarmy-s36, blocks: swarmy-5lt, swarmy-e24)
● swarmy-36i [● P2] [chore] [docs] - Integrate /bead-swarm workflow guidance (parent: swarmy-yyx, blocked by: swarmy-bde, blocks: swarmy-z9e)
● swarmy-vvw [● P2] [task] [verify] - Keep CLI and MCP behavior in parity (parent: swarmy-yyx, blocked by: swarmy-2a5, swarmy-bde, swarmy-l2z, blocks: swarmy-9kh)
● swarmy-6jm [● P2] [chore] [docs] - Document local build and run workflow (parent: swarmy-cs5, blocked by: swarmy-yx5)
● swarmy-yuf [● P3] [chore] [docs] - Document ecosystem request routing policy (parent: swarmy-8t5, blocked by: swarmy-43p, blocks: swarmy-z9e)
● swarmy-9zz [● P3] [chore] [docs] - Track upstream request fallbacks (parent: swarmy-8t5, blocked by: swarmy-43p)
● swarmy-43p [● P3] [chore] [docs] - Integrate research notes into contributor context (parent: swarmy-8t5, blocked by: swarmy-ami, blocks: swarmy-9zz, swarmy-yuf)
○ swarmy-8t5 [● P3] [epic] [docs] - Agent Knowledge and Ecosystem Follow-up

```

## bd dep cycles
```text

✓ No dependency cycles detected


```

## bd ready --limit 50 --plain
```text

📋 Ready work (8 issues with no active blockers):

1. [● P0] [task] swarmy-yx5: Scaffold Nim/Svelte monorepo and build targets
2. [● P1] [epic] swarmy-78o: Verification Operations and Packaging
3. [● P1] [epic] swarmy-4pg: Svelte Multi-Swarm Dashboard
4. [● P1] [epic] swarmy-t4r: Jazzy Backend API
5. [● P1] [epic] swarmy-yyx: Agent-Facing CLI and MCP Surface
6. [● P1] [epic] swarmy-4b2: Persistent Swarm State Model
7. [● P1] [epic] swarmy-cs5: Foundation and Monorepo Shape
8. [● P3] [epic] swarmy-8t5: Agent Knowledge and Ecosystem Follow-up


```

## bd ready --limit 50 --plain -t task
```text

📋 Ready work (1 issues with no active blockers):

1. [● P0] [task] swarmy-yx5: Scaffold Nim/Svelte monorepo and build targets


```

## Epic Trees

### swarmy-cs5
```text

🌲 Dependent tree for swarmy-cs5:

swarmy-cs5: Foundation and Monorepo Shape [P1] (open) [1m[BLOCKED][m
    ├── swarmy-6jm: Document local build and run workflow [P2] (open)
    ├── swarmy-ami: Establish thin binary and internal package boundaries [P1] (open)
    ├── swarmy-wow: Add smoke test harness skeleton [P1] (open)
    └── swarmy-yx5: Scaffold Nim/Svelte monorepo and build targets [P0] (open)


```

### swarmy-4b2
```text

🌲 Dependent tree for swarmy-4b2:

swarmy-4b2: Persistent Swarm State Model [P1] (open) [1m[BLOCKED][m
    ├── swarmy-0g2: Create SQLite schema and event store [P1] (open)
    ├── swarmy-1j8: Prove concurrent run isolation and writer safety [P1] (open)
    ├── swarmy-3p0: Record idempotent agent and stage events [P1] (open)
    ├── swarmy-3z4: Reconstruct bead snapshots from bd [P1] (open)
    ├── swarmy-5ph: Prove persistence across process restarts [P1] (open)
    ├── swarmy-djn: Implement .swarmy run initialization [P0] (open)
    └── swarmy-iph: Build merged Beads plus Swarmy read model [P1] (open)


```

### swarmy-yyx
```text

🌲 Dependent tree for swarmy-yyx:

swarmy-yyx: Agent-Facing CLI and MCP Surface [P1] (open) [1m[BLOCKED][m
    ├── swarmy-2a5: Implement advisor-style CLI event commands [P1] (open)
    ├── swarmy-36i: Integrate /bead-swarm workflow guidance [P2] (open)
    ├── swarmy-bde: Add CLI equivalent for /bead-swarm instructions [P1] (open)
    ├── swarmy-l2z: Serve MCP write tools for swarm events [P1] (open)
    ├── swarmy-otx: Serve /bead-swarm MCP resource or prompt [P1] (open)
    └── swarmy-vvw: Keep CLI and MCP behavior in parity [P2] (open)


```

### swarmy-t4r
```text

🌲 Dependent tree for swarmy-t4r:

swarmy-t4r: Jazzy Backend API [P1] (open) [1m[BLOCKED][m
    ├── swarmy-4nu: Expose run and swarm list endpoints [P1] (open)
    ├── swarmy-55y: Add local auth and request validation defaults [P1] (open)
    ├── swarmy-el7: Harden repo/db path and MCP trust boundaries [P1] (open)
    ├── swarmy-gyl: Add event cursor endpoint for polling [P2] (open)
    ├── swarmy-s36: Expose bead, agent, and stage detail endpoints [P1] (open)
    └── swarmy-zvh: Scaffold Jazzy server and static app hosting [P1] (open)


```

### swarmy-4pg
```text

🌲 Dependent tree for swarmy-4pg:

swarmy-4pg: Svelte Multi-Swarm Dashboard [P1] (open) [1m[BLOCKED][m
    ├── swarmy-1zi: Build dashboard shell and navigation [P1] (open)
    ├── swarmy-2cz: Display concurrent swarm run overview [P1] (open)
    ├── swarmy-5lt: Add event timeline and failure visibility [P2] (open)
    ├── swarmy-7lo: Show bead stage board for coding and review [P1] (open)
    ├── swarmy-9xh: Handle local token auth in the frontend client [P2] (open)
    └── swarmy-rid: Implement polling refresh without layout shifts [P2] (open)


```

### swarmy-78o
```text

🌲 Dependent tree for swarmy-78o:

swarmy-78o: Verification Operations and Packaging [P1] (open) [1m[BLOCKED][m
    ├── swarmy-1ek: Add CI and release packaging [P2] (open)
    ├── swarmy-3mk: Write production runbook and recovery guide [P2] (open)
    ├── swarmy-513: Add production logging and diagnostics [P2] (open)
    ├── swarmy-9kh: Add focused backend unit and integration tests [P1] (open)
    ├── swarmy-e24: Add full end-to-end first-milestone smoke test [P1] (open)
    └── swarmy-n1s: Add frontend build and UI smoke tests [P1] (open)


```

### swarmy-8t5
```text

🌲 Dependent tree for swarmy-8t5:

swarmy-8t5: Agent Knowledge and Ecosystem Follow-up [P3] (open) [1m[BLOCKED][m
    ├── swarmy-43p: Integrate research notes into contributor context [P3] (open)
    ├── swarmy-9zz: Track upstream request fallbacks [P3] (open)
    ├── swarmy-yuf: Document ecosystem request routing policy [P3] (open)
    └── swarmy-z9e: Add agent-facing project instructions [P2] (open)


```

## Representative bd show outputs

### swarmy-yx5
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

### swarmy-djn
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

### swarmy-iph
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

### swarmy-otx
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

### swarmy-55y
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

### swarmy-7lo
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

### swarmy-e24
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

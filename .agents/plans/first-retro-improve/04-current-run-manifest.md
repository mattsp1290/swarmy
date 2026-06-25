# 04 — Compact current-run manifest (`swarmy summary`)

**Priority:** P1
**Retro origin:**
- Retro 1: "Add a compact `.agents/bead-swarm/latest.md` or `summary.json`
  generated at the end of each iteration with completed beads, merged commit,
  validations, unresolved risks, and recommended next beads."
- Retro 2 (still open): "a compact current-run manifest (no `latest.md`/
  `summary.json`; recovery still means reading history files)."

## Problem (grounded)

Per-iteration history lives under `.agents/bead-swarm/history/iteration-N.json`
(schema `bead-swarm-history-v1`). The exact keys (verified across the 34 history
files) are: `schema_version, iteration, branch, slug, main_branch,
main_branch_source, selected_beads, beads_done, beads_blocked, beads_partial,
merge_target, validation, review_artifacts_local_only, review_blocker_summary,
reviews, status`, with later-iteration additions `degraded_reason, execution_mode,
findings_fixed_re_reviewed, notes, review_assurance, review_mode`. Note `validation`
is a JSON **array** of entries (not a scalar pass/fail), and there is **no**
`beads_open` field — open/ready counts must be computed from `bd`, not read from
history. To recover "where is this run right now / what's next," an agent must read
and reconcile many JSON files.
There is no single compact manifest. This is the #1 unaddressed carry-over across
both retros.

Because swarmy already persists run/event state in SQLite (`src/swarmy_core/
persistence.nim`, `read_model.nim`) and exposes it via CLI/MCP/HTTP, swarmy is the
natural place to *generate* this manifest rather than leaving it to the loop.

## Proposed change

Add a `swarmy summary` command (and matching MCP tool / HTTP endpoint if cheap)
that emits a compact current-run manifest. Two data sources to fold together:

1. **Swarmy's own store** — current run id, latest stage per bead, active agents,
   recent errors (already queried by `doctor`).
2. **The iteration history dir** — `.agents/bead-swarm/history/iteration-*.json`:
   last iteration number, last merged commit/branch, beads_done across the run,
   any `status != complete`, review verdicts.

Output a compact manifest with at least:

- `run_id`, `repo`, `generated_at`
- `last_iteration`, `last_merge_commit`, `main_branch`
- `beads_done` (cumulative), `beads_blocked`/`beads_partial` (from history),
  `beads_open` (computed from `bd ready`/`bd list`, NOT a history field)
- `latest_validation` — a pass/fail summary **derived from the last iteration's
  `validation` array** (it's a list of entries, not a boolean)
- `unresolved_risks` (from `review_blocker_summary` / open partials)
- `recommended_next` (ready non-epic beads — uses the shared epic/task classifier
  **owned by task 03**, see below)

Emit both:
- `--json` for machines, and
- a written `.agents/bead-swarm/latest.md` (+ optionally `summary.json`) so the next
  agent reads ONE file. Regenerate (overwrite) each invocation.

### Implementation pointers

- Add `src/swarmy_cli/summary.nim`, wired through `dispatch.nim` like `doctor`.
- Reuse `read_model.nim` for the live store view and `bd_adapter.nim` for bd data;
  reuse `redactDiagnostic()` for output.
- Parse the history JSON dir with `std/json`; tolerate missing/partial files
  (a run may have zero history files — emit a valid empty-ish manifest, exit 0).
- Add `tests/test_summary.nim` (fixtures: no history, several iterations, an
  in-progress/blocked iteration) modeled on `tests/test_doctor.nim` +
  `tests/test_smoke_harness.nim`.
- **Hard prerequisite — the epic/task classifier is owned by task 03**, not this
  task. Do not re-implement it. Task 03 delivers a shared helper (a `classifyReady`
  proc in `bd_adapter`/`read_model`); this task consumes it for `recommended_next`.
  Land 03 before 04, or have 03's classifier merged first to avoid two agents adding
  colliding helpers.
- This task does **not** add an MCP tool or HTTP endpoint for the summary. Surfacing
  run/review health in the API + dashboard is task 08's job — keep `summary` a CLI +
  generated-file concern here so the API surface is designed once in 08.

### Who writes `latest.md`? (resolved: swarmy writes it)

Default decision: **(a) swarmy writes the derived manifest.** `swarmy summary --write`
generates `.agents/bead-swarm/latest.md` (and optionally `summary.json`); the skill
(task 07) calls it at end of iteration. Rationale: keep generation logic in swarmy
(testable, consistent). This is consistent with the scope split in task 99 — swarmy
only *reads* the history *schema*, but it may *write derived/aggregate* artifacts like
this manifest. `latest.md` is an audit artifact (commit it, not a build product) —
confirm it is NOT matched by any `.gitignore` pattern.

## Acceptance criteria

- `swarmy summary --json` emits a valid manifest reconciling store + history.
- `swarmy summary --write` (or chosen flag) writes `.agents/bead-swarm/latest.md`.
- Works with zero history files (valid empty manifest, exit 0) and with many.
- `recommended_next` excludes epics.
- `tests/test_summary.nim` covers empty / multi-iteration / blocked cases.
- `docs/RUNBOOK.md` documents "recover run state with `swarmy summary`."

## Validation

```sh
nimble build
./swarmy summary --json | jq .
./swarmy summary --write && sed -n '1,40p' .agents/bead-swarm/latest.md
nimble test
```

## Scope / risk

- Read-only with respect to swarmy's store and the history dir (only writes
  `latest.md`/`summary.json`). Must not mutate the SQLite store or history JSON.
- Keep it resilient to malformed history JSON — skip a bad file with a warning, do
  not crash the manifest.

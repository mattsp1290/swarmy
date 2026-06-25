# 03 — `swarmy preflight` loop-readiness command

**Priority:** P1
**Retro origin:** Retro 1, "Add `swarmy preflight ralph` or `swarmy doctor` to
report clean branch state, origin reachability, `reviews/` exclusion, stale
iteration branches, lock files, Beads readiness, and open epic/task mix." Retro 1
also notes `/bead-swarm` and `/ralph` "share branch, review, validation, merge, and
cleanup concerns. Swarmy should provide a common preflight/readiness surface for
both loops."

## Current state (grounded)

`swarmy doctor` already exists (`src/swarmy_cli/doctor.nim`), built in iteration 23.
It checks **repo/run health**: canonical repo path, init status, run ID, db path +
trust, config path, created_at, db presence, recent errors (from the `errors`
table). It is redacted via `redactDiagnostic()` and dispatched in
`src/swarmy_cli/dispatch.nim`.

What doctor does **not** do is the *loop readiness* check the retro asks for. That
checklist is currently performed ad hoc with raw git/bd commands at the end of each
run (see "Checks Performed" in retro 1). It should become a first-class command.

## Proposed change

Add a `swarmy preflight` subcommand (alternatively `swarmy doctor --preflight`;
prefer a distinct subcommand so doctor stays about run health and preflight about
loop readiness). Model it on the existing doctor structure (`CliResult`, redacted
output, exit codes 0/1/2) and the manifest patterns in
`src/swarmy_cli/doctor.nim` + `dispatch.nim`.

Checks to report (each as PASS / WARN / FAIL with a one-line reason), mirroring the
retro's "Checks Performed" list:

1. **Clean working tree** — `git status --porcelain` empty.
2. **On main / expected base** — current branch vs the loop's main branch
   (default `main`; respect a `.ralph` file if present).
3. **Up to date with origin** — `git rev-list --left-right --count
   origin/main...HEAD` or `git pull --ff-only` dry equivalent; report ahead/behind.
4. **Origin reachable** — `git ls-remote --exit-code origin` succeeds.
5. **No stale loop branches** — local + remote `ralph/iteration-*`,
   `bead-swarm/iteration-*`, `bead-swarm/recovery-*` are absent.
6. **No lock file** — `.git/bead-swarm.lock` absent (or report owner token).
7. **`reviews/` excluded** — confirm via `git check-ignore -q reviews/` (covers
   either location). Note swarmy's convention keeps `reviews/` in
   `.git/info/exclude` (it is there today), **not** in the committed `.gitignore` —
   review artifacts are local-only per both retros. Do NOT "fix" a passing repo by
   adding `reviews/` to the tracked `.gitignore`.
8. **Beads readiness** — `bd ready --json` succeeds and returns ≥1 actionable item.
9. **Epic/task mix** — count how many ready items are epics vs concrete
   tasks/features/chores, so the loop can warn when only epics are ready (ties to
   the recurring "epics in ready queue" papercut). **This check owns the shared
   classifier** that task 04 also consumes — see "Deliverable: shared classifier"
   below.

Output: a human-readable report by default and `--json` for machine consumption
(the loop / a future dashboard tile can consume it). Exit non-zero if any FAIL.

### Deliverable: shared classifier (this task owns it)

Tasks 03 and 04 both need to split ready beads into epics vs concrete work. Build it
ONCE here so the two tasks can't collide:

- Add an explicit helper, e.g. `proc classifyReady(snapshot): tuple[epics,
  concrete: seq[Bead]]`, in `src/swarmy_core/bd_adapter.nim` (or `read_model.nim`).
- **Confirm first** that `bd_adapter.nim` actually parses the bead *type* (epic vs
  task/feature/chore). The retros note `bd ready --no-epics` does not exist upstream,
  so type may not be parsed yet — if so, this is net-new parsing, not pure reuse.
  Add the `type` field to the adapter's parse if missing.
- Give the helper its own unit test (in `tests/test_bd_adapter.nim` or the new
  preflight test). Task 04 consumes this helper and must not re-implement it.

### Implementation pointers

- Add `src/swarmy_cli/preflight.nim` mirroring `doctor.nim`'s shape.
- Wire it into the dispatcher in `src/swarmy_cli/dispatch.nim` (the same place
  `doctor`/`serve`/`mcp` are routed) and `dispatch_types.nim` if a new result shape
  is needed.
- **Git checks are new ground.** `doctor` today reads only the SQLite store + run
  metadata — it does **not** read git refs. Preflight introduces swarmy's first
  git-shelling code path (status, branch, ls-remote, for-each-ref). Keep it strictly
  **read-only** — no `fetch` that rewrites refs, no ref mutation (doctor's iter-23
  "mutated the thing it diagnosed" lesson applies).
- Reuse the shared classifier above for the epic/task mix; reuse `bd_adapter.nim` for
  the bd snapshot rather than duplicating parsing.
- Run all `bd` calls serially (see global beads conventions) — never inside a
  parallel batch.
- Route all output through `redactDiagnostic()` like doctor does (paths, tokens).
- Add `tests/test_preflight.nim` following `tests/test_doctor.nim`'s structure
  (temp repo fixtures via `tests/test_smoke_harness.nim`).

## Acceptance criteria

- `swarmy preflight` prints a clear PASS/WARN/FAIL report covering the 9 checks.
- `swarmy preflight --json` emits structured results.
- Exit code: 0 when ready, 1 when a check FAILs, 2 on bad args (match doctor).
- Output is redacted (no raw tokens / unexpected absolute paths leaked).
- `tests/test_preflight.nim` covers: clean-ready repo, dirty tree, stale branch
  present, lock file present, only-epics-ready.
- The shared `classifyReady` helper exists in `bd_adapter`/`read_model` with its own
  test, and bead `type` is parsed by the adapter.
- Docs updated: `docs/RUNBOOK.md` gains a "preflight before a loop run" section.

## Validation

```sh
nimble build
./swarmy preflight                 # on clean main → all PASS, exit 0
./swarmy preflight --json | jq .
# deliberately dirty the tree / create a fake bead-swarm/iteration-x branch → expect FAIL
nimble test                        # incl. new test_preflight.nim
```

## Scope / risk

- New command; additive, does not change existing doctor behavior.
- Keep git/bd interactions read-only — preflight must never mutate state (no fetch
  that rewrites refs, no bd writes). Doctor already learned this lesson in iter 23
  ("doctor mutated the DB it diagnosed"); do not repeat it.
- If wiring git status into Nim is heavy, it's acceptable to shell out to `git`/`bd`
  and parse, but prefer the existing bd_adapter for bd data.

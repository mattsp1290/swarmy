# /bead-swarm DevEx Retrospective and /ralph Readiness

Date: 2026-06-24
Repo: `swarmy`

## Scope

This note captures lessons from the recent `/bead-swarm` run and records the current repo state for running `/ralph` in the next session.

## What Worked Well

- Branch-per-iteration workflow kept the run recoverable. The merge commits on `main` give clear checkpoints, and the per-iteration history files under `.agents/bead-swarm/history/` provide a useful audit trail.
- Serial Beads operations avoided Dolt/Beads contention. `bd ready`, `bd update`, and `bd close` were safe when kept out of parallel tool calls.
- The validation pattern was strong: Nim tests, frontend build checks, smoke tests, and targeted diff checks caught practical integration issues before merge.
- Closing beads only after merge kept Beads state aligned with repository state.
- The smoke harness work in iteration 21 improved the project’s ability to prove CLI and MCP behavior with repeatable end-to-end coverage.

## Friction Points

- Review dependence was brittle. In iteration 21, subagent usage limits prevented two independent AI reviews, so the parent agent had to use a local fallback. Swarmy should treat this as an explicit degraded review mode rather than an ad hoc exception.
- The ready queue mixes epics and implementation tasks. Autonomous loops need a clear rule to skip epics for direct implementation unless explicitly operating in planning mode.
- Review feedback repeatedly focused on trust-boundary and configuration details. Swarmy should expose these invariants through reusable validation helpers or a doctor/preflight command so each iteration does not rediscover them manually.
- Work on backend auth partially overlapped frontend auth needs, leaving `swarmy-9xh` open. Related beads would benefit from a lightweight "partially satisfied by" note or dependency audit after each merge.
- Nim test runs produced generated binaries and build artifacts that required manual cleanup. This is easy to miss during long autonomous runs.
- Browser/UI validation had a tooling failure earlier in the run, so verification fell back to build and HTTP checks. Swarmy should define an explicit fallback checklist for unavailable browser tooling.
- The skill says the parent should delegate, but the actual run sometimes had to execute work directly due to subagent/tooling constraints. The workflow should document how to proceed when subagents are unavailable or quota-limited.
- Some history records effectively mean "findings fixed; not independently re-reviewed" rather than "approved after re-review." The history schema should distinguish those states.
- Durable iteration history exists, but there is no compact current-run manifest. A next agent must inspect multiple files to recover the high-level state.
- `/bead-swarm` and `/ralph` share branch, review, validation, merge, and cleanup concerns. Swarmy should provide a common preflight/readiness surface for both loops.

## Recommended Swarmy Changes

- Add `swarmy preflight ralph` or `swarmy doctor` to report clean branch state, origin reachability, `reviews/` exclusion, stale iteration branches, lock files, Beads readiness, and open epic/task mix.
- Add a first-class degraded-review state to iteration history: `reviewers_unavailable`, `local_fallback`, `findings_fixed_unreviewed`, and `approved`.
- Add a cleanup command or test-output convention for generated Nim test binaries, `.tsbuildinfo`, and smoke-test artifacts.
- Add a compact `.agents/bead-swarm/latest.md` or `summary.json` generated at the end of each iteration with completed beads, merged commit, validations, unresolved risks, and recommended next beads.
- Make autonomous task selection skip epics by default and prefer concrete ready tasks/features/chores with satisfied dependencies.
- Add documentation that compares `/bead-swarm` and `/ralph`, especially around review artifacts, Beads closure, branch naming, and degraded operation.
- Prioritize existing ready beads that improve future automation: `swarmy-513` for diagnostics/logging, `swarmy-gyl` for event cursor polling, `swarmy-9xh` for frontend auth state handling, and `swarmy-6jm` for local build/run docs.

## /ralph Readiness

Current state is ready for a next-session `/ralph` start:

- Current branch is `main`.
- `main` is clean and up to date with `origin/main`.
- `origin` points to `git@github.com:mattsp1290/swarmy.git`.
- `origin/main` exists and `git pull --ff-only origin main` reports already up to date.
- No `.ralph` file exists, so `/ralph` should default its main branch to `main`.
- No local or remote `ralph/iteration-*`, `bead-swarm/iteration-*`, or `bead-swarm/recovery-*` branches were found.
- No `.git/bead-swarm.lock` file exists.
- `reviews/` is added to `.git/info/exclude` for local-only review artifacts.
- `bd ready --json --limit 20` succeeds.

## Next-Session Notes

Start from:

```sh
git checkout main
git pull --ff-only origin main
```

Then run one of:

```sh
/ralph --single
```

or, for a scoped first iteration:

```sh
/ralph --goal "Handle frontend local token auth and auth failure states"
```

If `/ralph` relies on `bv --robot-triage` and that tool is unavailable in this repo, use the ready Beads queue directly and choose a concrete non-epic task. Good first candidates are:

- `swarmy-9xh`: Handle local token auth in frontend client.
- `swarmy-gyl`: Add event cursor endpoint for polling.
- `swarmy-513`: Add production logging and diagnostics.
- `swarmy-6jm`: Document local build and run workflow.

## Checks Performed

- `git status --short --branch`
- `git remote get-url origin`
- `git ls-remote --exit-code origin refs/heads/main`
- `git pull --ff-only origin main`
- `git for-each-ref --format='%(refname:short)' 'refs/heads/ralph/iteration-*' 'refs/heads/bead-swarm/iteration-*' 'refs/heads/bead-swarm/recovery-*'`
- `git ls-remote --heads origin 'ralph/iteration-*' 'bead-swarm/iteration-*' 'bead-swarm/recovery-*'`
- `git ls-files reviews/`
- `bd ready --json --limit 20`

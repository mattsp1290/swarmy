# 05 — Observe & harden the first GitHub-hosted CI run

**Priority:** P1
**Retro origin:** Retro 2, "Open follow-up": "The new CI workflow runs on push to
`main`; its jobs mirror locally-validated commands but the GitHub-hosted run has
**not been observed** yet — watch the first run and adjust the Nim/Playwright setup
steps if the hosted environment differs."

## Problem (grounded)

`.github/workflows/ci.yml` exists with four jobs — `backend` (choosenim →
`nimble install --depsOnly` → `nimble test` → `nimble build`), `frontend` (Node 22
→ `npm ci` → web build → `node --test` → Playwright UI), `smoke` (full build +
`tests/smoke.sh`), and `package` (build + `scripts/package.sh` + artifact upload).
All steps were validated locally, but the hosted runner has never been confirmed
green. Hosted environments commonly differ in: Nim install via `choosenim`,
Playwright browser/system-dep installation, Node version, and the jazzy-framework
git dependency fetch (pinned commit `a961fd3…`).

This task has two halves: **(A) agent-doable hardening** from reading the workflow,
and **(B) a human/credential-gated observe step**. Do A regardless; B may require the
user.

### Part A — hardening an agent can do without CI access

Review `.github/workflows/ci.yml` against the known hosted-runner pitfalls and fix
what's genuinely missing (do NOT re-add things already present):

- **Nim install determinism** → consider pinning the `choosenim`/Nim version
  explicitly in the `backend`/`smoke` jobs so a hosted `choosenim` change can't drift
  the toolchain.
- **Playwright system deps** → *already handled*: `ci.yml:52` runs
  `npx playwright install --with-deps chromium`. Do **not** re-add `--with-deps`. If
  the UI job later fails on the runner, suspect a missing browser variant or a system
  lib apt/choosenim didn't pull — triage from the log, don't blindly edit.
- **jazzy-framework dependency fetch** → confirm the pinned commit (`a961fd3…`,
  `swarmy.nimble:14`) is reachable from a hosted runner (public repo, no auth) — a
  shallow/clone-depth or network issue here is a plausible `backend`/`smoke` failure.
- **`tests/test_*` binaries dirtying the package step** → addressed by task 01;
  confirm `scripts/package.sh` stages only intended files (allowlist), independent of
  test artifacts.

Part A is complete when the workflow has been audited and any missing hardening is
committed (to a branch — see Scope/risk).

### Part B — observe green (may require the user)

1. Trigger a run: prefer opening a PR to `main` (triggers `ci.yml` on
   `pull_request`) over pushing to `main`. `gh workflow run ci.yml` works if
   `workflow_dispatch` auth is available.
2. Follow + triage: `gh run watch`, `gh run view <id> --log-failed`.
3. Confirm green across all four jobs and record the run URL + date in
   `docs/RELEASING.md`.

**This half needs `gh` auth with access to `mattsp1290/swarmy`.** If that auth is
absent, do NOT fake completion — surface it and ask the user to run `! gh auth login`
(or to trigger/observe the run themselves). Part B must not block the rest of the
plan's Definition of Done; it is the one human-gated item.

## Acceptance criteria

- **Part A:** `ci.yml` audited; any missing hardening committed; no already-present
  step (e.g. `--with-deps`) re-added redundantly.
- **Part B (human-gated):** at least one full `ci.yml` run observed **green** on the
  hosted runner across all four jobs, with the run URL + date recorded in
  `docs/RELEASING.md`. If auth is unavailable, this is explicitly handed to the user
  rather than marked done.

## Validation

```sh
gh workflow run ci.yml      # or push to a branch / open a PR to main
gh run watch
gh run view <id> --log-failed   # triage any red job
```

## Scope / risk

- This is a verification + small-fix task, not a redesign. Do not restructure the
  workflow unless a job genuinely cannot pass as written.
- Requires `gh` auth with repo access (origin is
  `git@github.com:mattsp1290/swarmy.git`). If auth is missing, surface that and
  ask the user to run the `gh` login (`! gh auth login`) rather than guessing.
- Per repo conventions, pushing to `main` needs explicit approval — prefer a branch
  + PR (which also triggers `ci.yml` on `pull_request`) to observe CI without
  touching `main`.

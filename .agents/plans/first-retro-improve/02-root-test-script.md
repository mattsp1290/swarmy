# 02 — Root `npm test` script that runs the real gates

**Priority:** P0 (removes a per-commit `--no-verify` workaround; recorded as a
project memory)
**Retro origin:** Retro 2, "Harness-level commit gate not anticipated by the
skill": a global Claude Code `PreToolUse` hook runs `npm test` on every `git
commit`. This Nim-primary repo has **no root `test` script**, so the hook fails and
every commit needed `--no-verify`.

## Problem (grounded)

`package.json` (root) defines:

```json
"scripts": {
  "build": "nimble build && npm run build --workspace apps/web",
  "build:nim": "nimble build",
  "build:web": "npm run build --workspace apps/web",
  "test:nim": "nimble test",
  "test:web": "npm run test --workspace apps/web",
  "test:ui": "npm run test:ui --workspace apps/web",
  "test:smoke": "tests/smoke.sh"
}
```

There is no plain `"test"` key. `npm test` therefore exits non-zero ("Missing script:
test"), which trips the global pre-commit hook. The existing project memory
(`swarmy-commit-hook-npm-test.md`) documents the `--no-verify` workaround. A root
`test` script that runs the **real** gates fixes the root cause: the hook passes by
actually validating, instead of being bypassed.

## Proposed change

Add a `"test"` script to root `package.json` that runs the fast, deterministic
gates. Recommended composition:

```json
"test": "npm run test:nim && npm run test:web",
"test:all": "npm run test:nim && npm run test:web && npm run test:ui && npm run test:smoke"
```

Rationale for what goes in the default `test`:
- `test:nim` (`nimble test`) and `test:web` (`node --test`) are fast and have no
  browser/network dependency — appropriate for a pre-commit gate.
- `test:ui` (Playwright) and `test:smoke` (full build + e2e shell) are slower and
  heavier; keep them out of the default `test` so commits stay quick, but expose
  them via `test:all` (and they continue to run in CI as separate jobs).

> Decision point for the implementer: if the maintainer wants the pre-commit gate to
> be maximally strict, point `test` at `test:all` instead. Default recommendation is
> the fast pair above — the heavy gates already run in CI (`05-ci-first-run-verification.md`).

## Interaction with task 01

Task 01 ensures `nimble test` leaves no stray binaries. That matters here too: a
pre-commit `npm test` that dirties the tree with `tests/test_*` would create new
friction. Land 01 first (or together).

## Acceptance criteria

- `npm test` at repo root runs Nim + web tests and exits 0 on a healthy tree.
- A normal `git commit` (no `--no-verify`) clears the global hook locally.
- The tree is still clean after the gate runs (depends on task 01).

## Validation

```sh
npm test            # expect exit 0, both suites run
git commit -m ...   # expect the hook to pass without --no-verify
```

## Follow-up bookkeeping

- Update the project memory `swarmy-commit-hook-npm-test.md` once this lands: the
  `--no-verify` workaround is no longer needed (or note the residual cases, e.g. if
  someone still runs `test:all` as the hook and Playwright isn't installed).
- Mention the new `test` / `test:all` scripts in `README.md` and/or `AGENTS.md`
  where build/test commands are listed.

## Scope / risk

- Single-file edit to root `package.json`. Low risk.
- Do not remove the existing granular `test:*` scripts — CI and docs reference them.

# 06 — Docs: loop comparison, browser-validation fallback, review states

**Priority:** P2 (docs; valuable but not blocking)
**Retro origin:**
- Retro 1: "Add documentation that compares `/bead-swarm` and `/ralph`, especially
  around review artifacts, Beads closure, branch naming, and degraded operation."
- Retro 1: "Browser/UI validation had a tooling failure earlier in the run... define
  an explicit fallback checklist for unavailable browser tooling."
- Retro 1: "Add a first-class degraded-review state to iteration history:
  `reviewers_unavailable`, `local_fallback`, `findings_fixed_unreviewed`, and
  `approved`." (The *history schema* part is skill-owned — see task 07 — but the
  human-readable meaning of these states belongs in swarmy docs.)

## Current state (grounded)

`docs/` has `RUNBOOK.md` (ops, MCP config, stage table, recovery), `RELEASING.md`
(CI/release), `ECOSYSTEM.md` (upstream gaps/fallbacks), `mcp-v1.md` (MCP surface).
There is no doc comparing the two loops, no browser-validation fallback checklist,
and the meaning of degraded-review states is undocumented.

## Proposed changes

### A. Loop comparison doc — `docs/LOOPS.md` (new)

A side-by-side of `/bead-swarm` vs `/ralph` as they apply to *this repo*:

| Concern | /bead-swarm | /ralph |
|---|---|---|
| Selection | ready Beads graph (skip epics) | goal/triage-driven |
| Branch naming | `bead-swarm/iteration-N` | `ralph/iteration-N` |
| Review artifacts | `reviews/` (local-only, git-excluded) | same |
| Beads closure | close only after merge | (document actual) |
| Degraded operation | reviewers-unavailable fallback | same |

Pull the concrete facts from the retros and from swarmy's own behavior. Cross-link
from `README.md` and `docs/RUNBOOK.md`. Keep it accurate — per the docs-review
lesson (task 07), every cited command/flag/path must be verified against source.

### B. Browser-validation fallback checklist — add to `docs/RUNBOOK.md`

When Playwright / browser tooling is unavailable, the validation fallback that the
run actually used:

1. `nimble build` + `npm run build --workspace apps/web` (compile/bundle pass).
2. `tests/smoke_serve.sh` / `tests/smoke_e2e.sh` — start the API, `curl`
   `/api/runs` and `/api/runs/:id/events`, assert JSON shape.
3. `node --test` for `apps/web/src/api.test.ts` (client logic without a browser).
4. Explicitly record in the iteration that UI was validated via build+HTTP, **not**
   browser — do not imply browser coverage that didn't run (verification honesty).

### C. Degraded-review state glossary — add to `docs/RUNBOOK.md` (or LOOPS.md)

The **four state names are canonically defined in task 07's `BeadSwarmGuidance`
const** — this doc gives them precise prose definitions and links to 07; do not
introduce a fifth name or diverge from 07's wording:
- `reviewers_unavailable` — could not obtain independent reviews (e.g. quota).
- `local_fallback` — parent/local heuristic review used instead of two independents.
- `findings_fixed_unreviewed` — findings fixed but not independently re-reviewed.
- `approved` — independently approved after (re-)review.

Reconcile with the live history schema, which is NOT identical: it carries
`review_artifacts_local_only` and `review_blocker_summary`, plus the boolean
`findings_fixed_re_reviewed` (added in retro 2 — note the `_re_reviewed` spelling,
distinct from the `findings_fixed_unreviewed` *state* above). The glossary should map
each named state to how it shows up in the schema fields so docs, guidance (07), and
history JSON agree rather than contradict.

## Acceptance criteria

- `docs/LOOPS.md` exists, accurate, cross-linked from README + RUNBOOK.
- `docs/RUNBOOK.md` has a "browser-validation fallback" checklist and a
  degraded-review glossary.
- Every command/flag/path cited is verified to exist in the repo (run them / grep).

## Validation

- Run each command the docs cite; confirm output matches the described behavior.
- `grep` source for every flag/path/stage-name referenced.

## Scope / risk

- Docs only; no code. Lowest risk, but the docs-review profile (task 07) applies:
  verify, don't proofread. Inaccurate docs are worse than none for autonomous loops.

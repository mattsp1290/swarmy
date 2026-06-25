# 08 — Surface run/review health in the API + dashboard

**Priority:** P1 (this is the retros' loudest theme applied to swarmy's *actual
product*, not just its CLI)
**Retro origin:** Both retros repeatedly stress that swarmy **is the observability
tool** for these loops, and retro 2's single most valuable finding was that the
**dual-review gate caught real defects** (log-injection, a doctor that mutated the DB
it diagnosed, a false-passing smoke test, a dashboard layout shift). Yet none of that
review/health signal is visible in swarmy's web dashboard or HTTP API today.

## Problem (grounded)

- `src/swarmy_core/events.nim` already models `review`, `merge`, `blocked`, and
  `complete` stages. The store + read model persist stage transitions per bead.
- `src/swarmy_server/app.nim` serves run/event/stage data
  (`/api/runs`, `/api/runs/:id/...`), and `apps/web/src/App.svelte` renders the
  dashboard from it.
- But **nothing surfaces review verdicts, REQUEST_CHANGES→fixed→approved cycles,
  degraded-review state, or per-iteration health.** The CLI-side work in tasks 03
  (preflight) and 04 (summary manifest) computes this kind of state, but only for the
  terminal — the dashboard, which is the product, stays blind to it.

Tasks 03/04 make the data *computable*; this task makes it *visible* where swarmy's
value actually lands.

## Proposed change

Design the API surface **once** (tasks 03/04 deliberately defer their MCP/HTTP
surfaces to here), then render it.

1. **API.** Add/extend endpoints in `src/swarmy_server/app.nim` to expose, per run:
   - per-iteration review verdicts (APPROVE / REQUEST_CHANGES) and the
     fixed→re-reviewed→approved progression, sourced from the same data tasks 03/04
     read (the iteration history + the store's `review`/`blocked` stages);
   - degraded-review state (the four states canonicalized in task 07 / glossed in
     task 06);
   - a compact run-health summary (reuse task 04's manifest shape — same generator,
     served over HTTP rather than re-derived).
2. **Dashboard.** Add a review/health tile or column in `apps/web/src/App.svelte`
   that shows, for the active run: current iteration, last review verdict, whether a
   `REQUEST_CHANGES` is outstanding, and degraded-review state when present. Keep it
   consistent with the existing stage-overlay visual language.
3. **Tests.** Extend `tests/test_server_app.nim` for the new endpoint(s);
   `apps/web/src/api.test.ts` for the client; a Playwright assertion in
   `apps/web/tests/` that the review/health tile renders for a run with a
   `REQUEST_CHANGES` iteration.

## Dependencies / sequencing

- Depends on the **data shapes** from task 04 (manifest) and task 06/07 (degraded
  state vocabulary). Land 04 first so the HTTP summary reuses one generator.
- This task is the single home for the summary's HTTP/MCP surface — task 04 explicitly
  does NOT add it.

## Acceptance criteria

- A run's review verdicts + degraded state are queryable via the HTTP API.
- The dashboard shows per-run review/health (verdict, outstanding REQUEST_CHANGES,
  degraded state) using the existing visual language.
- The HTTP summary reuses task 04's generator (no duplicate derivation).
- `test_server_app.nim`, `api.test.ts`, and a Playwright UI assertion cover it.
- `docs/RUNBOOK.md` / `docs/mcp-v1.md` document the new surface.

## Validation

```sh
nimble build && npm run build
./swarmy serve --repo PATH &      # then curl the new endpoint
npm run test --workspace apps/web # node --test
npm run test:ui --workspace apps/web  # Playwright tile assertion
nimble test                        # test_server_app.nim
```

## Scope / risk

- Largest task in the plan; scope it to **read-only surfacing** of state that 03/04
  already compute — do not add new write paths or change how stages are recorded.
- If full dashboard rendering is too large for one iteration, split: ship the API
  endpoint + tests first (agent-doable, testable headless), then the Svelte tile.
- Browser rendering must be verified per the fallback checklist in task 06 if
  Playwright is unavailable (build + HTTP assertions), and reported honestly as such.

# Swarmy Improvements — First Retro Pass

Derived from the two `/bead-swarm` retrospectives in `./.agents/`:

- `bead-swarm-devex-retrospective-2026-06-24.md` (iterations 1–21)
- `bead-swarm-retrospective-2026-06-24-iterations-22-34.md` (graph completion)

## What this plan is

The retros list recommendations that fall into three buckets:

1. **Swarmy (this repo) code/docs/CI/build changes** — concrete improvements to the
   swarmy codebase. **This is what most task files below cover.**
2. **Swarmy's internal `/bead-swarm` skill resource** — swarmy publishes the
   `/bead-swarm` guidance as an MCP resource (`swarmy://guidance/bead-swarm`), an MCP
   prompt, and the `swarmy bead-swarm` command, all from one `BeadSwarmGuidance`
   const. The retros' "skill-level" lessons must flow into THIS copy. **In scope —
   see task 07.** (This is the item the user explicitly flagged.)
3. **The dotfiles `/bead-swarm` skill** — the Claude-Code-side procedure at
   `~/git/dotfiles/.agents/skills/bead-swarm/`. **Out of scope here** — not in this
   repo. Tracked in `99-out-of-scope-skill-changes.md` so nothing is dropped, with
   pointers to where each lesson's durable/swarmy version lives.

Each task file is self-contained and written for another agent to pick up. Every
referenced file path, command, and snippet was verified against the repo on
2026-06-24, so treat them as grounded but re-confirm before editing.

## Why these, framed around swarmy's purpose

Swarmy *is* the observability tool for `/bead-swarm` and `/ralph` runs. Several
recurring friction points in the retros (no compact current-run manifest,
recovering state from many history files, no loop-readiness preflight surface) are
exactly the things swarmy exists to make visible. The highest-leverage items below
push that bookkeeping *into swarmy* instead of leaving it to each loop iteration to
rediscover.

Note that tasks 01–05 improve swarmy's **CLI, build hygiene, and CI**, but the
retros' loudest theme is the *dual-review gate* and observability — which lands in
swarmy's **web dashboard / HTTP API**, the actual product. Task 08 closes that gap;
03 and 04 deliberately defer their HTTP/MCP surfaces to 08 so the API is designed
once.

## Task files (in recommended order)

| # | File | Priority | Retro origin | Cost |
|---|------|----------|--------------|------|
| 01 | `01-test-binary-hygiene.md` | P0 | "Generated Nim test binaries reappear" (both retros) | small |
| 02 | `02-root-test-script.md` | P0 | "Harness-level commit gate not anticipated" (retro 2) | small |
| 03 | `03-swarmy-preflight-command.md` | P1 | "Add `swarmy preflight ralph`" (retro 1) | medium |
| 04 | `04-current-run-manifest.md` | P1 | "compact current-run manifest" (both retros) | medium |
| 05 | `05-ci-first-run-verification.md` | P1 | "CI not yet observed" (retro 2 open follow-up) | small |
| 06 | `06-docs-loop-and-fallbacks.md` | P2 | docs: bead-swarm vs ralph, browser fallback, degraded review | medium |
| 07 | `07-update-internal-bead-swarm-resource.md` | P1 | swarmy's published `/bead-swarm` resource (user-flagged) | medium |
| 08 | `08-surface-review-health-in-product.md` | P1 | review/run-health in dashboard+API (retros' core theme) | large |
| 99 | `99-out-of-scope-skill-changes.md` | — | tracking only (dotfiles skill) | — |

## Suggested execution

P0 items (01, 02) are cheap, high-frequency papercut fixes — do them first and they
can ship as one small iteration. The P1 items have real couplings — they are **not**
all freely parallelizable:

- **03 owns the shared `classifyReady` epic/task helper; 04 depends on it.** Land 03
  (or at least merge its classifier) before 04. Do not parallelize these two blindly
  — both touching `bd_adapter` will collide.
- **04 owns the summary generator; 08 reuses it over HTTP.** Land 04 before 08. 03
  and 04 deliberately do NOT add MCP/HTTP surfaces — 08 designs that once.
- **07 should land after 01 and 02** so the guidance references the real gate, but 07
  references the gate *generically* (no hard-coded script), so the coupling is soft.
- **05 Part A** (workflow hardening) is agent-doable anytime; **05 Part B** (observe
  CI green) is human/credential-gated and must not block the rest.
- **06 (docs) and 07 share the degraded-review vocabulary**; 07's guidance const is
  canonical and 06 links to it.

So a sane order is: 01+02 → 03 → 04 → 08, with 07 after 02, and 05A/06 in parallel
anytime. File one bead per task file (`bd create`) so the work is trackable; group
01+02 into a single bead if preferred.

## Definition of done for the whole plan

- `git status` is clean after `nimble test` (no stray `tests/test_*` binaries).
- A plain `npm test` at repo root runs the real gates and passes, so commits no
  longer need `--no-verify` to clear the global hook.
- A loop-readiness check exists as the `swarmy preflight` command (with tests +
  RUNBOOK docs) — not merely a documented seam.
- A compact current-run manifest is generated/queryable without reading every
  history JSON.
- Review/run-health is visible in swarmy's dashboard + HTTP API (task 08).
- `ci.yml` has been audited and any missing hardening committed (task 05 Part A).
  Observing a green hosted run (Part B) is human-gated and tracked separately — it
  does not block this DoD.
- Docs cover loop comparison + the browser-validation fallback checklist.
- Swarmy's published `/bead-swarm` resource (`BeadSwarmGuidance`, served via CLI +
  MCP resource + MCP prompt) carries the durable retro lessons, with golden tests
  regenerated and green.

# 07 — Update swarmy's internal `/bead-swarm` skill resource

**Priority:** P1 (this is the item the user flagged explicitly)
**Why this matters:** Swarmy is meant to *support* a `/bead-swarm`-style loop AND to
*offer the `/bead-swarm` skill as an MCP resource*. So the lessons the retros labeled
"skill changes" are NOT out of scope — they must flow into swarmy's **internal**
copy of the guidance, which swarmy serves to any agent that asks.

## Current state (grounded)

There is **one** source of truth: `BeadSwarmGuidance` in
`src/swarmy_core/guidance.nim`. It is served three ways:

1. CLI: `swarmy bead-swarm` → `src/swarmy_cli/guidance.nim` returns `BeadSwarmGuidance`.
2. MCP resource: `swarmy://guidance/bead-swarm` (`src/swarmy_cli/mcp_stdio.nim:11`,
   served at lines ~372–412).
3. MCP prompt: `bead-swarm` (same file).

Documented in `docs/mcp-v1.md` (resource + prompt entries).

The current text (26 lines) only covers **how to record state with swarmy** (init →
agent → stage → snapshot). It does **not** capture the loop workflow or the retro
lessons. Since this is what agents pull as "the skill," it should carry the durable,
repo-relevant workflow guidance.

## The two skill copies — keep them distinct

- **The dotfiles skill** (`~/git/dotfiles/.agents/skills/bead-swarm/`) is the
  Claude-Code-side procedure. Editing it is out of scope for *this repo* (it's not
  here). See `99-out-of-scope-skill-changes.md`.
- **Swarmy's internal resource** (`BeadSwarmGuidance`) is in scope and is what this
  task updates. It should be the canonical, tool-agnostic guidance swarmy publishes.

Where the two overlap, swarmy's resource should state the *durable* rules; it should
not encode Claude-Code-only or Codex-only mechanics as requirements.

## Lessons to fold into `BeadSwarmGuidance`

Drawn from the retros' skill-level recommendations, rewritten as durable guidance:

1. **Execution model is orchestrator-agnostic.** State the loop as: select →
   delegate implementation → validate → two independent reviews → fix → re-review →
   merge (no-ff) → record → repeat. Note that "main agent orchestrates and spawns
   worker/reviewer subagents" is a *normal* mode, not degraded — don't frame
   subagent use as a fallback. (Retro 2 rec 1.)
2. **Skip epics at selection.** Prefer concrete ready tasks/features/chores with
   satisfied dependencies; epics are for planning mode only. (Both retros.)
3. **Coupled-bead batching is allowed.** A single serial iteration may close
   several tightly-coupled beads when their write scopes overlap (e.g. docs all
   editing `AGENTS.md`/`README.md`); track per-bead outcomes. Don't force
   one-bead-per-iteration when that causes conflicting edits. (Retro 2 rec 2.)
4. **Run the real project gate regardless of harness hooks.** A global/harness
   pre-commit hook may force `--no-verify`; the orchestrator must still run the true
   gate. Reference the gate **generically** — "run the repo's documented project gate
   (root `package.json` `test` / `test:all`, which wrap `nimble test` + web tests)" —
   rather than hard-coding a specific script name, since task 02 decides which script
   maps to the fast vs full gate. (Retro 2 rec 3.)
5. **Generated-artifact hygiene.** Sweep stray `tests/test_*` binaries / build
   artifacts before staging; stage by allowlist. (After task 01 this is mostly
   automatic — reference it.) (Retro 2 rec 4.)
6. **Focused re-review suffices.** After `REQUEST_CHANGES`, one reviewer verifying
   the specific findings are resolved reaches mutual approval; a full second dual
   pass is overkill. (Retro 2 rec 6.)
7. **Docs iterations are an accuracy-review task.** Reviewers of docs beads must
   *execute* the documented commands and grep source for every cited flag/path/
   stage-name — verify, don't proofread. (Retro 2 rec 7.)
8. **Degraded-review states are explicit.** Name them: `reviewers_unavailable`,
   `local_fallback`, `findings_fixed_unreviewed`, `approved`. **This guidance const is
   the canonical source of these four state names** — task 06's doc glossary links
   here, and task 99 notes the history schema's related boolean
   `findings_fixed_re_reviewed` (already in use since iteration 22). Keep all three in
   agreement: four named states here, the prose glossary in 06, the boolean flag in
   the schema. (Retro 1.)
9. **Close beads only after merge**, keeping Beads canonical (already in the current
   text — preserve it).

Keep the existing swarmy-recording instructions (init/agent/stage/snapshot) — they
are correct and useful; layer the workflow guidance around them.

## Proposed change

- Rewrite `BeadSwarmGuidance` in `src/swarmy_core/guidance.nim` to include the
  workflow + the durable lessons above, while preserving the recording steps.
- Because it's served verbatim via CLI + MCP resource + MCP prompt, **no other code
  changes** are needed for distribution — but verify all three surfaces still emit
  the new text.
- Update `docs/mcp-v1.md` if the resource/prompt description strings change.
- Consider whether the prompt vs resource should differ (resource = full guidance;
  prompt = a short actionable kickoff). If splitting, add a second const rather than
  overloading one. Decision left to implementer; default is keep one shared const.

### Tests — what actually couples to the guidance text

Verified against the suite (do not over-correct here):

- The guidance tests compare against the `BeadSwarmGuidance` **const symbolically**,
  not against a frozen copy of the body, so **editing the const requires NO body
  fixture changes**:
  - `tests/test_cli_dispatch.nim:133` — `check result.output == BeadSwarmGuidance`
  - `tests/test_mcp_stdio.nim:77` and `:87` — `... .getStr == BeadSwarmGuidance`
  - `tests/test_mcp_golden.nim:44` — `normalize()` blanks the guidance body to the
    placeholder `<guidance>` by matching `value.getStr == BeadSwarmGuidance` before
    comparing to the fixture; the fixtures
    (`tests/fixtures/mcp/resources_read.json`, `tests/fixtures/mcp/prompts_get.json`)
    store `"text": "<guidance>"`, not the prose.
- The **only** fixture-coupled surface is the **description strings**, which are NOT
  normalized: the resource description (`mcp_stdio.nim:372`,
  `"Swarmy bead-swarm workflow guidance"`) and the prompt description
  (`prompts_get.json`, `"Instructions for agents recording bead-swarm progress"`). If
  task 07 changes either description string, update `prompts_get.json` (and any
  resource-description fixture) to match. If you only change the guidance *body*, no
  fixture edits are needed.
- Bottom line: just re-run `nimble test` to confirm all three surfaces still emit the
  const. Do not paste the new body into a fixture — that would defeat the
  `<guidance>` normalization the tests are built around.

## Acceptance criteria

- `swarmy bead-swarm`, the `swarmy://guidance/bead-swarm` MCP resource, and the
  `bead-swarm` MCP prompt all emit the updated guidance (same source const).
- The guidance covers lessons 1–9 above in durable, tool-agnostic language.
- Recording instructions (init/agent/stage/snapshot) preserved and still accurate.
- `nimble test` passes unchanged after a body-only edit; if a description string
  changed, the matching fixture is updated and tests pass.
- `docs/mcp-v1.md` consistent with any description changes.

## Validation

```sh
nimble build
./swarmy bead-swarm                       # inspect new guidance
echo '<mcp resources/read for swarmy://guidance/bead-swarm>' # via swarmy mcp / test harness
nimble test                                # golden fixtures must pass
```

## Scope / risk

- Primary edit is one const (`BeadSwarmGuidance`). A body-only change needs no fixture
  edits (see "Tests" above) — the risk is the opposite: don't "regenerate" fixtures
  with the new prose and break the `<guidance>` normalization. Only description-string
  changes touch fixtures.
- Keep guidance accurate to swarmy's actual commands/stages (`coding`, `validation`,
  `review`, `merge`, `blocked`, `complete`) — verify against
  `src/swarmy_core/events.nim`. Inaccurate guidance is worse than terse guidance.

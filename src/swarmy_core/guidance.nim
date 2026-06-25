const BeadSwarmGuidance* = """
# /bead-swarm

Run an autonomous Beads task-graph loop and use Swarmy to make its progress
visible. This guidance is tool-agnostic: it states durable rules, not the
mechanics of any one orchestrator.

## The loop

Each iteration: select -> delegate implementation -> validate -> two independent
reviews -> fix -> re-review -> merge (no-ff) -> record -> repeat, until the ready
graph is empty or a human is needed.

1. **Select.** Take ready beads whose dependencies are satisfied. Prefer concrete
   work — `task`, `feature`, `chore`, `bug`. Skip `epic` beads at selection;
   epics are for planning, not execution. A single serial iteration MAY close
   several tightly-coupled beads together when their write scopes overlap (for
   example several docs beads all editing `AGENTS.md`/`README.md`); track each
   bead's outcome separately rather than forcing one-bead-per-iteration into
   conflicting edits.

2. **Delegate and orchestrate.** A main agent that orchestrates and spawns
   worker and reviewer sub-agents is a NORMAL execution mode, not a degraded one.
   Do not record ordinary sub-agent use as degraded.

3. **Validate with the real project gate.** Run the repository's documented gate
   even if a harness or global pre-commit hook forces a `--no-verify` commit —
   bypassing the hook does not excuse skipping validation. The gate is the root
   `package.json` `test` (fast: `nimble test` + web tests) or `test:all` (adds
   Playwright UI + smoke); run whichever the iteration warrants. Sweep stray
   generated artifacts (for example `tests/test_*` binaries) before staging and
   stage by allowlist; `nimble test` already redirects its binaries into
   `nimcache/`, so a clean checkout stays clean.

4. **Review with two independent reviewers**, then fix and re-review. After a
   `REQUEST_CHANGES`, one reviewer verifying that the specific findings are
   resolved is sufficient to reach mutual approval — a full second dual pass is
   overkill. Docs beads are an ACCURACY review: reviewers must execute every
   documented command and grep source for every cited flag, path, and stage name
   — verify, do not proofread.

5. **Degraded-review states (canonical names).** When independent review cannot
   run normally, record one of these four states (this guidance is the canonical
   source of the names; docs and history schema map onto them):
   - `reviewers_unavailable` — independent reviews could not be obtained (e.g. quota).
   - `local_fallback` — a parent/local heuristic review was used instead of two independents.
   - `findings_fixed_unreviewed` — findings were fixed but not independently re-reviewed.
   - `approved` — independently approved after (re-)review.

6. **Merge, then close.** Merge with `--no-ff` into the main branch, then close
   the beads. Keep Beads as the canonical issue tracker — close a bead only after
   its work is merged, never before.

## Record progress with Swarmy

Swarmy records run-local agent activity and stage overlays so concurrent
bead-swarm work can be observed without changing canonical Beads status early.

1. Initialize the run before writing state:

   `swarmy init --repo PATH`

2. Record the agent before it writes bead progress:

   `swarmy agent --repo PATH --event-id EVENT --agent AGENT_ID --name NAME`

3. Record bead stage transitions with Swarmy stage overlays. Writable stage names are `coding`, `validation`, `review`, `merge`, `blocked`, and `complete`.

   `swarmy stage --repo PATH --event-id EVENT --bead BEAD_ID --stage coding --agent AGENT_ID`
   `swarmy stage --repo PATH --event-id EVENT --bead BEAD_ID --stage review --agent AGENT_ID`
   `swarmy stage --repo PATH --event-id EVENT --bead BEAD_ID --stage merge --agent AGENT_ID`
   `swarmy stage --repo PATH --event-id EVENT --bead BEAD_ID --stage complete --agent AGENT_ID`

4. Fetch the current persisted Swarmy snapshot when another agent needs context:

   Start `swarmy mcp`, then call `swarmy_snapshot` with `{ "repo": "PATH" }`, or use the same persisted SQLite store through Swarmy APIs.

5. Before starting an iteration, run `swarmy preflight` to confirm a clean,
   loop-ready checkout; at the end of an iteration, run `swarmy summary --write`
   to refresh the compact current-run manifest the next iteration reads.

Keep Beads as the canonical issue tracker.
"""

# Loops: `/bead-swarm` vs `/ralph`

Swarmy is the observability tool for autonomous development loops. Two loop
shapes run against this repo. They share most of their branch, review,
validation, merge, and cleanup machinery — `swarmy preflight` and
`swarmy summary` are deliberately loop-agnostic so both can use them. This page
compares them as they apply to **this repository**.

## Side by side

| Concern | `/bead-swarm` | `/ralph` |
|---|---|---|
| Selection | Ready Beads graph; take concrete `task`/`feature`/`chore`/`bug` beads with satisfied deps, skip `epic` beads | Goal/triage-driven: the loop picks the next slice of work toward a stated goal |
| Branch naming | `bead-swarm/iteration-N-<slug>` (recovery branches: `bead-swarm/recovery-*`) | `ralph/iteration-N` |
| Base branch | `main` (recorded per iteration as `main_branch`) | `main` |
| Review artifacts | `reviews/` — local-only, kept in `.git/info/exclude` (NOT the tracked `.gitignore`) | same `reviews/` convention |
| Reviewers | Two independent reviewers; focused single-reviewer re-review after `REQUEST_CHANGES` | same dual-review gate |
| Beads closure | Close a bead only **after** its work merges; Beads stays canonical | Beads (when used) closed post-merge; goal state otherwise tracks the work |
| Merge | `--no-ff` into the base branch | `--no-ff` into the base branch |
| Degraded operation | Named review states (see below); sub-agent orchestration is normal, not degraded | same degraded-review vocabulary |
| Per-iteration record | `.agents/bead-swarm/history/iteration-N.json` (`bead-swarm-history-v1`) | loop-defined |

The durable, tool-agnostic version of the `/bead-swarm` workflow rules is
published by swarmy itself as the `BeadSwarmGuidance` resource — read it with
`swarmy bead-swarm`, or over MCP as the `swarmy://guidance/bead-swarm` resource
and the `bead-swarm` prompt. That guidance is the canonical source for the
loop steps and the degraded-review state names; this page links to it rather than
restating it.

## Shared readiness and recovery surfaces

Both loops should use swarmy's loop-agnostic commands:

- **Before an iteration:** `swarmy preflight --repo .` — clean tree, expected base
  branch, origin sync/reachability, no stale `ralph/iteration-*` /
  `bead-swarm/iteration-*` / `bead-swarm/recovery-*` branches, no
  `.git/bead-swarm.lock`, `reviews/` excluded, and Beads readiness (with an
  epic-only warning). See [RUNBOOK §6](RUNBOOK.md#6-loop-readiness-preflight).
- **After an iteration:** `swarmy summary --write` — refresh the compact
  current-run manifest (`.agents/bead-swarm/latest.md`) so the next iteration
  recovers state from one file. See
  [RUNBOOK §7](RUNBOOK.md#7-recovery).

## Degraded-review states

When two independent reviews cannot run normally, record one of these four
states. The names are **canonically defined** in swarmy's `BeadSwarmGuidance`
resource (`swarmy bead-swarm`); the prose definitions here must not diverge from
or add to that set:

| State | Meaning |
|---|---|
| `reviewers_unavailable` | Independent reviews could not be obtained at all (e.g. reviewer quota exhausted). |
| `local_fallback` | A parent/local heuristic review was used in place of two independent reviewers. |
| `findings_fixed_unreviewed` | Findings were fixed but not independently re-reviewed before merge. |
| `approved` | Independently approved after (re-)review — the normal, non-degraded outcome. |

### How these map onto the history schema

The `bead-swarm-history-v1` iteration files do **not** store a single
`degraded_state` enum; they express the same information across several fields.
Map the named states onto the schema as follows so docs, the published guidance,
and the history JSON agree rather than contradict:

- `review_artifacts_local_only` (bool) — review artifacts stayed in local-only
  `reviews/`; true in normal runs too, so it is not by itself a degraded signal.
- `review_blocker_summary` (string array) — outstanding blockers; non-empty
  corresponds to an unresolved `reviewers_unavailable` / `local_fallback`
  situation.
- `findings_fixed_re_reviewed` (bool, present since iteration 22) — the positive
  counterpart of the `findings_fixed_unreviewed` state: `true` means findings
  were fixed **and** independently re-reviewed (→ `approved`); `false` after
  fixes means `findings_fixed_unreviewed`. Note the spelling difference:
  the schema field is `findings_fixed_re_reviewed`, the state name is
  `findings_fixed_unreviewed`.
- `execution_mode` / `degraded_reason` — record *why* an iteration ran in a
  reduced mode. Ordinary sub-agent orchestration is **not** degraded and should
  not be recorded as such.

## See also

- [`RUNBOOK.md`](RUNBOOK.md) — operating swarmy, preflight, summary, the
  browser-validation fallback, and recovery.
- `swarmy bead-swarm` — the canonical, tool-agnostic loop guidance.

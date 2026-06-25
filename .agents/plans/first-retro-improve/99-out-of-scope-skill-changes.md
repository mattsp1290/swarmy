# 99 — Out-of-scope: the dotfiles `/bead-swarm` skill

Tracking-only. These belong to the **Claude-Code-side skill** at
`~/git/dotfiles/.agents/skills/bead-swarm/`, which is **not in this repo** and is
not editable from a swarmy task. Listed so they aren't silently dropped.

> Important distinction (per the user): swarmy *also* ships an **internal**
> `/bead-swarm` resource (`BeadSwarmGuidance`). Updating that copy **is in scope** —
> see `07-update-internal-bead-swarm-resource.md`. Only the dotfiles procedure file
> itself is out of scope here. Where a lesson applies to both, it appears in 07 (the
> durable, swarmy-published version) and here (the Claude-Code mechanics).

## Skill-mechanics items (dotfiles only)

From retro 2 "Recommended skill changes":

1. Document a Claude Code execution mode (`spawn_agent` vs `Agent` tool); stop
   recording Agent-tool use as `parent-degraded`. *(Durable version → task 07
   lesson 1.)*
2. Bless coupled-bead batching in the procedure. *(Durable version → task 07
   lesson 3.)*
3. Anticipate harness commit gates / `--no-verify`. *(swarmy-side fix → task 02;
   durable note → task 07 lesson 4.)*
4. Generated-artifact cleanup step in the loop. *(swarmy-side fix → task 01;
   durable note → task 07 lesson 5.)*
5. Epic filtering at selection. *(swarmy can help classify → tasks 03/04; durable
   note → task 07 lesson 2.)*
6. Codify focused re-review. *(Durable version → task 07 lesson 6.)*
7. Docs-iteration review profile. *(Durable version → task 07 lesson 7.)*

## Iteration-history schema (lives where the loop writes it)

Retro 1 asked for first-class degraded-review states in the history schema
(`reviewers_unavailable`, `local_fallback`, `findings_fixed_unreviewed`,
`approved`). Retro 2 reports `findings_fixed_re_reviewed` was already added.

- The history JSON files live in **this repo** (`.agents/bead-swarm/history/`), but
  the **writer** is the skill/loop, not swarmy code. If the maintainer wants swarmy
  to own a typed schema (validate/emit history), that would become a new swarmy
  task (a `bead-swarm-history-v2` validator in `src/`). Until then, the schema is
  the skill's concern; swarmy only *reads* it for the manifest (task 04).
- The human-readable meaning of these states is documented swarmy-side in task 06.

## Other retro items routed here

- **"Partially satisfied by" / post-merge dependency audit** (retro 1 friction:
  backend auth partially satisfied frontend auth, leaving `swarmy-9xh` open). The
  retro suggested a lightweight "partially satisfied by" note or a dependency audit
  after each merge. This is primarily a loop/skill concern (the loop decides what to
  re-check after merge), so it lives here. **Partial in-repo mitigation:** task 04's
  manifest already surfaces `beads_partial` and `unresolved_risks` — those can carry
  "related bead X partially satisfied" notes, but swarmy won't *decide* the audit.

- **`bd ready --no-epics` upstream papercut** (retro 2: epics still appear in
  `bd ready`, "unresolved upstream"). The real fix is an upstream `bd` flag or the
  loop filtering once — **out of swarmy's control**. Swarmy's in-repo mitigation is
  to *classify* epics vs concrete beads (tasks 03 + 04's shared `classifyReady`
  helper); it cannot change `bd` itself.

## How to act on these

If you want these handled, edit the dotfiles skill in a separate session scoped to
`~/git/dotfiles`. Do not attempt to edit it from a swarmy working tree.

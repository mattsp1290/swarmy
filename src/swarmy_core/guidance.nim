const BeadSwarmGuidance* = """
# /bead-swarm

Use Swarmy to make bead-swarm progress visible.

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

Keep Beads as the canonical issue tracker. Swarmy records run-local agent activity and stage overlays so concurrent bead-swarm work can be observed without changing canonical Beads status early.
"""

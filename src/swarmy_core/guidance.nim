const BeadSwarmGuidance* = """
# /bead-swarm

Use Swarmy to make bead-swarm progress visible.

1. Initialize the run before writing state:

   `swarmy init --repo PATH`

2. Record the agent before it writes bead progress:

   `swarmy agent --repo PATH --event-id EVENT --agent AGENT_ID --name NAME`

3. Record bead stage transitions during coding, validation, review, merge, and completion:

   `swarmy stage --repo PATH --event-id EVENT --bead BEAD_ID --stage coding --agent AGENT_ID`

4. Fetch the current persisted Swarmy snapshot when another agent needs context:

   `swarmy mcp` exposes `swarmy_snapshot`, or use the same persisted SQLite store through Swarmy APIs.

Keep Beads as the canonical issue tracker. Swarmy records run-local agent activity and stage overlays so concurrent bead-swarm work can be observed without changing canonical Beads status early.
"""

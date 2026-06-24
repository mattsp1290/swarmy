import std/strutils

import swarmy_cli/[event_commands, guidance, init, mcp, serve]
import swarmy_cli/dispatch_types
import swarmy_core/app

proc ok(output = ""): CliResult =
  CliResult(exitCode: 0, output: output)

proc usage*(): string =
  """
swarmy - make bead-swarm runs visible

Usage:
  swarmy --version
  swarmy init [--repo PATH] [--db PATH]
  swarmy event --event-id ID --type TYPE [options]
  swarmy stage --event-id ID --bead ID --stage NAME [options]
  swarmy agent --event-id ID --agent ID --name NAME [options]
  swarmy snapshot --source SOURCE --snapshot-json JSON [options]
  swarmy bead-swarm
  swarmy serve
  swarmy mcp
""".strip(leading = false) & "\n"

proc run*(args: seq[string]): CliResult =
  if args.len == 0 or args[0] in ["help", "--help", "-h"]:
    return ok(usage())

  case args[0]
  of "--version", "-v", "version":
    ok(Name & " " & Version & "\n")
  of "init":
    init.run(args[1 .. ^1])
  of "event":
    event_commands.runEvent(args[1 .. ^1])
  of "stage":
    event_commands.runStage(args[1 .. ^1])
  of "agent":
    event_commands.runAgent(args[1 .. ^1])
  of "snapshot":
    event_commands.runSnapshot(args[1 .. ^1])
  of "bead-swarm":
    guidance.run(args[1 .. ^1])
  of "serve":
    serve.run(args[1 .. ^1])
  of "mcp":
    mcp.run(args[1 .. ^1])
  else:
    CliResult(
      exitCode: 2,
      error: "swarmy: unknown command '" & args[0] & "'\n\n" & usage()
    )

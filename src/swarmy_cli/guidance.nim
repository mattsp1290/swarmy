import swarmy_core/guidance

import ./dispatch_types

proc run*(args: seq[string]): CliResult =
  if args.len > 0:
    return CliResult(
      exitCode: 2,
      error: "swarmy bead-swarm: unexpected argument '" & args[0] & "'\n"
    )

  CliResult(exitCode: 0, output: BeadSwarmGuidance)

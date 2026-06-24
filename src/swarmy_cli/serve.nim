import swarmy_core/app

import ./dispatch_types

proc run*(args: seq[string]): CliResult =
  if args.len > 0:
    return CliResult(
      exitCode: 2,
      error: "swarmy serve: unexpected argument '" & args[0] & "'\n"
    )

  CliResult(
    exitCode: 0,
    output: Name & " serve: server seam ready\n"
  )

import swarmy_core/app

import ./dispatch_types

proc run*(args: seq[string]): CliResult =
  if args.len > 0:
    return CliResult(
      exitCode: 2,
      error: "swarmy mcp: unexpected argument '" & args[0] & "'\n"
    )

  CliResult(
    exitCode: 0,
    output: Name & " mcp: MCP server seam ready\n"
  )

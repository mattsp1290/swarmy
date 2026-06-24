import std/os

import swarmy_cli/dispatch
import swarmy_cli/mcp_stdio

proc main*() =
  let args = commandLineParams()
  if args.len == 1 and args[0] == "mcp":
    serveMcpStdio()
    quit(0)

  let result = run(args)

  if result.output.len > 0:
    stdout.write(result.output)
  if result.error.len > 0:
    stderr.write(result.error)
  quit(result.exitCode)

when isMainModule:
  main()

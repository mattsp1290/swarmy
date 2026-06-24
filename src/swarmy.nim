import std/os

import swarmy_cli/dispatch

proc main*() =
  let result = run(commandLineParams())

  if result.output.len > 0:
    stdout.write(result.output)
  if result.error.len > 0:
    stderr.write(result.error)
  quit(result.exitCode)

when isMainModule:
  main()

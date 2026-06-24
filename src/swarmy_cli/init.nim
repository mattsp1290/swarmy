import std/[options, strutils]

import swarmy_cli/dispatch_types
import swarmy_core/run_metadata

type
  InitOptions = object
    repo: string
    db: Option[string]

proc requireValue(args: seq[string], i: int, flag: string): tuple[ok: bool, value: string, error: string] =
  if i + 1 >= args.len or args[i + 1].startsWith("--"):
    return (false, "", "swarmy init: " & flag & " requires a path\n")
  (true, args[i + 1], "")

proc parseArgs(args: seq[string]): tuple[ok: bool, options: InitOptions, error: string] =
  result.options.repo = "."

  var i = 0
  while i < args.len:
    case args[i]
    of "--repo":
      let value = requireValue(args, i, "--repo")
      if not value.ok:
        return (false, result.options, value.error)
      result.options.repo = value.value
      i += 2
    of "--db":
      let value = requireValue(args, i, "--db")
      if not value.ok:
        return (false, result.options, value.error)
      result.options.db = some(value.value)
      i += 2
    else:
      return (false, result.options, "swarmy init: unexpected argument '" & args[i] & "'\n")

  (true, result.options, "")

proc run*(args: seq[string]): CliResult =
  let parsed = parseArgs(args)
  if not parsed.ok:
    return CliResult(exitCode: 2, error: parsed.error)

  try:
    let initialized = initRun(parsed.options.repo, parsed.options.db)
    CliResult(
      exitCode: 0,
      output: "swarmy init: " & initialized.metadata.runId & " " &
        initialized.metadata.repoPath & "\n"
    )
  except CatchableError as err:
    CliResult(exitCode: 1, error: "swarmy init: " & err.msg & "\n")

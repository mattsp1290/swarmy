import std/options

import swarmy_cli/dispatch_types
import swarmy_core/run_metadata

type
  InitOptions = object
    repo: string
    db: Option[string]

proc parseArgs(args: seq[string]): tuple[ok: bool, options: InitOptions, error: string] =
  result.options.repo = "."

  var i = 0
  while i < args.len:
    case args[i]
    of "--repo":
      if i + 1 >= args.len:
        return (false, result.options, "swarmy init: --repo requires a path\n")
      result.options.repo = args[i + 1]
      i += 2
    of "--db":
      if i + 1 >= args.len:
        return (false, result.options, "swarmy init: --db requires a path\n")
      result.options.db = some(args[i + 1])
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

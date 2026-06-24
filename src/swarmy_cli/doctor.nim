import std/[os, strutils]

import tiny_sqlite

import swarmy_cli/dispatch_types
import swarmy_core/diagnostics
import swarmy_core/persistence
import swarmy_core/run_metadata

type
  DoctorOptions = object
    repo: string

proc requireValue(args: seq[string], i: int, flag: string): tuple[ok: bool, value: string, error: string] =
  if i + 1 >= args.len or args[i + 1].startsWith("--"):
    return (false, "", "swarmy doctor: " & flag & " requires a path\n")
  (true, args[i + 1], "")

proc parseArgs(args: seq[string]): tuple[ok: bool, options: DoctorOptions, error: string] =
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
    else:
      return (false, result.options, "swarmy doctor: unexpected argument '" & args[i] & "'\n")

  (true, result.options, "")

proc recentErrorsReport(dbPath: string): string =
  var store = openReadOnlyStore(dbPath)
  try:
    var rows: seq[string]
    for row in store.db.iterate(
      """
      SELECT occurred_at, severity, message
      FROM errors
      ORDER BY occurred_at DESC, error_id DESC
      LIMIT 10
      """
    ):
      rows.add "  " & row["occurred_at"].fromDbValue(string) &
        " [" & row["severity"].fromDbValue(string) & "] " &
        row["message"].fromDbValue(string)
    result = "recent errors: " & $rows.len & "\n"
    for line in rows:
      result.add line & "\n"
  finally:
    store.close()

proc buildReport(repo: string): string =
  result = "swarmy doctor\n"

  let canonical =
    try:
      canonicalRepoPath(repo)
    except CatchableError:
      repo
  result.add "repo: " & canonical & "\n"

  let metaPath = metadataPath(canonical)
  if not fileExists(metaPath):
    result.add "status: not initialized\n"
    return

  result.add "status: initialized\n"
  let metadata = readRunMetadata(metaPath)
  result.add "run_id: " & metadata.runId & "\n"
  result.add "db_path: " & metadata.dbPath & "\n"
  result.add "db_path_trusted: " & $metadata.dbPathTrusted & "\n"
  result.add "config_path: " & metadata.configPath & "\n"
  result.add "created_at: " & metadata.createdAt & "\n"

  let dbExists = fileExists(metadata.dbPath)
  result.add "db_present: " & $dbExists & "\n"

  if dbExists:
    try:
      result.add recentErrorsReport(metadata.dbPath)
    except CatchableError:
      result.add "recent errors: 0\n"
  else:
    result.add "recent errors: 0\n"

proc run*(args: seq[string]): CliResult =
  let parsed = parseArgs(args)
  if not parsed.ok:
    return CliResult(exitCode: 2, error: parsed.error)

  try:
    let report = buildReport(parsed.options.repo)
    CliResult(exitCode: 0, output: redactDiagnostic(report))
  except CatchableError as err:
    CliResult(exitCode: 1, error: "swarmy doctor: " & err.msg & "\n")

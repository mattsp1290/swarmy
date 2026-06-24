import std/[json, options, os, osproc, strutils, times]

const DefaultBdTimeoutMs* = 5000

type
  BdSnapshotErrorKind* = enum
    bdMissing
    bdNotRepository
    bdCommandFailed
    bdTimeout
    bdMalformedOutput
    bdDeletedOrRenamed
    bdStaleSnapshot

  BdSnapshotError* = ref object of CatchableError
    kind*: BdSnapshotErrorKind
    command*: seq[string]
    output*: string
    exitCode*: int

  BdCommandResult* = object
    exitCode*: int
    output*: string
    timedOut*: bool

  BdCommandRunner* = proc(
    repoPath: string,
    args: seq[string],
    timeoutMs: int
  ): BdCommandResult

  BeadSnapshot* = object
    id*: string
    title*: string
    description*: string
    notes*: string
    status*: string
    priority*: int
    issueType*: string
    updatedAt*: string
    closedAt*: Option[string]
    labels*: seq[string]
    rawJson*: JsonNode

proc newBdError(
  kind: BdSnapshotErrorKind,
  command: seq[string],
  output: string,
  exitCode = -1,
  message = ""
): BdSnapshotError =
  let details =
    if message.len > 0:
      message
    elif output.len > 0:
      output
    else:
      $kind
  BdSnapshotError(kind: kind, command: command, output: output, exitCode: exitCode, msg: details)

proc classifyFailure(command: seq[string], output: string, exitCode: int): BdSnapshotError =
  let lowered = output.toLowerAscii()
  if "not a beads" in lowered or "no beads" in lowered or "no .beads" in lowered:
    newBdError(bdNotRepository, command, output, exitCode)
  elif command.len >= 1 and command[0] == "show" and
      ("no issue found" in lowered or "no issues found" in lowered):
    newBdError(bdDeletedOrRenamed, command, output, exitCode)
  else:
    newBdError(bdCommandFailed, command, output, exitCode)

proc isAllowedReadOnlyCommand(args: seq[string]): bool =
  if args == @["list", "--json"]:
    return true
  if args.len == 4 and args[0] == "ready" and args[1] == "--json" and args[2] == "--limit":
    return true
  if args.len == 3 and args[0] == "show" and args[2] == "--json":
    return true

proc tempOutputPath(): string =
  getTempDir() / ("swarmy-bd-" & $getCurrentProcessId() & "-" & $epochTime() & ".out")

proc runBdCommand(repoPath: string, args: seq[string], timeoutMs: int): BdCommandResult =
  if not isAllowedReadOnlyCommand(args):
    raise newBdError(
      bdCommandFailed,
      args,
      "",
      -1,
      "bd command is not allowed by the read-only snapshot adapter"
    )
  if findExe("bd").len == 0:
    raise newBdError(bdMissing, args, "", -1, "bd executable not found")

  let outputPath = tempOutputPath()
  var process: Process
  try:
    process = startProcess(
      "sh",
      workingDir = repoPath,
      args = @["-c", "out=\"$1\"; shift; exec bd \"$@\" > \"$out\" 2>&1", "swarmy-bd", outputPath] & args,
      options = {poUsePath, poStdErrToStdOut}
    )
  except OSError as error:
    raise newBdError(bdMissing, args, error.msg)

  try:
    result.exitCode = process.waitForExit(timeoutMs)
    if process.running():
      process.kill()
      discard process.waitForExit(1000)
      result.timedOut = true
      result.exitCode = -1

    if fileExists(outputPath):
      result.output = readFile(outputPath)
  finally:
    process.close()
    if fileExists(outputPath):
      removeFile(outputPath)

proc optionalString(node: JsonNode, key: string, command: seq[string], default = ""): string =
  if not node.hasKey(key) or node[key].kind == JNull:
    return default
  if node[key].kind != JString:
    raise newBdError(bdMalformedOutput, command, $node, message = "invalid bead field: " & key)
  node[key].getStr

proc optionalInt(node: JsonNode, key: string, command: seq[string], default = 0): int =
  if not node.hasKey(key) or node[key].kind == JNull:
    return default
  if node[key].kind != JInt:
    raise newBdError(bdMalformedOutput, command, $node, message = "invalid bead field: " & key)
  node[key].getInt

proc parseSnapshot(node: JsonNode, command: seq[string]): BeadSnapshot =
  if node.kind != JObject:
    raise newBdError(bdMalformedOutput, command, $node)

  for key in ["id", "title", "status"]:
    if not node.hasKey(key) or node[key].kind != JString:
      raise newBdError(
        bdMalformedOutput,
        command,
        $node,
        message = "missing or invalid bead field: " & key
      )

  result = BeadSnapshot(
    id: node["id"].getStr,
    title: node["title"].getStr,
    description: node.optionalString("description", command),
    notes: node.optionalString("notes", command),
    status: node["status"].getStr,
    priority: node.optionalInt("priority", command),
    issueType: node.optionalString("issue_type", command),
    updatedAt: node.optionalString("updated_at", command),
    closedAt: none(string),
    labels: @[],
    rawJson: node
  )

  if node.hasKey("closed_at"):
    if node["closed_at"].kind == JNull:
      discard
    elif node["closed_at"].kind == JString:
      result.closedAt = some(node["closed_at"].getStr)
    else:
      raise newBdError(bdMalformedOutput, command, $node, message = "invalid bead field: closed_at")

  if node.hasKey("labels"):
    if node["labels"].kind != JArray:
      raise newBdError(bdMalformedOutput, command, $node, message = "labels must be an array")
    for label in node["labels"].items:
      if label.kind != JString:
        raise newBdError(bdMalformedOutput, command, $node, message = "labels must contain strings")
      result.labels.add label.getStr

proc parseSnapshotArray(output: string, command: seq[string]): seq[BeadSnapshot] =
  let root =
    try:
      parseJson(output)
    except JsonParsingError as error:
      raise newBdError(bdMalformedOutput, command, output, message = error.msg)

  if root.kind != JArray:
    raise newBdError(bdMalformedOutput, command, output, message = "bd output must be a JSON array")

  for node in root.items:
    result.add parseSnapshot(node, command)

proc runReadOnlyBd(
  repoPath: string,
  args: seq[string],
  runner: BdCommandRunner,
  timeoutMs: int
): seq[BeadSnapshot] =
  let commandResult = runner(repoPath, args, timeoutMs)
  if commandResult.timedOut:
    raise newBdError(bdTimeout, args, commandResult.output, commandResult.exitCode)
  if commandResult.exitCode != 0:
    raise classifyFailure(args, commandResult.output, commandResult.exitCode)

  parseSnapshotArray(commandResult.output, args)

proc readReadyBeads*(
  repoPath: string,
  runner: BdCommandRunner = runBdCommand,
  timeoutMs = DefaultBdTimeoutMs,
  limit = 100
): seq[BeadSnapshot] =
  runReadOnlyBd(repoPath, @["ready", "--json", "--limit", $limit], runner, timeoutMs)

proc readListedBeads*(
  repoPath: string,
  runner: BdCommandRunner = runBdCommand,
  timeoutMs = DefaultBdTimeoutMs
): seq[BeadSnapshot] =
  runReadOnlyBd(repoPath, @["list", "--json"], runner, timeoutMs)

proc readBead*(
  repoPath: string,
  beadId: string,
  runner: BdCommandRunner = runBdCommand,
  timeoutMs = DefaultBdTimeoutMs,
  minimumUpdatedAt: Option[string] = none(string)
): BeadSnapshot =
  let command = @["show", beadId, "--json"]
  let snapshots = runReadOnlyBd(repoPath, command, runner, timeoutMs)
  for snapshot in snapshots:
    if snapshot.id == beadId:
      if minimumUpdatedAt.isSome:
        if snapshot.updatedAt.len == 0 or snapshot.updatedAt < minimumUpdatedAt.get:
          raise newBdError(
            bdStaleSnapshot,
            command,
            $snapshot.rawJson,
            message = "stale bead snapshot: " & beadId
          )
      return snapshot

  raise newBdError(
    bdDeletedOrRenamed,
    command,
    $snapshots.len,
    message = "bead not found or renamed: " & beadId
  )

import std/[json, options, os, osproc, streams, strutils]

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
  else:
    newBdError(bdCommandFailed, command, output, exitCode)

proc runBdCommand*(repoPath: string, args: seq[string], timeoutMs: int): BdCommandResult =
  if findExe("bd").len == 0:
    raise newBdError(bdMissing, args, "", -1, "bd executable not found")

  var process: Process
  try:
    process = startProcess(
      "bd",
      workingDir = repoPath,
      args = args,
      options = {poUsePath, poStdErrToStdOut}
    )
  except OSError as error:
    raise newBdError(bdMissing, args, error.msg)

  result.exitCode = process.waitForExit(timeoutMs)
  if process.running():
    process.kill()
    discard process.waitForExit(1000)
    result.timedOut = true
    result.exitCode = -1

  result.output = process.outputStream.readAll()
  process.close()

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
    description: node{"description"}.getStr(""),
    notes: node{"notes"}.getStr(""),
    status: node["status"].getStr,
    priority: node{"priority"}.getInt(0),
    issueType: node{"issue_type"}.getStr(""),
    updatedAt: node{"updated_at"}.getStr(""),
    closedAt: none(string),
    labels: @[],
    rawJson: node
  )

  if node.hasKey("closed_at") and node["closed_at"].kind != JNull:
    result.closedAt = some(node["closed_at"].getStr)

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

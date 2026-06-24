import std/[json, options, os, strutils, times]

import tiny_sqlite

import swarmy_core/events
import swarmy_core/persistence
import swarmy_core/run_metadata

import ./dispatch_types

const
  DefaultRepo = "."
  DefaultSource = "swarmy-cli"

type
  CommonOptions = object
    repo: string
    source: string
    at: string
    eventId: Option[string]

proc ok(output = ""): CliResult =
  CliResult(exitCode: 0, output: output)

proc usage(command: string): string =
  case command
  of "event":
    "swarmy event --event-id ID --type TYPE [--bead ID] [--agent ID] [--stage NAME] [--payload-json JSON] [--repo PATH] [--at RFC3339]\n"
  of "stage":
    "swarmy stage --event-id ID --bead ID --stage NAME [--agent ID] [--title TITLE] [--payload-json JSON] [--repo PATH] [--at RFC3339]\n"
  of "agent":
    "swarmy agent --event-id ID --agent ID --name NAME [--kind KIND] [--metadata-json JSON] [--repo PATH] [--at RFC3339]\n"
  of "snapshot":
    "swarmy snapshot --source SOURCE --snapshot-json JSON [--bead ID] [--repo PATH] [--at RFC3339]\n"
  else:
    "swarmy " & command & ": unknown write command\n"

proc requireValue(args: seq[string], i: int, flag, command: string): tuple[ok: bool, value, error: string] =
  if i + 1 >= args.len or args[i + 1].startsWith("--"):
    return (false, "", "swarmy " & command & ": " & flag & " requires a value\n")
  (true, args[i + 1], "")

proc utcNow(): string =
  now().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")

proc validateJson(value, name, command: string): tuple[ok: bool, error: string] =
  try:
    discard parseJson(value)
    (true, "")
  except JsonParsingError as err:
    (false, "swarmy " & command & ": invalid " & name & ": " & err.msg & "\n")

proc loadMetadata(repo: string): RunMetadata =
  let canonical = canonicalRepoPath(repo)
  let path = metadataPath(canonical)
  if not fileExists(path):
    raise newException(ValueError, "run metadata not found; run `swarmy init --repo " & canonical & "` first")
  readRunMetadata(path)

proc ensureRun(store: Store, metadata: RunMetadata) =
  store.db.exec(
    """
    INSERT OR IGNORE INTO runs(run_id, repo_path, created_at, updated_at)
    VALUES(?, ?, ?, ?)
    """,
    metadata.runId,
    metadata.repoPath,
    metadata.createdAt,
    metadata.createdAt
  )

proc withStore(repo: string, body: proc(store: Store, metadata: RunMetadata)) =
  let metadata = loadMetadata(repo)
  var store = initializeStore(metadata.dbPath)
  try:
    store.ensureRun(metadata)
    body(store, metadata)
  finally:
    store.close()

proc parseCommon(
  command: string,
  args: seq[string],
  i: var int,
  common: var CommonOptions
): tuple[handled: bool, ok: bool, error: string] =
  case args[i]
  of "--repo":
    let value = requireValue(args, i, "--repo", command)
    if not value.ok:
      return (true, false, value.error)
    common.repo = value.value
    i += 2
    (true, true, "")
  of "--source":
    let value = requireValue(args, i, "--source", command)
    if not value.ok:
      return (true, false, value.error)
    common.source = value.value
    i += 2
    (true, true, "")
  of "--at":
    let value = requireValue(args, i, "--at", command)
    if not value.ok:
      return (true, false, value.error)
    common.at = value.value
    i += 2
    (true, true, "")
  of "--event-id":
    let value = requireValue(args, i, "--event-id", command)
    if not value.ok:
      return (true, false, value.error)
    common.eventId = some(value.value)
    i += 2
    (true, true, "")
  else:
    (false, true, "")

proc newCommon(): CommonOptions =
  CommonOptions(repo: DefaultRepo, source: DefaultSource, at: utcNow())

proc missing(command, flag: string): CliResult =
  CliResult(
    exitCode: 2,
    error: "swarmy " & command & ": missing " & flag & "\n\n" & usage(command)
  )

proc fail(command: string, err: string): CliResult =
  CliResult(exitCode: 1, error: "swarmy " & command & ": " & err & "\n")

proc runEvent*(args: seq[string]): CliResult =
  var common = newCommon()
  var eventType = ""
  var beadId = none(string)
  var agentId = none(string)
  var stage = none(string)
  var payloadJson = "{}"

  var i = 0
  while i < args.len:
    let parsed = parseCommon("event", args, i, common)
    if parsed.handled:
      if not parsed.ok:
        return CliResult(exitCode: 2, error: parsed.error)
      continue

    case args[i]
    of "--type":
      let value = requireValue(args, i, "--type", "event")
      if not value.ok:
        return CliResult(exitCode: 2, error: value.error)
      eventType = value.value
      i += 2
    of "--bead":
      let value = requireValue(args, i, "--bead", "event")
      if not value.ok:
        return CliResult(exitCode: 2, error: value.error)
      beadId = some(value.value)
      i += 2
    of "--agent":
      let value = requireValue(args, i, "--agent", "event")
      if not value.ok:
        return CliResult(exitCode: 2, error: value.error)
      agentId = some(value.value)
      i += 2
    of "--stage":
      let value = requireValue(args, i, "--stage", "event")
      if not value.ok:
        return CliResult(exitCode: 2, error: value.error)
      try:
        stage = some(parseWritableStage(value.value).stageName)
      except ValueError as err:
        return CliResult(exitCode: 2, error: "swarmy event: " & err.msg & "\n")
      i += 2
    of "--payload-json":
      let value = requireValue(args, i, "--payload-json", "event")
      if not value.ok:
        return CliResult(exitCode: 2, error: value.error)
      let checked = validateJson(value.value, "--payload-json", "event")
      if not checked.ok:
        return CliResult(exitCode: 2, error: checked.error)
      payloadJson = value.value
      i += 2
    else:
      return CliResult(exitCode: 2, error: "swarmy event: unexpected argument '" & args[i] & "'\n")

  if common.eventId.isNone:
    return missing("event", "--event-id")
  if eventType.len == 0:
    return missing("event", "--type")

  try:
    var seq: int64
    withStore common.repo, proc(store: Store, metadata: RunMetadata) =
      seq = store.appendEvent(
        common.eventId.get,
        metadata.runId,
        common.at,
        common.source,
        eventType,
        beadId = beadId,
        agentId = agentId,
        stage = stage,
        payloadJson = payloadJson
      )
    ok("swarmy event: " & common.eventId.get & " seq " & $seq & "\n")
  except CatchableError as err:
    fail("event", err.msg)

proc ensureBead(store: Store, metadata: RunMetadata, beadId, title, at: string) =
  store.db.exec(
    """
    INSERT OR IGNORE INTO beads(run_id, bead_id, title, updated_at)
    VALUES(?, ?, ?, ?)
    """,
    metadata.runId,
    beadId,
    title,
    at
  )

proc runStage*(args: seq[string]): CliResult =
  var common = newCommon()
  var beadId = ""
  var stageName = ""
  var agentId = none(string)
  var title = ""
  var payloadJson = "{}"

  var i = 0
  while i < args.len:
    let parsed = parseCommon("stage", args, i, common)
    if parsed.handled:
      if not parsed.ok:
        return CliResult(exitCode: 2, error: parsed.error)
      continue

    case args[i]
    of "--bead":
      let value = requireValue(args, i, "--bead", "stage")
      if not value.ok:
        return CliResult(exitCode: 2, error: value.error)
      beadId = value.value
      i += 2
    of "--stage":
      let value = requireValue(args, i, "--stage", "stage")
      if not value.ok:
        return CliResult(exitCode: 2, error: value.error)
      stageName = value.value
      i += 2
    of "--agent":
      let value = requireValue(args, i, "--agent", "stage")
      if not value.ok:
        return CliResult(exitCode: 2, error: value.error)
      agentId = some(value.value)
      i += 2
    of "--title":
      let value = requireValue(args, i, "--title", "stage")
      if not value.ok:
        return CliResult(exitCode: 2, error: value.error)
      title = value.value
      i += 2
    of "--payload-json":
      let value = requireValue(args, i, "--payload-json", "stage")
      if not value.ok:
        return CliResult(exitCode: 2, error: value.error)
      let checked = validateJson(value.value, "--payload-json", "stage")
      if not checked.ok:
        return CliResult(exitCode: 2, error: checked.error)
      payloadJson = value.value
      i += 2
    else:
      return CliResult(exitCode: 2, error: "swarmy stage: unexpected argument '" & args[i] & "'\n")

  if common.eventId.isNone:
    return missing("stage", "--event-id")
  if beadId.len == 0:
    return missing("stage", "--bead")
  if stageName.len == 0:
    return missing("stage", "--stage")
  if title.len == 0:
    title = beadId

  try:
    let stage = parseWritableStage(stageName)
    var seq: int64
    withStore common.repo, proc(store: Store, metadata: RunMetadata) =
      store.ensureBead(metadata, beadId, title, common.at)
      seq = store.recordStageEvent(
        common.eventId.get,
        metadata.runId,
        beadId,
        common.at,
        stage,
        agentId = agentId,
        source = common.source,
        payloadJson = payloadJson
      )
    ok("swarmy stage: " & beadId & " " & $stage & " seq " & $seq & "\n")
  except CatchableError as err:
    fail("stage", err.msg)

proc runAgent*(args: seq[string]): CliResult =
  var common = newCommon()
  var agentId = ""
  var name = ""
  var kind = "agent"
  var metadataJson = "{}"

  var i = 0
  while i < args.len:
    let parsed = parseCommon("agent", args, i, common)
    if parsed.handled:
      if not parsed.ok:
        return CliResult(exitCode: 2, error: parsed.error)
      continue

    case args[i]
    of "--agent":
      let value = requireValue(args, i, "--agent", "agent")
      if not value.ok:
        return CliResult(exitCode: 2, error: value.error)
      agentId = value.value
      i += 2
    of "--name":
      let value = requireValue(args, i, "--name", "agent")
      if not value.ok:
        return CliResult(exitCode: 2, error: value.error)
      name = value.value
      i += 2
    of "--kind":
      let value = requireValue(args, i, "--kind", "agent")
      if not value.ok:
        return CliResult(exitCode: 2, error: value.error)
      kind = value.value
      i += 2
    of "--metadata-json":
      let value = requireValue(args, i, "--metadata-json", "agent")
      if not value.ok:
        return CliResult(exitCode: 2, error: value.error)
      let checked = validateJson(value.value, "--metadata-json", "agent")
      if not checked.ok:
        return CliResult(exitCode: 2, error: checked.error)
      metadataJson = value.value
      i += 2
    else:
      return CliResult(exitCode: 2, error: "swarmy agent: unexpected argument '" & args[i] & "'\n")

  if common.eventId.isNone:
    return missing("agent", "--event-id")
  if agentId.len == 0:
    return missing("agent", "--agent")
  if name.len == 0:
    return missing("agent", "--name")

  try:
    var seq: int64
    withStore common.repo, proc(store: Store, metadata: RunMetadata) =
      store.db.exec(
        """
        INSERT INTO agents(agent_id, run_id, name, kind, created_at, updated_at, metadata_json)
        VALUES(?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(agent_id) DO UPDATE SET
          name = excluded.name,
          kind = excluded.kind,
          updated_at = excluded.updated_at,
          metadata_json = excluded.metadata_json
        """,
        agentId,
        metadata.runId,
        name,
        kind,
        common.at,
        common.at,
        metadataJson
      )
      seq = store.appendEvent(
        common.eventId.get,
        metadata.runId,
        common.at,
        common.source,
        "agent.changed",
        agentId = some(agentId),
        payloadJson = metadataJson
      )
    ok("swarmy agent: " & agentId & " seq " & $seq & "\n")
  except CatchableError as err:
    fail("agent", err.msg)

proc runSnapshot*(args: seq[string]): CliResult =
  var common = newCommon()
  common.source = "bd"
  var beadId = none(string)
  var snapshotJson = ""

  var i = 0
  while i < args.len:
    let parsed = parseCommon("snapshot", args, i, common)
    if parsed.handled:
      if not parsed.ok:
        return CliResult(exitCode: 2, error: parsed.error)
      continue

    case args[i]
    of "--bead":
      let value = requireValue(args, i, "--bead", "snapshot")
      if not value.ok:
        return CliResult(exitCode: 2, error: value.error)
      beadId = some(value.value)
      i += 2
    of "--snapshot-json":
      let value = requireValue(args, i, "--snapshot-json", "snapshot")
      if not value.ok:
        return CliResult(exitCode: 2, error: value.error)
      let checked = validateJson(value.value, "--snapshot-json", "snapshot")
      if not checked.ok:
        return CliResult(exitCode: 2, error: checked.error)
      snapshotJson = value.value
      i += 2
    else:
      return CliResult(exitCode: 2, error: "swarmy snapshot: unexpected argument '" & args[i] & "'\n")

  if snapshotJson.len == 0:
    return missing("snapshot", "--snapshot-json")

  try:
    var snapshotId: int64
    withStore common.repo, proc(store: Store, metadata: RunMetadata) =
      store.db.exec(
        """
        INSERT INTO snapshots(run_id, bead_id, captured_at, source, snapshot_json)
        VALUES(?, ?, ?, ?, ?)
        """,
        metadata.runId,
        beadId,
        common.at,
        common.source,
        snapshotJson
      )
      snapshotId = store.db.value("SELECT last_insert_rowid()").get.fromDbValue(int64)
    ok("swarmy snapshot: " & $snapshotId & "\n")
  except CatchableError as err:
    fail("snapshot", err.msg)

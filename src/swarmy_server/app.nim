import std/[json, options, os, strutils]

import jazzy
import tiny_sqlite

import swarmy_core/app as core_app
import swarmy_core/events
import swarmy_core/logging
import swarmy_core/persistence
import swarmy_core/run_metadata
import swarmy_cli/summary

type ServerConfig* = object
  address*: string
  port*: int
  staticDir*: string
  repoPath*: string
  authToken*: string
  maxBodyBytes*: int

const
  DefaultEventPageLimit = 100
  MaxEventPageLimit = 500

var staticRoot = ""
var repoRoot = ""
var apiAuthToken = ""
var apiMaxBodyBytes = 1024 * 1024

proc setStaticRoot(path: string) =
  {.cast(gcsafe).}:
    staticRoot = normalizedPath(absolutePath(path))

proc currentStaticRoot(): string =
  {.cast(gcsafe).}:
    result = staticRoot

proc setRepoRoot(path: string) =
  {.cast(gcsafe).}:
    repoRoot = canonicalRepoPath(path)

proc currentRepoRoot(): string =
  {.cast(gcsafe).}:
    result = repoRoot

proc setApiAuthToken(token: string) =
  {.cast(gcsafe).}:
    apiAuthToken = token

proc currentApiAuthToken(): string =
  {.cast(gcsafe).}:
    result = apiAuthToken

proc setApiMaxBodyBytes(maxBytes: int) =
  {.cast(gcsafe).}:
    apiMaxBodyBytes = maxBytes

proc currentApiMaxBodyBytes(): int =
  {.cast(gcsafe).}:
    result = apiMaxBodyBytes

proc isStrictIpv4Loopback(host: string): bool =
  let parts = host.split(".")
  if parts.len != 4 or parts[0] != "127":
    return false

  for part in parts:
    if part.len == 0:
      return false
    for ch in part:
      if ch < '0' or ch > '9':
        return false
    try:
      let octet = parseInt(part)
      if octet < 0 or octet > 255:
        return false
    except ValueError:
      return false

  true

proc isLoopbackBindAddress*(host: string): bool =
  let normalized = host.strip().toLowerAscii()
  normalized == "localhost" or
    normalized == "::1" or
    normalized == "[::1]" or
    normalized == "0:0:0:0:0:0:0:1" or
    isStrictIpv4Loopback(normalized)

proc validateServerConfig*(config: ServerConfig): tuple[ok: bool, error: string] =
  if config.maxBodyBytes < 0:
    return (
      false,
      "swarmy serve: maxBodyBytes must be zero or greater\n"
    )
  if config.authToken.len == 0 and not isLoopbackBindAddress(config.address):
    return (
      false,
      "swarmy serve: --auth-token or SWARMY_AUTH_TOKEN is required when binding outside loopback\n"
    )
  (true, "")

proc constantTimeEquals(a, b: string): bool =
  if a.len != b.len:
    return false

  var diff = 0
  for i in 0 ..< a.len:
    diff = diff or (ord(a[i]) xor ord(b[i]))
  diff == 0

proc requestToken(ctx: Context): string =
  if ctx.request.headers.hasKey("X-Swarmy-Token"):
    return ctx.request.headers["X-Swarmy-Token"]

  if ctx.request.headers.hasKey("Authorization"):
    let value = ctx.request.headers["Authorization"]
    if value.startsWith("Bearer "):
      return value[7 .. ^1]

  ""

proc isJsonContentType(contentType: string): bool =
  let mediaType = contentType.split(";")[0].strip().toLowerAscii()
  mediaType == "application/json" or
    (mediaType.startsWith("application/") and mediaType.endsWith("+json"))

proc validateApiRequest(ctx: Context): bool =
  let maxBytes = currentApiMaxBodyBytes()
  let contentLength = ctx.request.headers.getOrDefault("Content-Length")
  if maxBytes >= 0 and contentLength.len > 0:
    try:
      if parseInt(contentLength) > maxBytes:
        ctx.status(413).json(%*{
          "error": "payload too large",
          "max_body_bytes": maxBytes
        })
        return false
    except ValueError:
      ctx.status(400).json(%*{"error": "invalid Content-Length"})
      return false

  if maxBytes >= 0 and ctx.request.body.len > maxBytes:
    ctx.status(413).json(%*{
      "error": "payload too large",
      "max_body_bytes": maxBytes
    })
    return false

  let contentType = ctx.request.headers.getOrDefault("Content-Type")
  if ctx.request.body.len > 0 and isJsonContentType(contentType):
    try:
      discard parseJson(ctx.request.body)
    except JsonParsingError:
      ctx.status(400).json(%*{"error": "invalid JSON payload"})
      return false

  let token = currentApiAuthToken()
  if token.len > 0 and not constantTimeEquals(ctx.requestToken(), token):
    ctx.status(401).json(%*{"error": "unauthorized"})
    return false

  true

proc health(ctx: Context) {.gcsafe.} =
  ctx.json(%*{
    "status": "ok",
    "name": core_app.Name,
    "version": core_app.Version
  })

proc authConfig(ctx: Context) {.gcsafe.} =
  ctx.json(%*{
    "auth_required": currentApiAuthToken().len > 0,
    "token_header": "X-Swarmy-Token",
    "bearer_supported": true
  })

proc appIndex(ctx: Context) {.gcsafe.} =
  let indexPath = currentStaticRoot() / "index.html"
  if not fileExists(indexPath):
    ctx.status(404).text("web app build not found: " & indexPath)
    return

  ctx.html(readFile(indexPath))

proc assetContentType(path: string): string =
  case splitFile(path).ext.toLowerAscii()
  of ".css": "text/css"
  of ".js": "text/javascript"
  of ".json": "application/json"
  of ".svg": "image/svg+xml"
  of ".webp": "image/webp"
  of ".png": "image/png"
  of ".jpg", ".jpeg": "image/jpeg"
  else: "application/octet-stream"

proc appAsset(ctx: Context) {.gcsafe.} =
  let filename = ctx.param("file")
  if filename.len == 0 or filename.contains("/") or filename.contains("\\") or
      filename == "." or filename == "..":
    ctx.status(404).text("404 Not Found")
    return

  let assetPath = currentStaticRoot() / "assets" / filename
  if not fileExists(assetPath):
    ctx.status(404).text("404 Not Found")
    return

  ctx.header("Content-Type", assetPath.assetContentType)
  ctx.response.body = readFile(assetPath)

proc readMetadataIfPresent(repoPath: string): Option[RunMetadata] =
  let path = metadataPath(repoPath)
  if not fileExists(path):
    return none(RunMetadata)
  some(readRunMetadata(path))

proc openConfiguredStore(): Option[Store] =
  let metadata = readMetadataIfPresent(currentRepoRoot())
  if metadata.isNone or not fileExists(metadata.get.dbPath):
    return none(Store)

  some(openStore(metadata.get.dbPath))

proc prepareConfiguredStore(repoPath: string) =
  let metadata = readMetadataIfPresent(repoPath)
  if metadata.isNone or not fileExists(metadata.get.dbPath):
    return

  var store = openStore(metadata.get.dbPath)
  try:
    store.initializeSchema()
  finally:
    store.close()

proc runSummary(row: ResultRow): JsonNode =
  %*{
    "run_id": row["run_id"].fromDbValue(string),
    "repo_path": row["repo_path"].fromDbValue(string),
    "status": row["status"].fromDbValue(string),
    "created_at": row["created_at"].fromDbValue(string),
    "updated_at": row["updated_at"].fromDbValue(string),
    "latest_event_at": row["latest_event_at"].fromDbValue(string),
    "bead_count": row["bead_count"].fromDbValue(int64),
    "active_bead_count": row["active_bead_count"].fromDbValue(int64),
    "agent_count": row["agent_count"].fromDbValue(int64),
    "event_count": row["event_count"].fromDbValue(int64),
    "latest_seq": row["latest_seq"].fromDbValue(int64)
  }

proc jsonFromDb(raw: string): JsonNode =
  try:
    parseJson(raw)
  except JsonParsingError:
    %raw

proc optionString(row: ResultRow, column: system.string): Option[system.string] =
  let value = row[column]
  if value.kind == sqliteNull:
    none(system.string)
  else:
    some(value.fromDbValue(system.string))

proc logApiRequest(ctx: Context, runId: string, status: int) =
  {.cast(gcsafe).}:
    emitLog(lvlInfo, "api request", {
      "request_id": ctx.requestId,
      "method": $ctx.request.httpMethod,
      "path": ctx.request.path,
      "run_id": runId,
      "status": $status
    })

proc notFound(ctx: Context, kind, id: string) {.gcsafe.} =
  ctx.status(404).json(%*{"error": kind & " not found", "id": id})

proc findRunSummary(store: Store, runId: string): Option[JsonNode] =
  let row = store.db.one(
    """
    WITH bead_counts AS (
      SELECT run_id,
        COUNT(*) AS bead_count,
        SUM(CASE WHEN status = 'closed' THEN 0 ELSE 1 END) AS active_bead_count
      FROM beads
      WHERE run_id = ?
      GROUP BY run_id
    ),
    agent_counts AS (
      SELECT run_id, COUNT(*) AS agent_count
      FROM agents
      WHERE run_id = ?
      GROUP BY run_id
    ),
    event_counts AS (
      SELECT run_id, COUNT(*) AS event_count, COALESCE(MAX(seq), 0) AS latest_seq,
        COALESCE(MAX(occurred_at), '') AS latest_event_at
      FROM events
      WHERE run_id = ?
      GROUP BY run_id
    )
    SELECT r.run_id, r.repo_path, r.status, r.created_at, r.updated_at,
      COALESCE(e.latest_event_at, r.updated_at) AS latest_event_at,
      COALESCE(b.bead_count, 0) AS bead_count,
      COALESCE(b.active_bead_count, 0) AS active_bead_count,
      COALESCE(a.agent_count, 0) AS agent_count,
      COALESCE(e.event_count, 0) AS event_count,
      COALESCE(e.latest_seq, 0) AS latest_seq
    FROM runs r
    LEFT JOIN bead_counts b ON b.run_id = r.run_id
    LEFT JOIN agent_counts a ON a.run_id = r.run_id
    LEFT JOIN event_counts e ON e.run_id = r.run_id
    WHERE r.run_id = ?
    """,
    runId,
    runId,
    runId,
    runId
  )
  if row.isNone:
    return none(JsonNode)

  some(row.get.runSummary())

proc agentSummaryFromRow(row: ResultRow): JsonNode =
  %*{
    "id": row["agent_id"].fromDbValue(string),
    "name": row["name"].fromDbValue(string),
    "kind": row["kind"].fromDbValue(string),
    "created_at": row["created_at"].fromDbValue(string),
    "updated_at": row["updated_at"].fromDbValue(string),
    "metadata": jsonFromDb(row["metadata_json"].fromDbValue(string)),
    "event_count": row["event_count"].fromDbValue(int64),
    "last_event_at": row["last_event_at"].fromDbValue(string)
  }

proc stageNode(row: ResultRow): JsonNode =
  result = %*{
    "event_id": row["event_id"].fromDbValue(string),
    "seq": row["seq"].fromDbValue(int64),
    "occurred_at": row["occurred_at"].fromDbValue(string),
    "stage": row["stage"].fromDbValue(string),
    "payload": jsonFromDb(row["payload_json"].fromDbValue(string))
  }

  let agentId = row.optionString("agent_id")
  if agentId.isSome:
    result["agent"] = %*{
      "id": agentId.get,
      "name": row.optionString("agent_name").get(""),
      "kind": row.optionString("agent_kind").get("")
    }
  else:
    result["agent"] = newJNull()

proc eventNode(row: ResultRow): JsonNode =
  result = %*{
    "event_id": row["event_id"].fromDbValue(string),
    "seq": row["seq"].fromDbValue(int64),
    "occurred_at": row["occurred_at"].fromDbValue(string),
    "source": row["source"].fromDbValue(string),
    "event_type": row["event_type"].fromDbValue(string),
    "payload": jsonFromDb(row["payload_json"].fromDbValue(string))
  }

  let beadId = row.optionString("bead_id")
  result["bead_id"] = if beadId.isSome: %beadId.get else: newJNull()

  let stage = row.optionString("stage")
  result["stage"] = if stage.isSome: %stage.get else: newJNull()

  let agentId = row.optionString("agent_id")
  if agentId.isSome:
    result["agent"] = %*{
      "id": agentId.get,
      "name": row.optionString("agent_name").get(""),
      "kind": row.optionString("agent_kind").get("")
    }
  else:
    result["agent"] = newJNull()

proc parseEventCursor(raw: string): tuple[ok: bool, value: int64] =
  if raw.len == 0:
    return (true, 0'i64)
  try:
    let value = parseBiggestInt(raw)
    if value < 0:
      return (false, 0'i64)
    (true, value)
  except ValueError:
    (false, 0'i64)

proc parseEventLimit(raw: string): tuple[ok: bool, value: int] =
  if raw.len == 0:
    return (true, DefaultEventPageLimit)
  try:
    let value = parseInt(raw)
    if value < 1:
      return (false, 0)
    (true, min(value, MaxEventPageLimit))
  except ValueError:
    (false, 0)

proc latestStageNode(store: Store, runId, beadId: string): Option[JsonNode] =
  let row = store.db.one(
    """
    SELECT e.event_id, e.seq, e.occurred_at, e.stage, e.agent_id,
      e.payload_json, a.name AS agent_name, a.kind AS agent_kind
    FROM events e
    LEFT JOIN agents a ON a.run_id = e.run_id AND a.agent_id = e.agent_id
    WHERE e.run_id = ?
      AND e.bead_id = ?
      AND e.event_type = ?
      AND e.stage IS NOT NULL
    ORDER BY e.seq DESC
    LIMIT 1
    """,
    runId,
    beadId,
    StageEventType
  )
  if row.isNone:
    return none(JsonNode)

  some(row.get.stageNode())

proc beadEventStats(store: Store, runId, beadId: string): tuple[count: int64, lastAt: string] =
  let row = store.db.one(
    """
    SELECT COUNT(*) AS event_count, COALESCE(MAX(occurred_at), '') AS last_event_at
    FROM events
    WHERE run_id = ? AND bead_id = ?
    """,
    runId,
    beadId
  ).get
  result.count = row["event_count"].fromDbValue(int64)
  result.lastAt = row["last_event_at"].fromDbValue(string)

proc beadNode(store: Store, row: ResultRow): JsonNode =
  let runId = row["run_id"].fromDbValue(string)
  let beadId = row["bead_id"].fromDbValue(string)
  let stats = store.beadEventStats(runId, beadId)
  let latest = store.latestStageNode(runId, beadId)
  result = %*{
    "id": beadId,
    "title": row["title"].fromDbValue(string),
    "status": row["status"].fromDbValue(string),
    "status_source": "bd",
    "priority": row["priority"].fromDbValue(int64),
    "issue_type": row["issue_type"].fromDbValue(string),
    "updated_at": row["updated_at"].fromDbValue(string),
    "snapshot": jsonFromDb(row["snapshot_json"].fromDbValue(string)),
    "event_count": stats.count,
    "last_event_at": stats.lastAt
  }

  if latest.isSome:
    let stage = latest.get
    result["current_stage"] = stage
    result["swarm_stage"] = stage["stage"]
    result["stage_event_id"] = stage["event_id"]
    result["stage_seq"] = stage["seq"]
    if stage["stage"].getStr == "blocked":
      result["blocker"] = stage
  else:
    result["current_stage"] = newJNull()

proc runErrors(store: Store, runId: string): JsonNode =
  result = newJArray()
  for row in store.db.iterate(
    """
    SELECT error_id, occurred_at, severity, message, context_json
    FROM errors
    WHERE run_id = ?
    ORDER BY occurred_at DESC, error_id DESC
    LIMIT 20
    """,
    runId
  ):
    result.add %*{
      "id": row["error_id"].fromDbValue(int64),
      "occurred_at": row["occurred_at"].fromDbValue(string),
      "severity": row["severity"].fromDbValue(string),
      "message": row["message"].fromDbValue(string),
      "context": jsonFromDb(row["context_json"].fromDbValue(string))
    }

proc listRuns(ctx: Context) {.gcsafe.} =
  if not validateApiRequest(ctx):
    return

  let repoPath = currentRepoRoot()
  let maybeStore = openConfiguredStore()
  if maybeStore.isNone:
    logApiRequest(ctx, "", 200)
    ctx.json(%*{"source_repo": repoPath, "runs": []})
    return

  var store = maybeStore.get
  defer: store.close()

  var runs = newJArray()
  for row in store.db.iterate(
    """
    WITH bead_counts AS (
      SELECT run_id,
        COUNT(*) AS bead_count,
        SUM(CASE WHEN status = 'closed' THEN 0 ELSE 1 END) AS active_bead_count
      FROM beads
      GROUP BY run_id
    ),
    agent_counts AS (
      SELECT run_id, COUNT(*) AS agent_count
      FROM agents
      GROUP BY run_id
    ),
    event_counts AS (
      SELECT run_id, COUNT(*) AS event_count, COALESCE(MAX(seq), 0) AS latest_seq,
        COALESCE(MAX(occurred_at), '') AS latest_event_at
      FROM events
      GROUP BY run_id
    )
    SELECT r.run_id, r.repo_path, r.status, r.created_at, r.updated_at,
      COALESCE(e.latest_event_at, r.updated_at) AS latest_event_at,
      COALESCE(b.bead_count, 0) AS bead_count,
      COALESCE(b.active_bead_count, 0) AS active_bead_count,
      COALESCE(a.agent_count, 0) AS agent_count,
      COALESCE(e.event_count, 0) AS event_count,
      COALESCE(e.latest_seq, 0) AS latest_seq
    FROM runs r
    LEFT JOIN bead_counts b ON b.run_id = r.run_id
    LEFT JOIN agent_counts a ON a.run_id = r.run_id
    LEFT JOIN event_counts e ON e.run_id = r.run_id
    ORDER BY latest_event_at DESC, r.created_at DESC, r.run_id
    """
  ):
    runs.add row.runSummary()

  logApiRequest(ctx, "", 200)
  ctx.json(%*{"source_repo": repoPath, "runs": runs})

proc runDetail(ctx: Context) {.gcsafe.} =
  if not validateApiRequest(ctx):
    return

  let runId = ctx.param("run_id")
  let maybeStore = openConfiguredStore()
  if maybeStore.isNone:
    logApiRequest(ctx, runId, 404)
    ctx.status(404).json(%*{"error": "run not found", "run_id": runId})
    return

  var store = maybeStore.get
  defer: store.close()

  let summary = store.findRunSummary(runId)
  if summary.isNone:
    logApiRequest(ctx, runId, 404)
    ctx.status(404).json(%*{"error": "run not found", "run_id": runId})
    return

  var payload = summary.get

  var beads = newJArray()
  for bead in store.db.iterate(
    """
    SELECT run_id, bead_id, title, status,
      COALESCE(priority, 0) AS priority,
      COALESCE(issue_type, '') AS issue_type,
      snapshot_json,
      updated_at
    FROM beads
    WHERE run_id = ?
    ORDER BY bead_id
    """,
    runId
  ):
    beads.add store.beadNode(bead)
  payload["beads"] = beads

  var agents = newJArray()
  for agent in store.db.iterate(
    """
    SELECT a.agent_id, a.name, a.kind, a.created_at, a.updated_at, a.metadata_json,
      COUNT(e.event_id) AS event_count,
      COALESCE(MAX(e.occurred_at), '') AS last_event_at
    FROM agents a
    LEFT JOIN events e ON e.run_id = a.run_id AND e.agent_id = a.agent_id
    WHERE a.run_id = ?
    GROUP BY a.agent_id, a.name, a.kind, a.created_at, a.updated_at, a.metadata_json
    ORDER BY a.agent_id
    """,
    runId
  ):
    agents.add agent.agentSummaryFromRow()
  payload["agents"] = agents
  payload["errors"] = store.runErrors(runId)

  logApiRequest(ctx, runId, 200)
  ctx.json(payload)

proc runBeads(ctx: Context) {.gcsafe.} =
  if not validateApiRequest(ctx):
    return

  let runId = ctx.param("run_id")
  let maybeStore = openConfiguredStore()
  if maybeStore.isNone:
    logApiRequest(ctx, runId, 404)
    ctx.status(404).json(%*{"error": "run not found", "run_id": runId})
    return

  var store = maybeStore.get
  defer: store.close()

  if store.findRunSummary(runId).isNone:
    logApiRequest(ctx, runId, 404)
    ctx.status(404).json(%*{"error": "run not found", "run_id": runId})
    return

  var beads = newJArray()
  for row in store.db.iterate(
    """
    SELECT run_id, bead_id, title, status,
      COALESCE(priority, 0) AS priority,
      COALESCE(issue_type, '') AS issue_type,
      snapshot_json,
      updated_at
    FROM beads
    WHERE run_id = ?
    ORDER BY bead_id
    """,
    runId
  ):
    beads.add store.beadNode(row)

  logApiRequest(ctx, runId, 200)
  ctx.json(%*{"run_id": runId, "beads": beads})

proc beadDetail(ctx: Context) {.gcsafe.} =
  if not validateApiRequest(ctx):
    return

  let runId = ctx.param("run_id")
  let beadId = ctx.param("bead_id")
  let maybeStore = openConfiguredStore()
  if maybeStore.isNone:
    logApiRequest(ctx, runId, 404)
    notFound(ctx, "bead", beadId)
    return

  var store = maybeStore.get
  defer: store.close()

  if store.findRunSummary(runId).isNone:
    logApiRequest(ctx, runId, 404)
    ctx.status(404).json(%*{"error": "run not found", "run_id": runId})
    return

  let row = store.db.one(
    """
    SELECT run_id, bead_id, title, status,
      COALESCE(priority, 0) AS priority,
      COALESCE(issue_type, '') AS issue_type,
      snapshot_json,
      updated_at
    FROM beads
    WHERE run_id = ? AND bead_id = ?
    """,
    runId,
    beadId
  )
  if row.isNone:
    logApiRequest(ctx, runId, 404)
    notFound(ctx, "bead", beadId)
    return

  var payload = store.beadNode(row.get)
  var stages = newJArray()
  for stage in store.db.iterate(
    """
    SELECT e.event_id, e.seq, e.occurred_at, e.stage, e.agent_id,
      e.payload_json, a.name AS agent_name, a.kind AS agent_kind
    FROM events e
    LEFT JOIN agents a ON a.run_id = e.run_id AND a.agent_id = e.agent_id
    WHERE e.run_id = ?
      AND e.bead_id = ?
      AND e.event_type = ?
      AND e.stage IS NOT NULL
    ORDER BY e.seq
    """,
    runId,
    beadId,
    StageEventType
  ):
    stages.add stage.stageNode()
  payload["stage_events"] = stages

  logApiRequest(ctx, runId, 200)
  ctx.json(payload)

proc runAgents(ctx: Context) {.gcsafe.} =
  if not validateApiRequest(ctx):
    return

  let runId = ctx.param("run_id")
  let maybeStore = openConfiguredStore()
  if maybeStore.isNone:
    logApiRequest(ctx, runId, 404)
    ctx.status(404).json(%*{"error": "run not found", "run_id": runId})
    return

  var store = maybeStore.get
  defer: store.close()

  if store.findRunSummary(runId).isNone:
    logApiRequest(ctx, runId, 404)
    ctx.status(404).json(%*{"error": "run not found", "run_id": runId})
    return

  var agents = newJArray()
  for row in store.db.iterate(
    """
    SELECT a.agent_id, a.name, a.kind, a.created_at, a.updated_at, a.metadata_json,
      COUNT(e.event_id) AS event_count,
      COALESCE(MAX(e.occurred_at), '') AS last_event_at
    FROM agents a
    LEFT JOIN events e ON e.run_id = a.run_id AND e.agent_id = a.agent_id
    WHERE a.run_id = ?
    GROUP BY a.agent_id, a.name, a.kind, a.created_at, a.updated_at, a.metadata_json
    ORDER BY a.agent_id
    """,
    runId
  ):
    agents.add row.agentSummaryFromRow()

  logApiRequest(ctx, runId, 200)
  ctx.json(%*{"run_id": runId, "agents": agents})

proc agentDetail(ctx: Context) {.gcsafe.} =
  if not validateApiRequest(ctx):
    return

  let runId = ctx.param("run_id")
  let agentId = ctx.param("agent_id")
  let maybeStore = openConfiguredStore()
  if maybeStore.isNone:
    logApiRequest(ctx, runId, 404)
    notFound(ctx, "agent", agentId)
    return

  var store = maybeStore.get
  defer: store.close()

  if store.findRunSummary(runId).isNone:
    logApiRequest(ctx, runId, 404)
    ctx.status(404).json(%*{"error": "run not found", "run_id": runId})
    return

  let row = store.db.one(
    """
    SELECT a.agent_id, a.name, a.kind, a.created_at, a.updated_at, a.metadata_json,
      COUNT(e.event_id) AS event_count,
      COALESCE(MAX(e.occurred_at), '') AS last_event_at
    FROM agents a
    LEFT JOIN events e ON e.run_id = a.run_id AND e.agent_id = a.agent_id
    WHERE a.run_id = ? AND a.agent_id = ?
    GROUP BY a.agent_id, a.name, a.kind, a.created_at, a.updated_at, a.metadata_json
    """,
    runId,
    agentId
  )
  if row.isNone:
    logApiRequest(ctx, runId, 404)
    notFound(ctx, "agent", agentId)
    return

  var payload = row.get.agentSummaryFromRow()
  var currentBeads = newJArray()
  for bead in store.db.iterate(
    """
    SELECT e.bead_id, COALESCE(b.title, e.bead_id) AS title,
      COALESCE(b.status, 'unknown') AS status, e.stage, e.occurred_at,
      e.event_id, e.seq
    FROM events e
    INNER JOIN (
      SELECT bead_id, MAX(seq) AS seq
      FROM events
      WHERE run_id = ?
        AND event_type = ?
        AND bead_id IS NOT NULL
        AND stage IS NOT NULL
      GROUP BY bead_id
    ) latest ON latest.bead_id = e.bead_id AND latest.seq = e.seq
    LEFT JOIN beads b ON b.run_id = e.run_id AND b.bead_id = e.bead_id
    WHERE e.run_id = ? AND e.agent_id = ?
    ORDER BY e.seq DESC
    """,
    runId,
    StageEventType,
    runId,
    agentId
  ):
    currentBeads.add %*{
      "id": bead["bead_id"].fromDbValue(string),
      "title": bead["title"].fromDbValue(string),
      "status": bead["status"].fromDbValue(string),
      "stage": bead["stage"].fromDbValue(string),
      "occurred_at": bead["occurred_at"].fromDbValue(string),
      "event_id": bead["event_id"].fromDbValue(string),
      "seq": bead["seq"].fromDbValue(int64)
    }
  payload["current_beads"] = currentBeads

  logApiRequest(ctx, runId, 200)
  ctx.json(payload)

proc runStages(ctx: Context) {.gcsafe.} =
  if not validateApiRequest(ctx):
    return

  let runId = ctx.param("run_id")
  let maybeStore = openConfiguredStore()
  if maybeStore.isNone:
    logApiRequest(ctx, runId, 404)
    ctx.status(404).json(%*{"error": "run not found", "run_id": runId})
    return

  var store = maybeStore.get
  defer: store.close()

  if store.findRunSummary(runId).isNone:
    logApiRequest(ctx, runId, 404)
    ctx.status(404).json(%*{"error": "run not found", "run_id": runId})
    return

  var stages = newJArray()
  for row in store.db.iterate(
    """
    SELECT e.event_id, e.seq, e.occurred_at, e.bead_id, e.stage, e.agent_id,
      e.payload_json, a.name AS agent_name, a.kind AS agent_kind
    FROM events e
    LEFT JOIN agents a ON a.run_id = e.run_id AND a.agent_id = e.agent_id
    WHERE e.run_id = ?
      AND e.event_type = ?
      AND e.stage IS NOT NULL
      AND e.bead_id IS NOT NULL
    ORDER BY e.seq
    """,
    runId,
    StageEventType
  ):
    var node = row.stageNode()
    node["bead_id"] = %row["bead_id"].fromDbValue(string)
    stages.add node

  logApiRequest(ctx, runId, 200)
  ctx.json(%*{"run_id": runId, "stages": stages})

proc runEvents(ctx: Context) {.gcsafe.} =
  if not validateApiRequest(ctx):
    return

  let runId = ctx.param("run_id")

  let cursor = parseEventCursor(ctx.input("after", ""))
  if not cursor.ok:
    logApiRequest(ctx, runId, 400)
    ctx.status(400).json(%*{"error": "invalid cursor", "param": "after"})
    return

  let limit = parseEventLimit(ctx.input("limit", ""))
  if not limit.ok:
    logApiRequest(ctx, runId, 400)
    ctx.status(400).json(%*{"error": "invalid limit", "param": "limit"})
    return

  let maybeStore = openConfiguredStore()
  if maybeStore.isNone:
    logApiRequest(ctx, runId, 404)
    ctx.status(404).json(%*{"error": "run not found", "run_id": runId})
    return

  var store = maybeStore.get
  defer: store.close()

  if store.findRunSummary(runId).isNone:
    logApiRequest(ctx, runId, 404)
    ctx.status(404).json(%*{"error": "run not found", "run_id": runId})
    return

  let latestSeq = store.db.value(
    "SELECT COALESCE(MAX(seq), 0) FROM events WHERE run_id = ?",
    runId
  ).get.fromDbValue(int64)

  # Fetch one extra row to detect whether more events remain past this page.
  var page: seq[JsonNode]
  for row in store.db.iterate(
    """
    SELECT e.event_id, e.seq, e.occurred_at, e.source, e.event_type,
      e.bead_id, e.stage, e.agent_id, e.payload_json,
      a.name AS agent_name, a.kind AS agent_kind
    FROM events e
    LEFT JOIN agents a ON a.run_id = e.run_id AND a.agent_id = e.agent_id
    WHERE e.run_id = ? AND e.seq > ?
    ORDER BY e.seq ASC
    LIMIT ?
    """,
    runId,
    cursor.value,
    limit.value + 1
  ):
    page.add row.eventNode()

  let hasMore = page.len > limit.value
  if hasMore:
    page.setLen(limit.value)

  var events = newJArray()
  for node in page:
    events.add node

  var nextCursor = cursor.value
  if events.len > 0:
    nextCursor = events[^1]["seq"].getBiggestInt
  elif nextCursor > latestSeq:
    # Client over-shot past the head; converge back so polling stays bounded.
    nextCursor = latestSeq

  logApiRequest(ctx, runId, 200)
  ctx.json(%*{
    "run_id": runId,
    "events": events,
    "next_cursor": nextCursor,
    "has_more": hasMore,
    "latest_seq": latestSeq
  })

proc runHealth(ctx: Context) {.gcsafe.} =
  ## Surfaces review/run health for the configured run: the compact summary
  ## manifest (reusing task 04's generator — no re-derivation here) plus the
  ## per-iteration review verdicts and degraded-review signals.
  if not validateApiRequest(ctx):
    return

  let runId = ctx.param("run_id")
  let repo = currentRepoRoot()

  # Health is derived for the configured repo's current run. Serving it for any
  # other run id in the store would return a manifest whose run_id contradicts
  # the requested one, so restrict it to the live run recorded in metadata.
  let metadata = readMetadataIfPresent(repo)
  if metadata.isNone or metadata.get.runId != runId:
    logApiRequest(ctx, runId, 404)
    ctx.status(404).json(%*{"error": "run not found", "run_id": runId})
    return

  let maybeStore = openConfiguredStore()
  if maybeStore.isNone:
    logApiRequest(ctx, runId, 404)
    ctx.status(404).json(%*{"error": "run not found", "run_id": runId})
    return

  var store = maybeStore.get
  defer: store.close()

  if store.findRunSummary(runId).isNone:
    logApiRequest(ctx, runId, 404)
    ctx.status(404).json(%*{"error": "run not found", "run_id": runId})
    return
  var manifestJson: JsonNode
  var iterationsJson: JsonNode
  {.cast(gcsafe).}:
    manifestJson = summary.generateNow(repo).toJson
    iterationsJson = summary.iterationsJson(repo)

  logApiRequest(ctx, runId, 200)
  ctx.json(%*{
    "run_id": runId,
    "summary": manifestJson,
    "iterations": iterationsJson
  })

proc registerRoutes*(
  staticDir: string,
  repoPath = ".",
  authToken = "",
  maxBodyBytes = 1024 * 1024
) =
  setStaticRoot(staticDir)
  setRepoRoot(repoPath)
  setApiAuthToken(authToken)
  setApiMaxBodyBytes(maxBodyBytes)
  Route.get("/api/health", health)
  Route.get("/api/auth", authConfig)
  Route.get("/api/runs", listRuns)
  Route.get("/api/runs/:run_id/beads", runBeads)
  Route.get("/api/runs/:run_id/beads/:bead_id", beadDetail)
  Route.get("/api/runs/:run_id/agents", runAgents)
  Route.get("/api/runs/:run_id/agents/:agent_id", agentDetail)
  Route.get("/api/runs/:run_id/stages", runStages)
  Route.get("/api/runs/:run_id/events", runEvents)
  Route.get("/api/runs/:run_id/health", runHealth)
  Route.get("/api/runs/:run_id", runDetail)
  Route.get("/", appIndex)
  Route.get("/assets/:file", appAsset)

proc serve*(config: ServerConfig) =
  let validConfig = validateServerConfig(config)
  if not validConfig.ok:
    raise newException(ValueError, validConfig.error.strip())

  registerRoutes(
    config.staticDir,
    config.repoPath,
    config.authToken,
    config.maxBodyBytes
  )
  prepareConfiguredStore(currentRepoRoot())
  Jazzy.serve(config.port, config.address)

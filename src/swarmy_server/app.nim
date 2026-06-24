import std/[json, options, os, strutils]

import jazzy
import tiny_sqlite

import swarmy_core/app as core_app
import swarmy_core/events
import swarmy_core/persistence
import swarmy_core/run_metadata

type ServerConfig* = object
  address*: string
  port*: int
  staticDir*: string
  repoPath*: string

var staticRoot = ""
var repoRoot = ""

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

proc health(ctx: Context) {.gcsafe.} =
  ctx.json(%*{
    "status": "ok",
    "name": core_app.Name,
    "version": core_app.Version
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
  let repoPath = currentRepoRoot()
  let maybeStore = openConfiguredStore()
  if maybeStore.isNone:
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

  ctx.json(%*{"source_repo": repoPath, "runs": runs})

proc runDetail(ctx: Context) {.gcsafe.} =
  let runId = ctx.param("run_id")
  let maybeStore = openConfiguredStore()
  if maybeStore.isNone:
    ctx.status(404).json(%*{"error": "run not found", "run_id": runId})
    return

  var store = maybeStore.get
  defer: store.close()

  let summary = store.findRunSummary(runId)
  if summary.isNone:
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

  ctx.json(payload)

proc runBeads(ctx: Context) {.gcsafe.} =
  let runId = ctx.param("run_id")
  let maybeStore = openConfiguredStore()
  if maybeStore.isNone:
    ctx.status(404).json(%*{"error": "run not found", "run_id": runId})
    return

  var store = maybeStore.get
  defer: store.close()

  if store.findRunSummary(runId).isNone:
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

  ctx.json(%*{"run_id": runId, "beads": beads})

proc beadDetail(ctx: Context) {.gcsafe.} =
  let runId = ctx.param("run_id")
  let beadId = ctx.param("bead_id")
  let maybeStore = openConfiguredStore()
  if maybeStore.isNone:
    notFound(ctx, "bead", beadId)
    return

  var store = maybeStore.get
  defer: store.close()

  if store.findRunSummary(runId).isNone:
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

  ctx.json(payload)

proc runAgents(ctx: Context) {.gcsafe.} =
  let runId = ctx.param("run_id")
  let maybeStore = openConfiguredStore()
  if maybeStore.isNone:
    ctx.status(404).json(%*{"error": "run not found", "run_id": runId})
    return

  var store = maybeStore.get
  defer: store.close()

  if store.findRunSummary(runId).isNone:
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

  ctx.json(%*{"run_id": runId, "agents": agents})

proc agentDetail(ctx: Context) {.gcsafe.} =
  let runId = ctx.param("run_id")
  let agentId = ctx.param("agent_id")
  let maybeStore = openConfiguredStore()
  if maybeStore.isNone:
    notFound(ctx, "agent", agentId)
    return

  var store = maybeStore.get
  defer: store.close()

  if store.findRunSummary(runId).isNone:
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

  ctx.json(payload)

proc runStages(ctx: Context) {.gcsafe.} =
  let runId = ctx.param("run_id")
  let maybeStore = openConfiguredStore()
  if maybeStore.isNone:
    ctx.status(404).json(%*{"error": "run not found", "run_id": runId})
    return

  var store = maybeStore.get
  defer: store.close()

  if store.findRunSummary(runId).isNone:
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

  ctx.json(%*{"run_id": runId, "stages": stages})

proc registerRoutes*(staticDir: string, repoPath = ".") =
  setStaticRoot(staticDir)
  setRepoRoot(repoPath)
  Route.get("/api/health", health)
  Route.get("/api/runs", listRuns)
  Route.get("/api/runs/:run_id/beads", runBeads)
  Route.get("/api/runs/:run_id/beads/:bead_id", beadDetail)
  Route.get("/api/runs/:run_id/agents", runAgents)
  Route.get("/api/runs/:run_id/agents/:agent_id", agentDetail)
  Route.get("/api/runs/:run_id/stages", runStages)
  Route.get("/api/runs/:run_id", runDetail)
  Route.get("/", appIndex)
  Route.get("/assets/:file", appAsset)

proc serve*(config: ServerConfig) =
  registerRoutes(config.staticDir, config.repoPath)
  prepareConfiguredStore(currentRepoRoot())
  Jazzy.serve(config.port, config.address)

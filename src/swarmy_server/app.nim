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
    "agent_count": row["agent_count"].fromDbValue(int64),
    "event_count": row["event_count"].fromDbValue(int64),
    "latest_seq": row["latest_seq"].fromDbValue(int64)
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
      SELECT run_id, COUNT(*) AS bead_count
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

  let row = store.db.one(
    """
    WITH bead_counts AS (
      SELECT run_id, COUNT(*) AS bead_count
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
    ctx.status(404).json(%*{"error": "run not found", "run_id": runId})
    return

  var payload = row.get.runSummary()

  var beads = newJArray()
  for bead in store.db.iterate(
    """
    SELECT bead_id, title, status,
      COALESCE(priority, 0) AS priority,
      COALESCE(issue_type, '') AS issue_type
    FROM beads
    WHERE run_id = ?
    ORDER BY bead_id
    """,
    runId
  ):
    let beadId = bead["bead_id"].fromDbValue(string)
    let latest = store.latestBeadStage(runId, beadId)
    var node = %*{
      "id": beadId,
      "title": bead["title"].fromDbValue(string),
      "status": bead["status"].fromDbValue(string),
      "priority": bead["priority"].fromDbValue(int64),
      "issue_type": bead["issue_type"].fromDbValue(string)
    }
    if latest.isSome:
      let stage = latest.get
      node["swarm_stage"] = %stage.stage.stageName
      node["stage_event_id"] = %stage.eventId
      node["stage_seq"] = %stage.seq
    beads.add node
  payload["beads"] = beads

  var agents = newJArray()
  for agent in store.db.iterate(
    """
    SELECT agent_id, name, kind
    FROM agents
    WHERE run_id = ?
    ORDER BY agent_id
    """,
    runId
  ):
    agents.add %*{
      "id": agent["agent_id"].fromDbValue(string),
      "name": agent["name"].fromDbValue(string),
      "kind": agent["kind"].fromDbValue(string)
    }
  payload["agents"] = agents

  ctx.json(payload)

proc registerRoutes*(staticDir: string, repoPath = ".") =
  setStaticRoot(staticDir)
  setRepoRoot(repoPath)
  Route.get("/api/health", health)
  Route.get("/api/runs", listRuns)
  Route.get("/api/runs/:run_id", runDetail)
  Route.get("/", appIndex)
  Route.get("/assets/:file", appAsset)

proc serve*(config: ServerConfig) =
  registerRoutes(config.staticDir, config.repoPath)
  prepareConfiguredStore(currentRepoRoot())
  Jazzy.serve(config.port, config.address)

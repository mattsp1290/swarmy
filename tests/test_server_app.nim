import std/[asyncdispatch, httpcore, json, options, os, times, unittest]

import jazzy
import tiny_sqlite

import swarmy_core/app
import swarmy_core/events
import swarmy_core/persistence
import swarmy_core/run_metadata
import swarmy_cli/serve
import swarmy_server/app as server_app

proc withTempDist(body: proc(dir: string)) =
  let dir = getTempDir() / "swarmy-server-test-" & $getCurrentProcessId() &
    "-" & $epochTime().int
  createDir(dir)
  createDir(dir / "assets")
  writeFile(dir / "index.html", "<!doctype html><title>Swarmy</title>")
  writeFile(dir / "assets" / "app.js", "console.log('swarmy');")
  try:
    body(dir)
  finally:
    removeDir(dir)

proc withEmptyTempDir(body: proc(dir: string)) =
  let dir = getTempDir() / "swarmy-server-empty-test-" & $getCurrentProcessId() &
    "-" & $epochTime().int
  createDir(dir)
  try:
    body(dir)
  finally:
    removeDir(dir)

proc withTempRepoAndDist(body: proc(repo, dist, dbPath: string, runId: string)) =
  let repo = getTempDir() / "swarmy-server-repo-test-" & $getCurrentProcessId() &
    "-" & $epochTime().int
  let dist = repo / "dist"
  let dbPath = repo / "swarmy.db"
  createDir(repo)
  createDir(dist)
  createDir(dist / "assets")
  writeFile(dist / "index.html", "<!doctype html><title>Swarmy</title>")
  writeFile(dist / "assets" / "app.js", "console.log('swarmy');")
  try:
    let initialized = initRun(repo, some(dbPath))
    body(repo, dist, dbPath, initialized.metadata.runId)
  finally:
    removeDir(repo)

proc insertRun(store: Store, runId, repoPath, status, createdAt, updatedAt: string) =
  store.db.exec(
    """
    INSERT INTO runs(run_id, repo_path, status, created_at, updated_at)
    VALUES(?, ?, ?, ?, ?)
    """,
    runId,
    repoPath,
    status,
    createdAt,
    updatedAt
  )

proc insertBead(store: Store, runId, beadId, title, status: string) =
  store.db.exec(
    """
    INSERT INTO beads(
      run_id, bead_id, title, status, priority, issue_type, updated_at
    )
    VALUES(?, ?, ?, ?, 1, 'feature', '2026-06-24T00:00:00Z')
    """,
    runId,
    beadId,
    title,
    status
  )

proc insertAgent(store: Store, runId, agentId, name: string) =
  store.db.exec(
    """
    INSERT INTO agents(agent_id, run_id, name, kind, created_at, updated_at)
    VALUES(?, ?, ?, 'agent', '2026-06-24T00:00:00Z', '2026-06-24T00:00:00Z')
    """,
    agentId,
    runId,
    name
  )

proc insertAgent(
  store: Store,
  runId, agentId, name, kind, metadataJson: string
) =
  store.db.exec(
    """
    INSERT INTO agents(
      agent_id, run_id, name, kind, created_at, updated_at, metadata_json
    )
    VALUES(?, ?, ?, ?, '2026-06-24T00:00:00Z', '2026-06-24T00:00:00Z', ?)
    """,
    agentId,
    runId,
    name,
    kind,
    metadataJson
  )

proc dispatchGet(path: string): Context =
  let req = JazzyRequest(
    httpMethod: HttpGet,
    path: path,
    headers: newHttpHeaders()
  )
  result = newContext(req)
  waitFor dispatch(result)

suite "server app":
  test "blocking serve fails fast when web build is missing":
    withEmptyTempDir proc(dir: string) =
      let result = serveBlocking(@[
        "--host", "127.0.0.1",
        "--port", "18081",
        "--static-dir", dir
      ])

      check result.exitCode == 1
      check result.output == ""
      check "web app build not found" in result.error
      check "npm run build --workspace apps/web" in result.error

  test "registers health and static app routes":
    withTempDist proc(dist: string) =
      server_app.registerRoutes(dist)

      let health = dispatchGet("/api/health")
      check health.response.code == 200
      let payload = parseJson(health.response.body)
      check payload["status"].getStr == "ok"
      check payload["name"].getStr == Name
      check payload["version"].getStr == Version

      let index = dispatchGet("/")
      check index.response.code == 200
      check "<title>Swarmy</title>" in index.response.body
      check index.response.headers["Content-Type"] == "text/html"

      let asset = dispatchGet("/assets/app.js")
      check asset.response.code == 200
      check asset.response.headers["Content-Type"] == "text/javascript"
      check asset.response.body == "console.log('swarmy');"

  test "run endpoints stay read-only when configured store is absent":
    withTempRepoAndDist proc(repo, dist, dbPath, runId: string) =
      discard runId
      check not fileExists(dbPath)
      server_app.registerRoutes(dist, repo)

      let runs = dispatchGet("/api/runs")
      check runs.response.code == 200
      let payload = parseJson(runs.response.body)
      check payload["runs"].len == 0

      let detail = dispatchGet("/api/runs/missing-run")
      check detail.response.code == 404
      check not fileExists(dbPath)

  test "lists configured Swarmy runs with aggregate counts":
    withTempRepoAndDist proc(repo, dist, dbPath, runId: string) =
      var store = initializeStore(dbPath)
      try:
        store.insertRun(
          runId,
          repo,
          "active",
          "2026-06-24T00:00:00Z",
          "2026-06-24T00:00:02Z"
        )
        store.insertRun(
          "run-other",
          repo / "other",
          "complete",
          "2026-06-24T00:00:01Z",
          "2026-06-24T00:00:01Z"
        )
        store.insertBead(runId, "swarmy-4nu", "Expose endpoints", "open")
        store.insertBead("run-other", "other-bead", "Other run bead", "open")
        store.insertAgent(runId, "agent-1", "API Agent")
        discard store.recordStageEvent(
          "event-1",
          runId,
          "swarmy-4nu",
          "2026-06-24T00:00:02Z",
          stageCoding
        )
      finally:
        store.close()

      server_app.registerRoutes(dist, repo)

      let runs = dispatchGet("/api/runs")
      check runs.response.code == 200
      let payload = parseJson(runs.response.body)
      check payload["source_repo"].getStr == canonicalRepoPath(repo)
      check payload["runs"].len == 2
      check payload["runs"][0]["run_id"].getStr == runId
      check payload["runs"][0]["latest_event_at"].getStr == "2026-06-24T00:00:02Z"
      check payload["runs"][0]["bead_count"].getInt == 1
      check payload["runs"][0]["agent_count"].getInt == 1
      check payload["runs"][0]["event_count"].getInt == 1
      check payload["runs"][0]["latest_seq"].getInt == 1

  test "returns run details without cross-run bead leakage":
    withTempRepoAndDist proc(repo, dist, dbPath, runId: string) =
      var store = initializeStore(dbPath)
      try:
        store.insertRun(
          runId,
          repo,
          "active",
          "2026-06-24T00:00:00Z",
          "2026-06-24T00:00:02Z"
        )
        store.insertRun(
          "run-other",
          repo / "other",
          "active",
          "2026-06-24T00:00:00Z",
          "2026-06-24T00:00:03Z"
        )
        store.insertBead(runId, "swarmy-4nu", "Expose endpoints", "open")
        store.insertBead("run-other", "other-bead", "Other run bead", "open")
        store.insertAgent(runId, "agent-1", "API Agent")
        discard store.recordStageEvent(
          "event-1",
          runId,
          "swarmy-4nu",
          "2026-06-24T00:00:02Z",
          stageReview
        )
      finally:
        store.close()

      server_app.registerRoutes(dist, repo)

      let detail = dispatchGet("/api/runs/" & runId)
      check detail.response.code == 200
      let payload = parseJson(detail.response.body)
      check payload["run_id"].getStr == runId
      check payload["latest_event_at"].getStr == "2026-06-24T00:00:02Z"
      check payload["beads"].len == 1
      check payload["beads"][0]["id"].getStr == "swarmy-4nu"
      check payload["beads"][0]["swarm_stage"].getStr == "review"
      check payload["agents"].len == 1
      check payload["agents"][0]["id"].getStr == "agent-1"

      let missing = dispatchGet("/api/runs/missing-run")
      check missing.response.code == 404

  test "returns focused bead agent and stage detail endpoints":
    withTempRepoAndDist proc(repo, dist, dbPath, runId: string) =
      var store = initializeStore(dbPath)
      try:
        store.insertRun(
          runId,
          repo,
          "active",
          "2026-06-24T00:00:00Z",
          "2026-06-24T00:00:04Z"
        )
        store.insertRun(
          "run-other",
          repo / "other",
          "active",
          "2026-06-24T00:00:00Z",
          "2026-06-24T00:00:05Z"
        )
        store.insertBead(runId, "swarmy-s36", "Expose detail endpoints", "open")
        store.insertBead(runId, "bd-only", "Discovered from bd", "blocked")
        store.insertBead("run-other", "other-bead", "Other run bead", "open")
        store.insertAgent(
          runId,
          "agent-1",
          "Detail Agent",
          "subagent",
          """{"role":"api"}"""
        )
        discard store.recordStageEvent(
          "event-1",
          runId,
          "swarmy-s36",
          "2026-06-24T00:00:02Z",
          stageCoding,
          agentId = some("agent-1")
        )
        discard store.recordStageEvent(
          "event-2",
          runId,
          "swarmy-s36",
          "2026-06-24T00:00:03Z",
          stageBlocked,
          agentId = some("agent-1"),
          payloadJson = """{"reason":"waiting on review"}"""
        )
        discard store.appendEvent(
          "event-3",
          runId,
          "2026-06-24T00:00:04Z",
          "swarmy",
          "bead.note",
          beadId = some("swarmy-s36")
        )
        discard store.recordStageEvent(
          "event-other",
          "run-other",
          "other-bead",
          "2026-06-24T00:00:04Z",
          stageComplete
        )
        store.db.exec(
          """
          INSERT INTO errors(run_id, occurred_at, severity, message, context_json)
          VALUES(?, '2026-06-24T00:00:04Z', 'error', 'backend failed', '{"step":"api"}')
          """,
          runId
        )
      finally:
        store.close()

      server_app.registerRoutes(dist, repo)

      let detail = dispatchGet("/api/runs/" & runId)
      check detail.response.code == 200
      let detailPayload = parseJson(detail.response.body)
      check detailPayload["beads"].len == 2
      check detailPayload["beads"][0]["current_stage"].kind == JNull
      check detailPayload["beads"][1]["swarm_stage"].getStr == "blocked"
      check detailPayload["beads"][1]["status"].getStr == "open"
      check detailPayload["beads"][1]["last_event_at"].getStr ==
        "2026-06-24T00:00:04Z"
      check detailPayload["beads"][1]["current_stage"]["occurred_at"].getStr ==
        "2026-06-24T00:00:03Z"
      check detailPayload["beads"][1]["current_stage"]["agent"]["id"].getStr ==
        "agent-1"
      check detailPayload["beads"][1]["blocker"]["payload"]["reason"].getStr ==
        "waiting on review"
      check detailPayload["agents"][0]["metadata"]["role"].getStr == "api"
      check detailPayload["errors"][0]["message"].getStr == "backend failed"

      let beads = dispatchGet("/api/runs/" & runId & "/beads")
      check beads.response.code == 200
      let beadsPayload = parseJson(beads.response.body)
      check beadsPayload["beads"].len == 2
      check beadsPayload["beads"][0]["id"].getStr == "bd-only"
      check beadsPayload["beads"][0]["current_stage"].kind == JNull

      let bead = dispatchGet("/api/runs/" & runId & "/beads/swarmy-s36")
      check bead.response.code == 200
      let beadPayload = parseJson(bead.response.body)
      check beadPayload["stage_events"].len == 2
      check beadPayload["stage_events"][0]["stage"].getStr == "coding"
      check beadPayload["stage_events"][1]["payload"]["reason"].getStr ==
        "waiting on review"

      let agent = dispatchGet("/api/runs/" & runId & "/agents/agent-1")
      check agent.response.code == 200
      let agentPayload = parseJson(agent.response.body)
      check agentPayload["metadata"]["role"].getStr == "api"
      check agentPayload["event_count"].getInt == 2
      check agentPayload["current_beads"].len == 1
      check agentPayload["current_beads"][0]["stage"].getStr == "blocked"

      let stages = dispatchGet("/api/runs/" & runId & "/stages")
      check stages.response.code == 200
      let stagesPayload = parseJson(stages.response.body)
      check stagesPayload["stages"].len == 2
      check stagesPayload["stages"][1]["bead_id"].getStr == "swarmy-s36"
      check stagesPayload["stages"][1]["agent"]["id"].getStr == "agent-1"

      let missingAgent = dispatchGet("/api/runs/" & runId & "/agents/missing")
      check missingAgent.response.code == 404

      let missingRunBead = dispatchGet("/api/runs/missing-run/beads/swarmy-s36")
      check missingRunBead.response.code == 404
      check parseJson(missingRunBead.response.body)["run_id"].getStr == "missing-run"

      let missingRunAgent = dispatchGet("/api/runs/missing-run/agents/agent-1")
      check missingRunAgent.response.code == 404
      check parseJson(missingRunAgent.response.body)["run_id"].getStr == "missing-run"

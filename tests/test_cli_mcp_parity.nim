import std/[json, options, os, times, unittest]

import tiny_sqlite

import swarmy_cli/event_commands
import swarmy_cli/mcp_stdio
import swarmy_core/persistence
import swarmy_core/run_metadata

const
  FixedAt = "2026-06-24T00:00:00Z"
  ParitySource = "parity-test"

proc tempRepo(tag: string): string =
  let dir = getTempDir() / "swarmy-parity-" & tag & "-" &
    $getCurrentProcessId() & "-" & $epochTime().int
  if dirExists(dir):
    removeDir(dir)
  createDir(dir)
  dir

proc initRepo(repo: string): RunMetadata =
  initRun(repo).metadata

proc request(id: int, methodName: string, params = newJObject()): string =
  $(%*{
    "jsonrpc": "2.0",
    "id": id,
    "method": methodName,
    "params": params
  })

proc callTool(id: int, name: string, args: JsonNode): string =
  request(id, "tools/call", %*{"name": name, "arguments": args})

proc response(line: string): JsonNode =
  parseJson(handleMcpLine(line).get)

proc toolPayload(node: JsonNode): JsonNode =
  parseJson(node["result"]["content"][0]["text"].getStr())

proc isToolError(node: JsonNode): bool =
  node["result"].hasKey("isError") and node["result"]["isError"].getBool

proc optStr(value: DbValue): JsonNode =
  let opt = value.fromDbValue(Option[string])
  if opt.isSome: %opt.get else: newJNull()

proc eventRow(dbPath: string): JsonNode =
  ## Returns the single events row as a JsonNode with run_id stripped so
  ## records from different repos can be compared for logical equivalence.
  var store = openStore(dbPath)
  try:
    let row = store.db.one(
      """
      SELECT event_id, seq, occurred_at, source, event_type, bead_id,
             agent_id, stage, payload_json
      FROM events
      """
    ).get
    %*{
      "event_id": row["event_id"].fromDbValue(string),
      "seq": row["seq"].fromDbValue(int64),
      "occurred_at": row["occurred_at"].fromDbValue(string),
      "source": row["source"].fromDbValue(string),
      "event_type": row["event_type"].fromDbValue(string),
      "bead_id": optStr(row["bead_id"]),
      "agent_id": optStr(row["agent_id"]),
      "stage": optStr(row["stage"]),
      "payload_json": row["payload_json"].fromDbValue(string)
    }
  finally:
    store.close()

proc beadRow(dbPath, beadId: string): JsonNode =
  var store = openStore(dbPath)
  try:
    let row = store.db.one(
      "SELECT title, status FROM beads WHERE bead_id = ?", beadId
    ).get
    %*{
      "title": row["title"].fromDbValue(string),
      "status": row["status"].fromDbValue(string)
    }
  finally:
    store.close()

proc agentRow(dbPath, agentId: string): JsonNode =
  var store = openStore(dbPath)
  try:
    let row = store.db.one(
      "SELECT name, kind, metadata_json FROM agents WHERE agent_id = ?", agentId
    ).get
    %*{
      "name": row["name"].fromDbValue(string),
      "kind": row["kind"].fromDbValue(string),
      "metadata_json": row["metadata_json"].fromDbValue(string)
    }
  finally:
    store.close()

suite "cli/mcp parity":
  test "stage path persists equivalent event and bead records":
    let repoCli = tempRepo("stage-cli")
    let repoMcp = tempRepo("stage-mcp")
    try:
      let mdCli = initRepo(repoCli)
      let mdMcp = initRepo(repoMcp)

      let cli = runStage(@[
        "--repo", repoCli,
        "--event-id", "evt-stage-1",
        "--bead", "b1",
        "--stage", "coding",
        "--source", ParitySource,
        "--at", FixedAt,
        "--title", "Bead One",
        "--payload-json", "{\"k\":\"v\"}"
      ])
      check cli.exitCode == 0

      let mcp = response(callTool(1, "swarmy_stage", %*{
        "repo": repoMcp,
        "event_id": "evt-stage-1",
        "bead_id": "b1",
        "stage": "coding",
        "source": ParitySource,
        "at": FixedAt,
        "title": "Bead One",
        "payload_json": "{\"k\":\"v\"}"
      }))
      check not mcp.isToolError

      check eventRow(mdCli.dbPath) == eventRow(mdMcp.dbPath)
      check beadRow(mdCli.dbPath, "b1") == beadRow(mdMcp.dbPath, "b1")
    finally:
      removeDir(repoCli)
      removeDir(repoMcp)

  test "agent path persists equivalent event and agent records":
    let repoCli = tempRepo("agent-cli")
    let repoMcp = tempRepo("agent-mcp")
    try:
      let mdCli = initRepo(repoCli)
      let mdMcp = initRepo(repoMcp)

      let cli = runAgent(@[
        "--repo", repoCli,
        "--event-id", "evt-agent-1",
        "--agent", "a1",
        "--name", "Agent One",
        "--kind", "subagent",
        "--source", ParitySource,
        "--at", FixedAt,
        "--metadata-json", "{\"role\":\"impl\"}"
      ])
      check cli.exitCode == 0

      let mcp = response(callTool(1, "swarmy_agent", %*{
        "repo": repoMcp,
        "event_id": "evt-agent-1",
        "agent_id": "a1",
        "name": "Agent One",
        "kind": "subagent",
        "source": ParitySource,
        "at": FixedAt,
        "metadata_json": "{\"role\":\"impl\"}"
      }))
      check not mcp.isToolError

      check eventRow(mdCli.dbPath) == eventRow(mdMcp.dbPath)
      check agentRow(mdCli.dbPath, "a1") == agentRow(mdMcp.dbPath, "a1")
    finally:
      removeDir(repoCli)
      removeDir(repoMcp)

  test "invalid stage is rejected equivalently by both transports":
    let repoCli = tempRepo("bad-cli")
    let repoMcp = tempRepo("bad-mcp")
    try:
      discard initRepo(repoCli)
      discard initRepo(repoMcp)

      let cli = runStage(@[
        "--repo", repoCli,
        "--event-id", "evt-bad-1",
        "--bead", "b1",
        "--stage", "bogus",
        "--source", ParitySource,
        "--at", FixedAt
      ])
      check cli.exitCode == 2

      let mcp = response(callTool(1, "swarmy_stage", %*{
        "repo": repoMcp,
        "event_id": "evt-bad-1",
        "bead_id": "b1",
        "stage": "bogus",
        "source": ParitySource,
        "at": FixedAt
      }))
      check mcp.isToolError
      check mcp.toolPayload["code"].getStr == "invalid_arguments"
    finally:
      removeDir(repoCli)
      removeDir(repoMcp)

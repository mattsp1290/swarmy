import std/[json, options, os, sequtils, strutils, times, unittest]

import tiny_sqlite

import swarmy_cli/mcp_stdio
import swarmy_core/persistence

proc withTempRepo(body: proc(repo, dbPath: string)) =
  let dir = getTempDir() / "swarmy-mcp-test-" & $getCurrentProcessId() &
    "-" & $epochTime().int
  let dbPath = dir / "swarmy.db"
  if dirExists(dir):
    removeDir(dir)
  createDir(dir)
  try:
    body(dir, dbPath)
  finally:
    removeDir(dir)

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

proc scalarInt(store: Store, sql: string): int64 =
  store.db.value(sql).get.fromDbValue(int64)

suite "mcp stdio":
  test "initialize advertises MCP protocol version and tools":
    let initialized = response(request(1, "initialize"))
    check initialized["result"]["protocolVersion"].getStr == McpProtocolVersion

    let listed = response(request(2, "tools/list"))
    let names = listed["result"]["tools"].elems.mapIt(it["name"].getStr)
    check names == @[
      "swarmy_init",
      "swarmy_agent",
      "swarmy_stage",
      "swarmy_snapshot"
    ]

  test "tool calls initialize runs, write events, and fetch snapshots":
    withTempRepo proc(repo, dbPath: string) =
      let initPayload = response(callTool(1, "swarmy_init", %*{
        "repo": repo,
        "db": dbPath
      })).toolPayload
      check initPayload["ok"].getBool

      let agentPayload = response(callTool(2, "swarmy_agent", %*{
        "repo": repo,
        "event_id": "agent-event-1",
        "agent_id": "agent-1",
        "name": "MCP Agent",
        "kind": "subagent",
        "at": "2026-06-24T00:00:01Z"
      })).toolPayload
      check agentPayload["ok"].getBool

      let stagePayload = response(callTool(3, "swarmy_stage", %*{
        "repo": repo,
        "event_id": "stage-event-1",
        "bead_id": "swarmy-l2z",
        "stage": "coding",
        "agent_id": "agent-1",
        "title": "Serve MCP write tools for swarm events",
        "at": "2026-06-24T00:00:02Z"
      })).toolPayload
      check stagePayload["ok"].getBool

      let snapshotPayload = response(callTool(4, "swarmy_snapshot", %*{
        "repo": repo
      })).toolPayload
      check snapshotPayload["ok"].getBool
      check snapshotPayload["agents"][0]["name"].getStr == "MCP Agent"
      check snapshotPayload["beads"][0]["id"].getStr == "swarmy-l2z"
      check snapshotPayload["beads"][0]["swarm_stage"].getStr == "coding"

      var store = openStore(dbPath)
      try:
        check store.scalarInt("SELECT COUNT(*) FROM events") == 2
      finally:
        store.close()

  test "unknown tools return structured tool errors":
    let payload = response(callTool(1, "missing_tool", %*{})).toolPayload

    check not payload["ok"].getBool
    check "unknown tool" in payload["error"].getStr

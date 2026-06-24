import std/[json, options, os, sequtils, strutils, times, unittest]

import tiny_sqlite

import swarmy_cli/mcp_stdio
import swarmy_core/guidance
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

proc isToolError(node: JsonNode): bool =
  node["result"].hasKey("isError") and node["result"]["isError"].getBool

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

    check initialized["result"]["capabilities"].hasKey("resources")
    check initialized["result"]["capabilities"].hasKey("prompts")

  test "bead-swarm guidance is exposed as MCP resource and prompt":
    let resources = response(request(1, "resources/list"))
    check resources["result"]["resources"][0]["uri"].getStr == "/bead-swarm"

    let resource = response(request(2, "resources/read", %*{
      "uri": "/bead-swarm"
    }))
    check resource["result"]["contents"][0]["text"].getStr == BeadSwarmGuidance

    let prompts = response(request(3, "prompts/list"))
    check prompts["result"]["prompts"][0]["name"].getStr == "bead-swarm"

    let prompt = response(request(4, "prompts/get", %*{
      "name": "bead-swarm"
    }))
    check prompt["result"]["messages"][0]["content"]["text"].getStr ==
      BeadSwarmGuidance

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

  test "unknown tools return JSON-RPC invalid params errors":
    let node = response(callTool(1, "missing_tool", %*{}))

    check node["error"]["code"].getInt == -32602
    check "unknown tool" in node["error"]["message"].getStr

  test "requests without ids do not execute tool side effects":
    withTempRepo proc(repo, dbPath: string) =
      let line = $(%*{
        "jsonrpc": "2.0",
        "method": "tools/call",
        "params": {
          "name": "swarmy_init",
          "arguments": {"repo": repo, "db": dbPath}
        }
      })

      check handleMcpLine(line).isNone
      check not fileExists(repo / ".swarmy" / "run.json")
      check not fileExists(dbPath)

  test "null request ids are rejected":
    let line = $(%*{
      "jsonrpc": "2.0",
      "id": nil,
      "method": "tools/list",
      "params": {}
    })
    let node = response(line)

    check node["error"]["code"].getInt == -32600
    check "must not be null" in node["error"]["message"].getStr

  test "missing required MCP arguments return tool errors without cwd writes":
    let original = getCurrentDir()
    let dir = getTempDir() / "swarmy-mcp-cwd-test-" & $getCurrentProcessId() &
      "-" & $epochTime().int
    createDir(dir)
    try:
      setCurrentDir(dir)
      let payload = response(callTool(1, "swarmy_init", %*{}))

      check payload.isToolError
      check "missing required argument `repo`" in payload.toolPayload["error"].getStr
      check not fileExists(dir / ".swarmy" / "run.json")
    finally:
      setCurrentDir(original)
      removeDir(dir)

  test "non-object MCP arguments return tool errors":
    let node = response(callTool(1, "swarmy_stage", %"not-an-object"))

    check node.isToolError
    check "arguments must be an object" in node.toolPayload["error"].getStr

  test "snapshot reads do not initialize missing stores":
    withTempRepo proc(repo, dbPath: string) =
      discard response(callTool(1, "swarmy_init", %*{
        "repo": repo,
        "db": dbPath
      })).toolPayload
      check not fileExists(dbPath)

      let node = response(callTool(2, "swarmy_snapshot", %*{
        "repo": repo
      }))

      check node.isToolError
      check "store not initialized" in node.toolPayload["error"].getStr
      check not fileExists(dbPath)

import std/[json, options, os, times, unittest]

import swarmy_cli/mcp_stdio
import swarmy_core/guidance

proc tempRepo(tag: string): string =
  let dir = getTempDir() / "swarmy-golden-" & tag & "-" &
    $getCurrentProcessId() & "-" & $epochTime().int
  if dirExists(dir):
    removeDir(dir)
  createDir(dir)
  dir

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

proc normalize(node: JsonNode): JsonNode =
  ## Blanks volatile fields (server version, guidance body) to stable
  ## placeholders so golden fixtures remain small and deterministic.
  case node.kind
  of JObject:
    result = newJObject()
    for key, value in node:
      if key == "version" and value.kind == JString:
        result[key] = %"<version>"
      elif key == "text" and value.kind == JString and
          value.getStr == BeadSwarmGuidance:
        result[key] = %"<guidance>"
      else:
        result[key] = normalize(value)
  of JArray:
    result = newJArray()
    for item in node:
      result.add normalize(item)
  else:
    result = node

proc fixturePath(name: string): string =
  currentSourcePath().parentDir / "fixtures" / "mcp" / name

proc readFixture(name: string): JsonNode =
  parseJson(readFile(fixturePath(name)))

suite "mcp protocol golden fixtures":
  test "initialize matches fixture":
    let actual = normalize(response(request(1, "initialize"))["result"])
    check actual == readFixture("initialize.json")

  test "tools/list matches fixture":
    let actual = normalize(response(request(1, "tools/list"))["result"])
    check actual == readFixture("tools_list.json")

  test "tools/call swarmy_stage payload matches fixture":
    let repo = tempRepo("stage")
    try:
      discard response(callTool(1, "swarmy_init", %*{"repo": repo})).toolPayload
      let actual = normalize(response(callTool(2, "swarmy_stage", %*{
        "repo": repo,
        "event_id": "evt-stage-1",
        "bead_id": "b1",
        "stage": "coding"
      })).toolPayload)
      check actual == readFixture("call_tool_stage.json")
    finally:
      removeDir(repo)

  test "resources/read matches fixture":
    let actual = normalize(response(request(1, "resources/read", %*{
      "uri": BeadSwarmResourceUri
    }))["result"])
    check actual == readFixture("resources_read.json")

  test "prompts/get matches fixture":
    let actual = normalize(response(request(1, "prompts/get", %*{
      "name": BeadSwarmPromptName
    }))["result"])
    check actual == readFixture("prompts_get.json")

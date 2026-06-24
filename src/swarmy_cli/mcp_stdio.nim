import std/[json, options, os, strutils]

import tiny_sqlite

import swarmy_cli/event_commands
import swarmy_cli/init as init_command
import swarmy_core/[app, events, persistence, run_metadata]

const
  McpProtocolVersion* = "2025-06-18"

proc textResult(text: string, isError = false): JsonNode =
  result = %*{"content": [%*{"type": "text", "text": text}]}
  if isError:
    result["isError"] = %true

proc rpcResult(id, value: JsonNode): string =
  var response = newJObject()
  response["jsonrpc"] = %"2.0"
  response["id"] = id
  response["result"] = value
  $response

proc rpcError(id: JsonNode, code: int, message: string): string =
  var error = newJObject()
  error["code"] = %code
  error["message"] = %message

  var response = newJObject()
  response["jsonrpc"] = %"2.0"
  response["id"] = id
  response["error"] = error
  $response

proc stringArg(args: JsonNode, name: string, default = ""): string =
  if args.kind == JObject and args.hasKey(name) and args[name].kind != JNull:
    args[name].getStr()
  else:
    default

proc optionalStringArg(args: JsonNode, name: string): Option[string] =
  if args.kind == JObject and args.hasKey(name) and args[name].kind != JNull:
    some(args[name].getStr())
  else:
    none(string)

proc toolError(name, error: string): JsonNode =
  var payload = newJObject()
  payload["ok"] = %false
  payload["tool"] = %name
  payload["error"] = %error
  textResult(payload.pretty, isError = true)

proc requireObjectArgs(toolName: string, args: JsonNode): Option[JsonNode] =
  if args.kind == JObject:
    return none(JsonNode)
  some(toolError(toolName, toolName & ": arguments must be an object"))

proc requireStringField(
  toolName: string,
  args: JsonNode,
  name: string
): tuple[ok: bool, value: string, error: JsonNode] =
  if args.kind != JObject or not args.hasKey(name) or
      args[name].kind != JString or args[name].getStr.len == 0:
    return (
      false,
      "",
      toolError(toolName, toolName & ": missing required argument `" & name & "`")
    )
  (true, args[name].getStr, newJNull())

proc addOpt(result: var seq[string], flag: string, value: Option[string]) =
  if value.isSome:
    result.add flag
    result.add value.get

proc addReq(result: var seq[string], flag, value: string) =
  result.add flag
  result.add value

proc commonArgs(args: JsonNode): seq[string] =
  result.addReq("--repo", args.stringArg("repo", "."))
  result.addOpt("--source", args.optionalStringArg("source"))
  result.addOpt("--at", args.optionalStringArg("at"))

proc runCliTool(name: string, cliResult: auto): JsonNode =
  if cliResult.exitCode == 0:
    var payload = newJObject()
    payload["ok"] = %true
    payload["tool"] = %name
    payload["output"] = %cliResult.output.strip()
    textResult(payload.pretty)
  else:
    toolError(name, cliResult.error.strip())

proc initTool(args: JsonNode): JsonNode =
  let objectError = requireObjectArgs("swarmy_init", args)
  if objectError.isSome:
    return objectError.get
  let repo = requireStringField("swarmy_init", args, "repo")
  if not repo.ok:
    return repo.error

  var cliArgs: seq[string]
  cliArgs.addReq("--repo", repo.value)
  cliArgs.addOpt("--db", args.optionalStringArg("db"))
  runCliTool("swarmy_init", init_command.run(cliArgs))

proc agentTool(args: JsonNode): JsonNode =
  let objectError = requireObjectArgs("swarmy_agent", args)
  if objectError.isSome:
    return objectError.get
  for name in ["repo", "event_id", "agent_id", "name"]:
    let found = requireStringField("swarmy_agent", args, name)
    if not found.ok:
      return found.error

  var cliArgs = args.commonArgs()
  cliArgs.addReq("--event-id", args.stringArg("event_id"))
  cliArgs.addReq("--agent", args.stringArg("agent_id"))
  cliArgs.addReq("--name", args.stringArg("name"))
  cliArgs.addOpt("--kind", args.optionalStringArg("kind"))
  cliArgs.addOpt("--metadata-json", args.optionalStringArg("metadata_json"))
  runCliTool("swarmy_agent", runAgent(cliArgs))

proc stageTool(args: JsonNode): JsonNode =
  let objectError = requireObjectArgs("swarmy_stage", args)
  if objectError.isSome:
    return objectError.get
  for name in ["repo", "event_id", "bead_id", "stage"]:
    let found = requireStringField("swarmy_stage", args, name)
    if not found.ok:
      return found.error

  var cliArgs = args.commonArgs()
  cliArgs.addReq("--event-id", args.stringArg("event_id"))
  cliArgs.addReq("--bead", args.stringArg("bead_id"))
  cliArgs.addReq("--stage", args.stringArg("stage"))
  cliArgs.addOpt("--agent", args.optionalStringArg("agent_id"))
  cliArgs.addOpt("--title", args.optionalStringArg("title"))
  cliArgs.addOpt("--payload-json", args.optionalStringArg("payload_json"))
  runCliTool("swarmy_stage", runStage(cliArgs))

proc snapshotTool(args: JsonNode): JsonNode =
  try:
    let objectError = requireObjectArgs("swarmy_snapshot", args)
    if objectError.isSome:
      return objectError.get
    let repoArg = requireStringField("swarmy_snapshot", args, "repo")
    if not repoArg.ok:
      return repoArg.error

    let repo = canonicalRepoPath(repoArg.value)
    let metadata = readRunMetadata(metadataPath(repo))
    if not fileExists(metadata.dbPath):
      return toolError("swarmy_snapshot", "store not initialized: " & metadata.dbPath)

    var store = openStore(metadata.dbPath)
    defer: store.close()

    var beads = newJArray()
    for row in store.db.iterate(
      "SELECT bead_id, title, status FROM beads WHERE run_id = ? ORDER BY bead_id",
      metadata.runId
    ):
      let beadId = row["bead_id"].fromDbValue(string)
      let latest = store.latestBeadStage(metadata.runId, beadId)
      var bead = %*{
        "id": beadId,
        "title": row["title"].fromDbValue(string),
        "status": row["status"].fromDbValue(string)
      }
      if latest.isSome:
        let found = latest.get
        bead["swarm_stage"] = %found.stage.stageName
        bead["stage_event_id"] = %found.eventId
        bead["stage_seq"] = %found.seq
      beads.add bead

    var agents = newJArray()
    for row in store.db.iterate(
      "SELECT agent_id, name, kind FROM agents WHERE run_id = ? ORDER BY agent_id",
      metadata.runId
    ):
      agents.add %*{
        "id": row["agent_id"].fromDbValue(string),
        "name": row["name"].fromDbValue(string),
        "kind": row["kind"].fromDbValue(string)
      }

    var payload = newJObject()
    payload["ok"] = %true
    payload["tool"] = %"swarmy_snapshot"
    payload["run_id"] = %metadata.runId
    payload["repo_path"] = %metadata.repoPath
    payload["beads"] = beads
    payload["agents"] = agents
    textResult(payload.pretty)
  except CatchableError as err:
    toolError("swarmy_snapshot", err.msg)

proc toolSchema(required: openArray[string], props: JsonNode): JsonNode =
  result = %*{"type": "object", "properties": props}
  result["required"] = newJArray()
  for item in required:
    result["required"].add %item

proc toolsList(): JsonNode =
  %*{
    "tools": [
      {
        "name": "swarmy_init",
        "description": "Initialize a Swarmy run in a repository",
        "inputSchema": toolSchema(["repo"], %*{
          "repo": {"type": "string"},
          "db": {"type": "string"}
        })
      },
      {
        "name": "swarmy_agent",
        "description": "Record or update an agent and append an agent.changed event",
        "inputSchema": toolSchema(["repo", "event_id", "agent_id", "name"], %*{
          "repo": {"type": "string"},
          "event_id": {"type": "string"},
          "agent_id": {"type": "string"},
          "name": {"type": "string"},
          "kind": {"type": "string"},
          "metadata_json": {"type": "string"},
          "source": {"type": "string"},
          "at": {"type": "string"}
        })
      },
      {
        "name": "swarmy_stage",
        "description": "Set a bead's Swarmy stage and append a stage.changed event",
        "inputSchema": toolSchema(["repo", "event_id", "bead_id", "stage"], %*{
          "repo": {"type": "string"},
          "event_id": {"type": "string"},
          "bead_id": {"type": "string"},
          "stage": {"type": "string"},
          "agent_id": {"type": "string"},
          "title": {"type": "string"},
          "payload_json": {"type": "string"},
          "source": {"type": "string"},
          "at": {"type": "string"}
        })
      },
      {
        "name": "swarmy_snapshot",
        "description": "Fetch the current persisted Swarmy run snapshot",
        "inputSchema": toolSchema(["repo"], %*{
          "repo": {"type": "string"}
        })
      }
    ]
  }

proc knownTool(name: string): bool =
  case name
  of "swarmy_init", "swarmy_agent", "swarmy_stage", "swarmy_snapshot":
    true
  else:
    false

proc callTool(name: string, args: JsonNode): JsonNode =
  case name
  of "swarmy_init": initTool(args)
  of "swarmy_agent": agentTool(args)
  of "swarmy_stage": stageTool(args)
  of "swarmy_snapshot": snapshotTool(args)
  else: toolError(name, "unknown tool: " & name)

proc handleMcpLine*(line: string): Option[string] =
  try:
    let request = parseJson(line)
    if request.kind != JObject or request{"jsonrpc"}.getStr() != "2.0" or
        not request.hasKey("method"):
      return some(rpcError(newJNull(), -32600, "invalid request"))
    if not request.hasKey("id"):
      return none(string)
    let id = request["id"]
    if id.kind == JNull:
      return some(rpcError(newJNull(), -32600, "request id must not be null"))
    let methodName = request{"method"}.getStr()

    case methodName
    of "initialize":
      some(rpcResult(id, %*{
        "protocolVersion": McpProtocolVersion,
        "serverInfo": {"name": Name, "version": Version},
        "capabilities": {"tools": {"listChanged": false}}
      }))
    of "tools/list":
      some(rpcResult(id, toolsList()))
    of "tools/call":
      let params = request{"params"}
      if params.kind != JObject:
        return some(rpcError(id, -32602, "tools/call requires params"))
      let name = params.stringArg("name")
      let args = if params.hasKey("arguments"): params["arguments"] else: newJObject()
      if not knownTool(name):
        return some(rpcError(id, -32602, "unknown tool: " & name))
      some(rpcResult(id, callTool(name, args)))
    else:
      if request.hasKey("id"):
        some(rpcError(id, -32601, "method not found: " & methodName))
      else:
        none(string)
  except CatchableError as err:
    some(rpcError(newJNull(), -32700, "parse error: " & err.msg))

proc serveMcpStdio*() =
  while true:
    try:
      let line = stdin.readLine()
      let response = handleMcpLine(line)
      if response.isSome:
        stdout.writeLine(response.get)
        stdout.flushFile()
    except EOFError:
      break

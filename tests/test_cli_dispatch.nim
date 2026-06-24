import std/[options, os, strutils, times, unittest]

import tiny_sqlite

import swarmy_cli/dispatch
import swarmy_core/app
import swarmy_core/persistence
import swarmy_core/run_metadata

proc withTempRepo(body: proc(repo, dbPath: string)) =
  let dir = getTempDir() / "swarmy-cli-test-" & $getCurrentProcessId() &
    "-" & $epochTime().int
  let dbPath = dir / "swarmy.db"
  if dirExists(dir):
    removeDir(dir)
  createDir(dir)
  try:
    discard initRun(dir, some(dbPath))
    body(dir, dbPath)
  finally:
    removeDir(dir)

proc scalarString(store: Store, sql: string): string =
  store.db.value(sql).get.fromDbValue(string)

proc scalarInt(store: Store, sql: string): int64 =
  store.db.value(sql).get.fromDbValue(int64)

suite "cli dispatch":
  test "version comes from core app metadata":
    let result = run(@["--version"])

    check result.exitCode == 0
    check result.output == Name & " " & Version & "\n"
    check result.error == ""

  test "serve dispatches through the internal serve module":
    let result = run(@["serve"])

    check result.exitCode == 0
    check result.output == "swarmy serve: server seam ready\n"
    check result.error == ""

  test "init validates arguments before reaching metadata writes":
    let result = run(@["init", "--repo"])

    check result.exitCode == 2
    check result.output == ""
    check "--repo requires a path" in result.error

  test "init rejects option-looking missing values":
    let result = run(@["init", "--repo", "--db"])

    check result.exitCode == 2
    check result.output == ""
    check "--repo requires a path" in result.error

  test "mcp dispatches through the internal mcp module":
    let result = run(@["mcp"])

    check result.exitCode == 0
    check result.output == "swarmy mcp: MCP server seam ready\n"
    check result.error == ""

  test "stage command records a durable bead stage event":
    withTempRepo proc(repo, dbPath: string) =
      let result = run(@[
        "stage",
        "--repo", repo,
        "--event-id", "stage-event-1",
        "--bead", "swarmy-2a5",
        "--stage", "coding",
        "--title", "Implement advisor-style CLI event commands",
        "--at", "2026-06-24T00:00:01Z"
      ])

      check result.exitCode == 0
      check result.output == "swarmy stage: swarmy-2a5 coding seq 1\n"
      check result.error == ""

      var store = openStore(dbPath)
      try:
        check store.scalarString("SELECT event_id FROM events") == "stage-event-1"
        check store.scalarString("SELECT stage FROM events") == "coding"
        check store.scalarString("SELECT bead_id FROM beads") == "swarmy-2a5"
        check store.scalarInt("SELECT next_seq FROM event_cursors") == 2
      finally:
        store.close()

  test "agent command upserts agent and records an agent event":
    withTempRepo proc(repo, dbPath: string) =
      let result = run(@[
        "agent",
        "--repo", repo,
        "--event-id", "agent-event-1",
        "--agent", "agent-1",
        "--name", "Reviewer",
        "--kind", "subagent",
        "--metadata-json", """{"role":"review"}""",
        "--at", "2026-06-24T00:00:02Z"
      ])

      check result.exitCode == 0
      check result.output == "swarmy agent: agent-1 seq 1\n"

      var store = openStore(dbPath)
      try:
        check store.scalarString("SELECT name FROM agents") == "Reviewer"
        check store.scalarString("SELECT kind FROM agents") == "subagent"
        check store.scalarString("SELECT event_type FROM events") == "agent.changed"
        check store.scalarString("SELECT agent_id FROM events") == "agent-1"
      finally:
        store.close()

  test "event command appends a generic event with payload":
    withTempRepo proc(repo, dbPath: string) =
      let result = run(@[
        "event",
        "--repo", repo,
        "--event-id", "event-1",
        "--type", "note.added",
        "--payload-json", """{"message":"hello"}""",
        "--at", "2026-06-24T00:00:03Z"
      ])

      check result.exitCode == 0
      check result.output == "swarmy event: event-1 seq 1\n"

      var store = openStore(dbPath)
      try:
        check store.scalarString("SELECT event_type FROM events") == "note.added"
        check store.scalarString("SELECT payload_json FROM events") ==
          """{"message":"hello"}"""
      finally:
        store.close()

  test "snapshot command writes a durable snapshot row":
    withTempRepo proc(repo, dbPath: string) =
      let result = run(@[
        "snapshot",
        "--repo", repo,
        "--source", "bd",
        "--bead", "swarmy-2a5",
        "--snapshot-json", """{"id":"swarmy-2a5"}""",
        "--at", "2026-06-24T00:00:04Z"
      ])

      check result.exitCode == 0
      check result.output == "swarmy snapshot: 1\n"

      var store = openStore(dbPath)
      try:
        check store.scalarString("SELECT bead_id FROM snapshots") == "swarmy-2a5"
        check store.scalarString("SELECT snapshot_json FROM snapshots") ==
          """{"id":"swarmy-2a5"}"""
      finally:
        store.close()

  test "write commands validate required arguments":
    let result = run(@["stage", "--event-id", "event-1"])

    check result.exitCode == 2
    check result.output == ""
    check "missing --bead" in result.error

  test "unknown commands fail before reaching a module":
    let result = run(@["unknown"])

    check result.exitCode == 2
    check result.output == ""
    check "unknown command" in result.error

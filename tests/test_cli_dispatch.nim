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

  test "snapshot requires source and rejects unused event ids":
    withTempRepo proc(repo, dbPath: string) =
      discard dbPath
      let missingSource = run(@[
        "snapshot",
        "--repo", repo,
        "--snapshot-json", "{}"
      ])
      check missingSource.exitCode == 2
      check "missing --source" in missingSource.error

      let eventId = run(@[
        "snapshot",
        "--repo", repo,
        "--event-id", "unused",
        "--source", "bd",
        "--snapshot-json", "{}"
      ])
      check eventId.exitCode == 2
      check "unexpected argument '--event-id'" in eventId.error

  test "write commands reject invalid timestamps before persistence":
    withTempRepo proc(repo, dbPath: string) =
      let result = run(@[
        "stage",
        "--repo", repo,
        "--event-id", "stage-event-1",
        "--bead", "swarmy-2a5",
        "--stage", "coding",
        "--at", "not-a-time"
      ])

      check result.exitCode == 2
      check "invalid --at" in result.error

      var store = initializeStore(dbPath)
      try:
        check store.scalarInt("SELECT COUNT(*) FROM runs") == 0
        check store.scalarInt("SELECT COUNT(*) FROM events") == 0
      finally:
        store.close()

  test "generic event rejects reserved event types":
    withTempRepo proc(repo, dbPath: string) =
      let result = run(@[
        "event",
        "--repo", repo,
        "--event-id", "event-1",
        "--type", "stage.changed",
        "--at", "2026-06-24T00:00:05Z"
      ])

      check result.exitCode == 2
      check "use `swarmy stage`" in result.error

      var store = initializeStore(dbPath)
      try:
        check store.scalarInt("SELECT COUNT(*) FROM events") == 0
      finally:
        store.close()

  test "stage command rolls back bead creation when event append fails":
    withTempRepo proc(repo, dbPath: string) =
      let first = run(@[
        "stage",
        "--repo", repo,
        "--event-id", "stage-event-1",
        "--bead", "existing-bead",
        "--stage", "coding",
        "--at", "2026-06-24T00:00:06Z"
      ])
      check first.exitCode == 0

      let duplicate = run(@[
        "stage",
        "--repo", repo,
        "--event-id", "stage-event-1",
        "--bead", "new-bead",
        "--stage", "review",
        "--at", "2026-06-24T00:00:07Z"
      ])
      check duplicate.exitCode == 1
      check "different event content" in duplicate.error

      var store = openStore(dbPath)
      try:
        check store.scalarInt(
          "SELECT COUNT(*) FROM beads WHERE bead_id = 'new-bead'"
        ) == 0
        check store.scalarInt("SELECT COUNT(*) FROM events") == 1
      finally:
        store.close()

  test "agent command rejects cross-run agent ids without mutation":
    withTempRepo proc(repo, dbPath: string) =
      var setup = initializeStore(dbPath)
      try:
        setup.db.exec(
          """
          INSERT INTO runs(run_id, repo_path, created_at, updated_at)
          VALUES('run-2', '/other', '2026-06-24T00:00:00Z', '2026-06-24T00:00:00Z')
          """
        )
        setup.db.exec(
          """
          INSERT INTO agents(agent_id, run_id, name, kind, created_at, updated_at)
          VALUES('agent-1', 'run-2', 'Other Agent', 'agent', '2026-06-24T00:00:00Z', '2026-06-24T00:00:00Z')
          """
        )
      finally:
        setup.close()

      let result = run(@[
        "agent",
        "--repo", repo,
        "--event-id", "agent-event-1",
        "--agent", "agent-1",
        "--name", "Mutated Agent",
        "--at", "2026-06-24T00:00:08Z"
      ])

      check result.exitCode == 1
      check "belongs to another run" in result.error

      var store = openStore(dbPath)
      try:
        check store.scalarString(
          "SELECT name FROM agents WHERE agent_id = 'agent-1'"
        ) == "Other Agent"
        check store.scalarInt("SELECT COUNT(*) FROM events") == 0
      finally:
        store.close()

  test "unknown commands fail before reaching a module":
    let result = run(@["unknown"])

    check result.exitCode == 2
    check result.output == ""
    check "unknown command" in result.error

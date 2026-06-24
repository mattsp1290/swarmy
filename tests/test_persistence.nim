import std/[options, os, strutils, unittest]

import tiny_sqlite

import swarmy_core/persistence

proc withTempStore(body: proc(store: Store, path: string)) =
  let dir = getTempDir() / "swarmy-store-test-" & $getCurrentProcessId()
  let path = dir / "swarmy.db"
  if dirExists(dir):
    removeDir(dir)
  createDir(dir)

  var store = initializeStore(path)
  try:
    body(store, path)
  finally:
    store.close()
    removeDir(dir)

proc scalarString(store: Store, sql: string): string =
  store.db.value(sql).get.fromDbValue(string)

proc scalarInt(store: Store, sql: string): int64 =
  store.db.value(sql).get.fromDbValue(int64)

proc tableNames(store: Store): seq[string] =
  for row in store.db.iterate(
    "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
  ):
    result.add row["name"].fromDbValue(string)

proc insertRun(store: Store, runId = "run-1") =
  store.db.exec(
    """
    INSERT INTO runs(run_id, repo_path, created_at, updated_at)
    VALUES(?, '/repo', '2026-06-24T00:00:00Z', '2026-06-24T00:00:00Z')
    """,
    runId
  )

suite "persistence":
  test "initializes the durable store schema":
    withTempStore proc(store: Store, path: string) =
      check fileExists(path)

      let names = store.tableNames()
      for table in [
        "agents",
        "beads",
        "errors",
        "event_cursors",
        "events",
        "runs",
        "schema_migrations",
        "snapshots",
        "stages",
      ]:
        check table in names

      check store.scalarInt("PRAGMA user_version") == StoreSchemaVersion
      check store.scalarInt("SELECT version FROM schema_migrations") ==
        StoreSchemaVersion

  test "configures sqlite for concurrent file-backed writes":
    withTempStore proc(store: Store, path: string) =
      check fileExists(path)
      check store.scalarString("PRAGMA journal_mode").toLowerAscii() == "wal"
      check store.scalarInt("PRAGMA busy_timeout") == DefaultBusyTimeoutMs
      check store.scalarInt("PRAGMA foreign_keys") == 1

  test "events enforce unique event ids and run-scoped sequence numbers":
    withTempStore proc(store: Store, path: string) =
      discard path
      store.insertRun()
      store.db.exec(
        """
        INSERT INTO events(event_id, run_id, seq, occurred_at, source, event_type)
        VALUES('event-1', 'run-1', 1, '2026-06-24T00:00:01Z', 'test', 'stage.started')
        """
      )

      expect SqliteError:
        store.db.exec(
          """
          INSERT INTO events(event_id, run_id, seq, occurred_at, source, event_type)
          VALUES('event-1', 'run-1', 2, '2026-06-24T00:00:02Z', 'test', 'stage.done')
          """
        )

      expect SqliteError:
        store.db.exec(
          """
          INSERT INTO events(event_id, run_id, seq, occurred_at, source, event_type)
          VALUES('event-2', 'run-1', 1, '2026-06-24T00:00:03Z', 'test', 'stage.done')
          """
        )

  test "appends events through a durable run cursor":
    withTempStore proc(store: Store, path: string) =
      discard path
      store.insertRun()

      check store.appendEvent(
        "event-1", "run-1", "2026-06-24T00:00:01Z", "test", "stage.started"
      ) == 1
      check store.appendEvent(
        "event-2", "run-1", "2026-06-24T00:00:02Z", "test", "stage.done"
      ) == 2
      check store.scalarInt("SELECT COUNT(*) FROM events") == 2
      check store.scalarInt(
        "SELECT next_seq FROM event_cursors WHERE run_id = 'run-1'"
      ) == 3

  test "duplicate event appends are idempotent and do not advance the cursor":
    withTempStore proc(store: Store, path: string) =
      discard path
      store.insertRun()

      check store.appendEvent(
        "event-1", "run-1", "2026-06-24T00:00:01Z", "test", "stage.started"
      ) == 1
      check store.appendEvent(
        "event-1", "run-1", "2026-06-24T00:00:01Z", "test", "stage.started"
      ) == 1
      check store.scalarInt("SELECT COUNT(*) FROM events") == 1
      check store.scalarInt(
        "SELECT next_seq FROM event_cursors WHERE run_id = 'run-1'"
      ) == 2

  test "independent store connections append distinct run-scoped sequences":
    withTempStore proc(store: Store, path: string) =
      store.insertRun()
      var second = initializeStore(path)
      try:
        check store.appendEvent(
          "event-1", "run-1", "2026-06-24T00:00:01Z", "test", "stage.started"
        ) == 1
        check second.appendEvent(
          "event-2", "run-1", "2026-06-24T00:00:02Z", "test", "stage.done"
        ) == 2
        check store.scalarInt("SELECT COUNT(*) FROM events") == 2
        check store.scalarInt("SELECT COUNT(DISTINCT seq) FROM events") == 2
        check store.scalarInt(
          "SELECT next_seq FROM event_cursors WHERE run_id = 'run-1'"
        ) == 3
      finally:
        second.close()

  test "timestamp columns reject non-rfc3339 strings":
    withTempStore proc(store: Store, path: string) =
      discard path
      expect SqliteError:
        store.db.exec(
          """
          INSERT INTO runs(run_id, repo_path, created_at, updated_at)
          VALUES('run-1', '/repo', 'not-a-time', '2026-06-24T00:00:00Z')
          """
        )

      store.insertRun()
      expect SqliteError:
        discard store.appendEvent(
          "event-1", "run-1", "not-a-time", "test", "stage.started"
        )
      check store.scalarInt("SELECT COUNT(*) FROM events") == 0
      check store.scalarInt("SELECT COUNT(*) FROM event_cursors") == 0

  test "stage names are constrained to the known reducer vocabulary":
    withTempStore proc(store: Store, path: string) =
      discard path
      store.insertRun()
      store.db.exec(
        """
        INSERT INTO beads(run_id, bead_id, title, updated_at)
        VALUES('run-1', 'swarmy-0g2', 'Create SQLite schema', '2026-06-24T00:00:00Z')
        """
      )
      store.db.exec(
        """
        INSERT INTO stages(run_id, bead_id, stage, started_at)
        VALUES('run-1', 'swarmy-0g2', 'review', '2026-06-24T00:00:01Z')
        """
      )

      expect SqliteError:
        store.db.exec(
          """
          INSERT INTO stages(run_id, bead_id, stage, started_at)
          VALUES('run-1', 'swarmy-0g2', 'surprise', '2026-06-24T00:00:02Z')
          """
        )

  test "event and stage provenance foreign keys are enforced":
    withTempStore proc(store: Store, path: string) =
      discard path
      store.insertRun()

      expect SqliteError:
        discard store.appendEvent(
          "event-1",
          "run-1",
          "2026-06-24T00:00:01Z",
          "test",
          "bead.changed",
          beadId = some("missing-bead")
        )

      store.db.exec(
        """
        INSERT INTO beads(run_id, bead_id, title, updated_at)
        VALUES('run-1', 'swarmy-0g2', 'Create SQLite schema', '2026-06-24T00:00:00Z')
        """
      )
      discard store.appendEvent(
        "event-1",
        "run-1",
        "2026-06-24T00:00:01Z",
        "test",
        "bead.changed",
        beadId = some("swarmy-0g2")
      )

      expect SqliteError:
        store.db.exec(
          """
          INSERT INTO stages(run_id, bead_id, stage, started_at, source_event_id)
          VALUES('run-1', 'swarmy-0g2', 'review', '2026-06-24T00:00:02Z', 'missing-event')
          """
        )

      store.db.exec(
        """
        INSERT INTO stages(run_id, bead_id, stage, started_at, source_event_id)
        VALUES('run-1', 'swarmy-0g2', 'review', '2026-06-24T00:00:02Z', 'event-1')
        """
      )

  test "appendEvent rejects agents outside the event run before cursor allocation":
    withTempStore proc(store: Store, path: string) =
      discard path
      store.insertRun("run-1")
      store.insertRun("run-2")
      store.db.exec(
        """
        INSERT INTO agents(agent_id, run_id, name, created_at, updated_at)
        VALUES('agent-2', 'run-2', 'other-run-agent', '2026-06-24T00:00:00Z', '2026-06-24T00:00:00Z')
        """
      )

      expect ValueError:
        discard store.appendEvent(
          "event-1",
          "run-1",
          "2026-06-24T00:00:01Z",
          "test",
          "agent.event",
          agentId = some("agent-2")
        )

      expect ValueError:
        discard store.appendEvent(
          "event-2",
          "run-1",
          "2026-06-24T00:00:01Z",
          "test",
          "agent.event",
          agentId = some("missing-agent")
        )

      check store.scalarInt("SELECT COUNT(*) FROM events") == 0
      check store.scalarInt("SELECT COUNT(*) FROM event_cursors") == 0

import std/[options, os, unittest]

import tiny_sqlite

import swarmy_core/events
import swarmy_core/persistence

proc withTempStore(body: proc(store: Store, path: string)) =
  let dir = getTempDir() / "swarmy-events-test-" & $getCurrentProcessId()
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

proc scalarInt(store: Store, sql: string): int64 =
  store.db.value(sql).get.fromDbValue(int64)

proc insertRunAndBead(store: Store, runId = "run-1", beadId = "swarmy-3p0") =
  store.db.exec(
    """
    INSERT INTO runs(run_id, repo_path, created_at, updated_at)
    VALUES(?, '/repo', '2026-06-24T00:00:00Z', '2026-06-24T00:00:00Z')
    """,
    runId
  )
  store.db.exec(
    """
    INSERT INTO beads(run_id, bead_id, title, updated_at)
    VALUES(?, ?, 'Record idempotent agent and stage events', '2026-06-24T00:00:00Z')
    """,
    runId,
    beadId
  )

suite "events":
  test "stage names parse, validate, and reduce legacy values to unknown":
    check stageCoding.stageName == "coding"
    check $stageReview == "review"
    check parseStage("merge") == stageMerge
    check parseStage("legacy-stage") == stageUnknown
    check parseWritableStage("unknown") == stageUnknown

    expect ValueError:
      discard parseWritableStage("legacy-stage")

  test "recordStageEvent appends idempotent stage events":
    withTempStore proc(store: Store, path: string) =
      discard path
      store.insertRunAndBead()

      check store.recordStageEvent(
        "event-1", "run-1", "swarmy-3p0", "2026-06-24T00:00:01Z", stageCoding
      ) == 1
      check store.recordStageEvent(
        "event-1", "run-1", "swarmy-3p0", "2026-06-24T00:00:01Z", stageCoding
      ) == 1

      let latest = store.latestBeadStage("run-1", "swarmy-3p0").get
      check latest.eventId == "event-1"
      check latest.seq == 1
      check latest.stage == stageCoding
      check store.scalarInt("SELECT COUNT(*) FROM events") == 1
      check store.scalarInt(
        "SELECT next_seq FROM event_cursors WHERE run_id = 'run-1'"
      ) == 2

  test "duplicate event ids do not change the reduced stage":
    withTempStore proc(store: Store, path: string) =
      discard path
      store.insertRunAndBead()

      check store.recordStageEvent(
        "event-1", "run-1", "swarmy-3p0", "2026-06-24T00:00:01Z", stageCoding
      ) == 1
      expect ValueError:
        discard store.recordStageEvent(
          "event-1", "run-1", "swarmy-3p0", "2026-06-24T00:00:02Z", stageReview
        )

      let latest = store.latestBeadStage("run-1", "swarmy-3p0").get
      check latest.eventId == "event-1"
      check latest.stage == stageCoding
      check store.scalarInt("SELECT COUNT(*) FROM events") == 1
      check store.scalarInt(
        "SELECT next_seq FROM event_cursors WHERE run_id = 'run-1'"
      ) == 2

  test "duplicate event ids with different beads fail without cursor advance":
    withTempStore proc(store: Store, path: string) =
      discard path
      store.insertRunAndBead(beadId = "swarmy-a")
      store.db.exec(
        """
        INSERT INTO beads(run_id, bead_id, title, updated_at)
        VALUES('run-1', 'swarmy-b', 'Second bead', '2026-06-24T00:00:00Z')
        """
      )

      check store.recordStageEvent(
        "event-1", "run-1", "swarmy-a", "2026-06-24T00:00:01Z", stageCoding
      ) == 1

      expect ValueError:
        discard store.recordStageEvent(
          "event-1", "run-1", "swarmy-b", "2026-06-24T00:00:01Z", stageCoding
        )

      check store.latestBeadStage("run-1", "swarmy-b").isNone
      check store.scalarInt("SELECT COUNT(*) FROM events") == 1
      check store.scalarInt(
        "SELECT next_seq FROM event_cursors WHERE run_id = 'run-1'"
      ) == 2

  test "latest bead stage is deterministic by event sequence":
    withTempStore proc(store: Store, path: string) =
      discard path
      store.insertRunAndBead()

      check store.recordStageEvent(
        "event-1", "run-1", "swarmy-3p0", "2026-06-24T00:00:03Z", stageValidation
      ) == 1
      check store.recordStageEvent(
        "event-2", "run-1", "swarmy-3p0", "2026-06-24T00:00:02Z", stageReview
      ) == 2

      let latest = store.latestBeadStage("run-1", "swarmy-3p0").get
      check latest.eventId == "event-2"
      check latest.seq == 2
      check latest.stage == stageReview

  test "recordStageEvent validates string stage names before writing":
    withTempStore proc(store: Store, path: string) =
      discard path
      store.insertRunAndBead()

      expect ValueError:
        discard store.recordStageEvent(
          "event-1", "run-1", "swarmy-3p0", "2026-06-24T00:00:01Z", "surprise"
        )

      check store.scalarInt("SELECT COUNT(*) FROM events") == 0
      check store.scalarInt("SELECT COUNT(*) FROM event_cursors") == 0

  test "stage event writes enforce bead and agent run ownership":
    withTempStore proc(store: Store, path: string) =
      discard path
      store.insertRunAndBead()

      expect SqliteError:
        discard store.recordStageEvent(
          "event-1",
          "run-1",
          "missing-bead",
          "2026-06-24T00:00:01Z",
          stageCoding
        )

      expect ValueError:
        discard store.recordStageEvent(
          "event-2",
          "run-1",
          "swarmy-3p0",
          "2026-06-24T00:00:01Z",
          stageCoding,
          agentId = some("missing-agent")
        )

      store.db.exec(
        """
        INSERT INTO runs(run_id, repo_path, created_at, updated_at)
        VALUES('run-2', '/repo', '2026-06-24T00:00:00Z', '2026-06-24T00:00:00Z')
        """
      )
      store.db.exec(
        """
        INSERT INTO agents(agent_id, run_id, name, created_at, updated_at)
        VALUES('agent-2', 'run-2', 'other-run-agent', '2026-06-24T00:00:00Z', '2026-06-24T00:00:00Z')
        """
      )

      expect ValueError:
        discard store.recordStageEvent(
          "event-3",
          "run-1",
          "swarmy-3p0",
          "2026-06-24T00:00:01Z",
          stageCoding,
          agentId = some("agent-2")
        )

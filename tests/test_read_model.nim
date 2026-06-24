import std/[options, unittest]

import tiny_sqlite

import swarmy_core/bd_adapter
import swarmy_core/events
import swarmy_core/persistence
import swarmy_core/read_model

proc snapshot(
  id: string,
  status = "open",
  title = "Fixture bead",
  priority = 1,
  issueType = "feature"
): BeadSnapshot =
  BeadSnapshot(
    id: id,
    title: title,
    description: "",
    notes: "",
    status: status,
    priority: priority,
    issueType: issueType,
    updatedAt: "2026-06-24T00:00:00Z",
    closedAt: none(string),
    labels: @["data"]
  )

proc insertRunAndBead(store: Store, runId, beadId: string) =
  store.db.exec(
    """
    INSERT OR IGNORE INTO runs(run_id, repo_path, created_at, updated_at)
    VALUES(?, '/repo', '2026-06-24T00:00:00Z', '2026-06-24T00:00:00Z')
    """,
    runId
  )
  store.db.exec(
    """
    INSERT INTO beads(run_id, bead_id, title, updated_at)
    VALUES(?, ?, 'Fixture bead', '2026-06-24T00:00:00Z')
    """,
    runId,
    beadId
  )

proc withStore(body: proc(store: Store)) =
  var store = initializeStore(":memory:")
  try:
    body(store)
  finally:
    store.close()

suite "read model":
  test "returns beads discovered from bd without swarmy events":
    withStore proc(store: Store) =
      store.insertRunAndBead("run-1", "swarmy-iph")

      let merged = store.mergeBeads("run-1", [snapshot("swarmy-iph", status = "in_progress")])

      check merged.len == 1
      check merged[0].beadId == "swarmy-iph"
      check merged[0].canonicalStatus == "in_progress"
      check merged[0].swarmStage.isNone
      check not merged[0].hasSwarmyEvents

  test "overlays latest swarmy stage while preserving canonical bead status":
    withStore proc(store: Store) =
      store.insertRunAndBead("run-1", "swarmy-iph")
      discard store.recordStageEvent(
        "event-1", "run-1", "swarmy-iph", "2026-06-24T00:00:01Z", stageCoding
      )
      discard store.recordStageEvent(
        "event-2", "run-1", "swarmy-iph", "2026-06-24T00:00:02Z", stageReview
      )

      let merged = store.mergeBeads("run-1", [snapshot("swarmy-iph", status = "open")])

      check merged[0].canonicalStatus == "open"
      check merged[0].swarmStage == some(stageReview)
      check merged[0].stageEventId == some("event-2")
      check merged[0].stageSeq == some(2'i64)
      check merged[0].hasSwarmyEvents

  test "keeps run-scoped stages isolated":
    withStore proc(store: Store) =
      store.insertRunAndBead("run-1", "swarmy-iph")
      store.insertRunAndBead("run-2", "swarmy-iph")
      discard store.recordStageEvent(
        "event-1", "run-2", "swarmy-iph", "2026-06-24T00:00:01Z", stageComplete
      )

      let merged = store.mergeBeads("run-1", [snapshot("swarmy-iph")])

      check merged[0].swarmStage.isNone
      check not merged[0].hasSwarmyEvents

  test "reports discovered bead ids in bd snapshot order":
    withStore proc(store: Store) =
      store.insertRunAndBead("run-1", "a")
      store.insertRunAndBead("run-1", "b")

      let merged = store.mergeBeads("run-1", [snapshot("a"), snapshot("b")])

      check merged.discoveredBeadIds == @["a", "b"]

  test "propagates canonical bd priority issue type and labels":
    withStore proc(store: Store) =
      store.insertRunAndBead("run-1", "swarmy-iph")

      let merged = store.mergeBeads("run-1", [
        snapshot("swarmy-iph", priority = 2, issueType = "task")
      ])

      check merged[0].canonicalPriority == 2
      check merged[0].canonicalIssueType == "task"
      check merged[0].labels == @["data"]

  test "detects whether discovered beads have any swarmy stage events":
    withStore proc(store: Store) =
      store.insertRunAndBead("run-1", "a")
      store.insertRunAndBead("run-1", "b")
      discard store.recordStageEvent(
        "event-1", "run-1", "b", "2026-06-24T00:00:01Z", stageBlocked
      )

      check store.hasDiscoveredStageEvents("run-1", [snapshot("a")]) == false
      check store.hasDiscoveredStageEvents("run-1", [snapshot("a"), snapshot("b")])

  test "reports latest stage events missing from canonical bead snapshots":
    withStore proc(store: Store) =
      store.insertRunAndBead("run-1", "a")
      store.insertRunAndBead("run-1", "b")
      discard store.recordStageEvent(
        "event-a1", "run-1", "a", "2026-06-24T00:00:01Z", stageCoding
      )
      discard store.recordStageEvent(
        "event-b1", "run-1", "b", "2026-06-24T00:00:02Z", stageCoding
      )
      discard store.recordStageEvent(
        "event-b2", "run-1", "b", "2026-06-24T00:00:03Z", stageComplete
      )

      let missing = store.stageEventsWithoutCanonicalBeads("run-1", [snapshot("a")])

      check missing.len == 1
      check missing[0].beadId == "b"
      check missing[0].swarmStage == stageComplete
      check missing[0].stageEventId == "event-b2"
      check missing[0].stageSeq == 3

  test "missing canonical stage-event diagnostics are run scoped":
    withStore proc(store: Store) =
      store.insertRunAndBead("run-1", "a")
      store.insertRunAndBead("run-2", "b")
      discard store.recordStageEvent(
        "event-b1", "run-2", "b", "2026-06-24T00:00:01Z", stageBlocked
      )

      let missing = store.stageEventsWithoutCanonicalBeads("run-1", [])

      check missing.len == 0

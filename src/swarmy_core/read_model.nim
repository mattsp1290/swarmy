import std/options

import tiny_sqlite

import swarmy_core/bd_adapter
import swarmy_core/events
import swarmy_core/persistence

type
  MergedBead* = object
    runId*: string
    beadId*: string
    title*: string
    canonicalStatus*: string
    canonicalPriority*: int
    canonicalIssueType*: string
    labels*: seq[string]
    swarmStage*: Option[Stage]
    stageEventId*: Option[string]
    stageSeq*: Option[int64]
    hasSwarmyEvents*: bool
    rawBead*: BeadSnapshot

proc mergeBead*(store: Store, runId: string, snapshot: BeadSnapshot): MergedBead =
  let stage = store.latestBeadStage(runId, snapshot.id)
  result = MergedBead(
    runId: runId,
    beadId: snapshot.id,
    title: snapshot.title,
    canonicalStatus: snapshot.status,
    canonicalPriority: snapshot.priority,
    canonicalIssueType: snapshot.issueType,
    labels: snapshot.labels,
    swarmStage: none(Stage),
    stageEventId: none(string),
    stageSeq: none(int64),
    hasSwarmyEvents: false,
    rawBead: snapshot
  )

  if stage.isSome:
    let found = stage.get
    result.swarmStage = some(found.stage)
    result.stageEventId = some(found.eventId)
    result.stageSeq = some(found.seq)
    result.hasSwarmyEvents = true

proc mergeBeads*(
  store: Store,
  runId: string,
  snapshots: openArray[BeadSnapshot]
): seq[MergedBead] =
  for snapshot in snapshots:
    result.add store.mergeBead(runId, snapshot)

proc discoveredBeadIds*(beads: openArray[MergedBead]): seq[string] =
  for bead in beads:
    result.add bead.beadId

proc countStageEvents(store: Store, runId: string, beadId: string): int64 =
  store.db.value(
    """
    SELECT COUNT(*)
    FROM events
    WHERE run_id = ?
      AND bead_id = ?
      AND event_type = ?
    """,
    runId,
    beadId,
    StageEventType
  ).get.fromDbValue(int64)

proc hasDiscoveredStageEvents*(
  store: Store,
  runId: string,
  snapshots: openArray[BeadSnapshot]
): bool =
  for snapshot in snapshots:
    if store.countStageEvents(runId, snapshot.id) > 0:
      return true

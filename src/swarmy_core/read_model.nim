import std/[options, sequtils]

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

  StageEventWithoutCanonicalBead* = object
    runId*: string
    beadId*: string
    swarmStage*: Stage
    stageEventId*: string
    stageSeq*: int64
    occurredAt*: string

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

proc containsId(ids: openArray[string], id: string): bool =
  for item in ids:
    if item == id:
      return true

proc stageEventsWithoutCanonicalBeads*(
  store: Store,
  runId: string,
  snapshots: openArray[BeadSnapshot]
): seq[StageEventWithoutCanonicalBead] =
  let discoveredIds = snapshots.mapIt(it.id)
  for row in store.db.iterate(
    """
    SELECT e.event_id, e.bead_id, e.seq, e.occurred_at, e.stage
    FROM events e
    INNER JOIN (
      SELECT bead_id, MAX(seq) AS seq
      FROM events
      WHERE run_id = ?
        AND event_type = ?
        AND bead_id IS NOT NULL
        AND stage IS NOT NULL
      GROUP BY bead_id
    ) latest
      ON latest.bead_id = e.bead_id
     AND latest.seq = e.seq
    WHERE e.run_id = ?
      AND e.event_type = ?
      AND e.bead_id IS NOT NULL
      AND e.stage IS NOT NULL
    ORDER BY e.seq
    """,
    runId,
    StageEventType,
    runId,
    StageEventType
  ):
    let beadId = row["bead_id"].fromDbValue(string)
    if not discoveredIds.containsId(beadId):
      result.add StageEventWithoutCanonicalBead(
        runId: runId,
        beadId: beadId,
        swarmStage: parseStage(row["stage"].fromDbValue(string)),
        stageEventId: row["event_id"].fromDbValue(string),
        stageSeq: row["seq"].fromDbValue(int64),
        occurredAt: row["occurred_at"].fromDbValue(string)
      )

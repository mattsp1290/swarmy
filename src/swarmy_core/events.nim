import std/options

import tiny_sqlite

import swarmy_core/persistence

const StageEventType* = "stage.changed"

type
  Stage* = enum
    stageCoding
    stageValidation
    stageReview
    stageMerge
    stageBlocked
    stageComplete
    stageUnknown

  BeadStageSnapshot* = object
    runId*: string
    beadId*: string
    eventId*: string
    seq*: int64
    occurredAt*: string
    stage*: Stage

proc stageName*(stage: Stage): string =
  case stage
  of stageCoding: "coding"
  of stageValidation: "validation"
  of stageReview: "review"
  of stageMerge: "merge"
  of stageBlocked: "blocked"
  of stageComplete: "complete"
  of stageUnknown: "unknown"

proc `$`*(stage: Stage): string =
  stage.stageName

proc parseStage*(name: string): Stage =
  case name
  of "coding": stageCoding
  of "validation": stageValidation
  of "review": stageReview
  of "merge": stageMerge
  of "blocked": stageBlocked
  of "complete": stageComplete
  of "unknown": stageUnknown
  else: stageUnknown

proc parseWritableStage*(name: string): Stage =
  result = parseStage(name)
  if result == stageUnknown and name != "unknown":
    raise newException(ValueError, "unknown stage: " & name)

proc recordStageEvent*(
  store: Store,
  eventId: string,
  runId: string,
  beadId: string,
  occurredAt: string,
  stage: Stage,
  agentId: Option[string] = none(string),
  source = "swarmy",
  payloadJson = "{}"
): int64 =
  appendEvent(
    store,
    eventId,
    runId,
    occurredAt,
    source,
    StageEventType,
    beadId = some(beadId),
    agentId = agentId,
    stage = some(stage.stageName),
    payloadJson = payloadJson
  )

proc recordStageEvent*(
  store: Store,
  eventId: string,
  runId: string,
  beadId: string,
  occurredAt: string,
  stageName: string,
  agentId: Option[string] = none(string),
  source = "swarmy",
  payloadJson = "{}"
): int64 =
  recordStageEvent(
    store,
    eventId,
    runId,
    beadId,
    occurredAt,
    parseWritableStage(stageName),
    agentId,
    source,
    payloadJson
  )

proc latestBeadStage*(
  store: Store,
  runId: string,
  beadId: string
): Option[BeadStageSnapshot] =
  let row = store.db.one(
    """
    SELECT event_id, seq, occurred_at, stage
    FROM events
    WHERE run_id = ?
      AND bead_id = ?
      AND event_type = ?
      AND stage IS NOT NULL
    ORDER BY seq DESC
    LIMIT 1
    """,
    runId,
    beadId,
    StageEventType
  )
  if row.isNone:
    return none(BeadStageSnapshot)

  let found = row.get
  some(BeadStageSnapshot(
    runId: runId,
    beadId: beadId,
    eventId: found["event_id"].fromDbValue(string),
    seq: found["seq"].fromDbValue(int64),
    occurredAt: found["occurred_at"].fromDbValue(string),
    stage: parseStage(found["stage"].fromDbValue(string))
  ))

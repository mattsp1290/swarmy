import std/[options, os]

import tiny_sqlite

const
  StoreSchemaVersion* = 1
  DefaultBusyTimeoutMs* = 5000

type
  Store* = object
    path*: string
    db*: DbConn

proc optionString(row: ResultRow, column: string): Option[string] =
  let value = row[column]
  if value.kind == sqliteNull:
    none(string)
  else:
    some(value.fromDbValue(string))

proc sameEventContent(
  row: ResultRow,
  runId: string,
  occurredAt: string,
  source: string,
  eventType: string,
  beadId: Option[string],
  agentId: Option[string],
  stage: Option[string],
  payloadJson: string
): bool =
  row["run_id"].fromDbValue(string) == runId and
    row["occurred_at"].fromDbValue(string) == occurredAt and
    row["source"].fromDbValue(string) == source and
    row["event_type"].fromDbValue(string) == eventType and
    row.optionString("bead_id") == beadId and
    row.optionString("agent_id") == agentId and
    row.optionString("stage") == stage and
    row["payload_json"].fromDbValue(string) == payloadJson

proc validateEventAgentRun(store: Store, runId: string, agentId: Option[string]) =
  if agentId.isNone:
    return

  let found = store.db.value(
    "SELECT COUNT(*) FROM agents WHERE run_id = ? AND agent_id = ?",
    runId,
    agentId.get
  ).get.fromDbValue(int64)
  if found == 0:
    raise newException(
      ValueError,
      "agent does not belong to run: " & agentId.get
    )

const StoreSchema = """
CREATE TABLE IF NOT EXISTS schema_migrations (
  version INTEGER PRIMARY KEY,
  applied_at TEXT NOT NULL CHECK(
    applied_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z'
  )
);

CREATE TABLE IF NOT EXISTS runs (
  run_id TEXT PRIMARY KEY,
  repo_path TEXT NOT NULL,
  created_at TEXT NOT NULL CHECK(
    created_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z'
  ),
  updated_at TEXT NOT NULL CHECK(
    updated_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z'
  ),
  status TEXT NOT NULL DEFAULT 'active',
  metadata_json TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS agents (
  agent_id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL REFERENCES runs(run_id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  kind TEXT NOT NULL DEFAULT 'agent',
  created_at TEXT NOT NULL CHECK(
    created_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z'
  ),
  updated_at TEXT NOT NULL CHECK(
    updated_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z'
  ),
  metadata_json TEXT NOT NULL DEFAULT '{}',
  UNIQUE(run_id, name)
);

CREATE TABLE IF NOT EXISTS beads (
  run_id TEXT NOT NULL REFERENCES runs(run_id) ON DELETE CASCADE,
  bead_id TEXT NOT NULL,
  title TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'unknown',
  priority INTEGER,
  issue_type TEXT,
  snapshot_json TEXT NOT NULL DEFAULT '{}',
  updated_at TEXT NOT NULL CHECK(
    updated_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z'
  ),
  PRIMARY KEY(run_id, bead_id)
);

CREATE TABLE IF NOT EXISTS stages (
  stage_id INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id TEXT NOT NULL REFERENCES runs(run_id) ON DELETE CASCADE,
  bead_id TEXT NOT NULL,
  agent_id TEXT REFERENCES agents(agent_id) ON DELETE SET NULL,
  stage TEXT NOT NULL CHECK(stage IN (
    'coding', 'validation', 'review', 'merge', 'blocked', 'complete', 'unknown'
  )),
  started_at TEXT NOT NULL CHECK(
    started_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z'
  ),
  ended_at TEXT CHECK(
    ended_at IS NULL OR
    ended_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z'
  ),
  source_event_id TEXT REFERENCES events(event_id) ON DELETE SET NULL,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY(run_id, bead_id) REFERENCES beads(run_id, bead_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS events (
  event_id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL REFERENCES runs(run_id) ON DELETE CASCADE,
  seq INTEGER NOT NULL CHECK(seq > 0),
  occurred_at TEXT NOT NULL CHECK(
    occurred_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z'
  ),
  source TEXT NOT NULL,
  event_type TEXT NOT NULL,
  bead_id TEXT,
  agent_id TEXT REFERENCES agents(agent_id) ON DELETE SET NULL,
  stage TEXT CHECK(stage IS NULL OR stage IN (
    'coding', 'validation', 'review', 'merge', 'blocked', 'complete', 'unknown'
  )),
  payload_json TEXT NOT NULL DEFAULT '{}',
  UNIQUE(run_id, seq),
  FOREIGN KEY(run_id, bead_id) REFERENCES beads(run_id, bead_id)
);

CREATE TABLE IF NOT EXISTS event_cursors (
  run_id TEXT PRIMARY KEY REFERENCES runs(run_id) ON DELETE CASCADE,
  next_seq INTEGER NOT NULL CHECK(next_seq > 0)
);

CREATE TABLE IF NOT EXISTS snapshots (
  snapshot_id INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id TEXT NOT NULL REFERENCES runs(run_id) ON DELETE CASCADE,
  bead_id TEXT,
  captured_at TEXT NOT NULL CHECK(
    captured_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z'
  ),
  source TEXT NOT NULL,
  snapshot_json TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS errors (
  error_id INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id TEXT NOT NULL REFERENCES runs(run_id) ON DELETE CASCADE,
  occurred_at TEXT NOT NULL CHECK(
    occurred_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z'
  ),
  severity TEXT NOT NULL,
  message TEXT NOT NULL,
  context_json TEXT NOT NULL DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_agents_run_id ON agents(run_id);
CREATE INDEX IF NOT EXISTS idx_beads_run_status ON beads(run_id, status);
CREATE INDEX IF NOT EXISTS idx_stages_run_bead ON stages(run_id, bead_id, started_at);
CREATE INDEX IF NOT EXISTS idx_events_run_seq ON events(run_id, seq);
CREATE INDEX IF NOT EXISTS idx_events_run_type ON events(run_id, event_type, occurred_at);
CREATE INDEX IF NOT EXISTS idx_snapshots_run_bead ON snapshots(run_id, bead_id, captured_at);
CREATE INDEX IF NOT EXISTS idx_errors_run_time ON errors(run_id, occurred_at);

INSERT OR IGNORE INTO schema_migrations(version, applied_at)
VALUES(1, strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));

PRAGMA user_version = 1;
"""

proc ensureParentDir(path: string) =
  if path == ":memory:":
    return

  let dir = parentDir(path)
  if dir.len > 0 and not dirExists(dir):
    createDir(dir)

proc openStore*(path: string): Store =
  ensureParentDir(path)
  let db = openDatabase(path)
  db.exec("PRAGMA busy_timeout = " & $DefaultBusyTimeoutMs)
  db.exec("PRAGMA journal_mode=WAL")
  db.exec("PRAGMA foreign_keys=ON")
  Store(path: path, db: db)

proc initializeSchema*(store: Store) =
  store.db.execScript(StoreSchema)

proc initializeStore*(path: string): Store =
  result = openStore(path)
  initializeSchema(result)

proc close*(store: var Store) =
  store.db.close()

proc appendEventInTransaction*(
  store: Store,
  eventId: string,
  runId: string,
  occurredAt: string,
  source: string,
  eventType: string,
  beadId: Option[string] = none(string),
  agentId: Option[string] = none(string),
  stage: Option[string] = none(string),
  payloadJson = "{}"
): int64 =
  store.validateEventAgentRun(runId, agentId)
  store.db.exec(
    "INSERT OR IGNORE INTO event_cursors(run_id, next_seq) VALUES(?, 1)",
    runId
  )

  let existing = store.db.one(
    """
    SELECT run_id, seq, occurred_at, source, event_type,
      bead_id, agent_id, stage, payload_json
    FROM events
    WHERE event_id = ?
    """,
    eventId
  )
  if existing.isSome:
    let row = existing.get
    if not row.sameEventContent(
      runId,
      occurredAt,
      source,
      eventType,
      beadId,
      agentId,
      stage,
      payloadJson
    ):
      raise newException(
        ValueError,
        "event id already exists with different event content: " & eventId
      )
    result = row["seq"].fromDbValue(int64)
  else:
    let seq = store.db.value(
      "SELECT next_seq FROM event_cursors WHERE run_id = ?",
      runId
    ).get.fromDbValue(int64)
    let params = toDbValues(
      eventId, runId, seq, occurredAt, source, eventType,
      beadId, agentId, stage, payloadJson
    )
    store.db.exec(
      """
      INSERT INTO events(
        event_id, run_id, seq, occurred_at, source, event_type,
        bead_id, agent_id, stage, payload_json
      )
      VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """,
      params
    )
    store.db.exec(
      "UPDATE event_cursors SET next_seq = next_seq + 1 WHERE run_id = ?",
      runId
    )
    result = seq

proc appendEvent*(
  store: Store,
  eventId: string,
  runId: string,
  occurredAt: string,
  source: string,
  eventType: string,
  beadId: Option[string] = none(string),
  agentId: Option[string] = none(string),
  stage: Option[string] = none(string),
  payloadJson = "{}"
): int64 =
  store.db.transaction:
    result = store.appendEventInTransaction(
      eventId,
      runId,
      occurredAt,
      source,
      eventType,
      beadId = beadId,
      agentId = agentId,
      stage = stage,
      payloadJson = payloadJson
    )

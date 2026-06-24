import std/os

import tiny_sqlite

const
  StoreSchemaVersion* = 1
  DefaultBusyTimeoutMs* = 5000

type
  Store* = object
    path*: string
    db*: DbConn

const StoreSchema = """
CREATE TABLE IF NOT EXISTS schema_migrations (
  version INTEGER PRIMARY KEY,
  applied_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS runs (
  run_id TEXT PRIMARY KEY,
  repo_path TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  metadata_json TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS agents (
  agent_id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL REFERENCES runs(run_id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  kind TEXT NOT NULL DEFAULT 'agent',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
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
  updated_at TEXT NOT NULL,
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
  started_at TEXT NOT NULL,
  ended_at TEXT,
  source_event_id TEXT,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY(run_id, bead_id) REFERENCES beads(run_id, bead_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS events (
  event_id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL REFERENCES runs(run_id) ON DELETE CASCADE,
  seq INTEGER NOT NULL CHECK(seq > 0),
  occurred_at TEXT NOT NULL,
  source TEXT NOT NULL,
  event_type TEXT NOT NULL,
  bead_id TEXT,
  agent_id TEXT REFERENCES agents(agent_id) ON DELETE SET NULL,
  stage TEXT CHECK(stage IS NULL OR stage IN (
    'coding', 'validation', 'review', 'merge', 'blocked', 'complete', 'unknown'
  )),
  payload_json TEXT NOT NULL DEFAULT '{}',
  UNIQUE(run_id, seq)
);

CREATE TABLE IF NOT EXISTS event_cursors (
  run_id TEXT PRIMARY KEY REFERENCES runs(run_id) ON DELETE CASCADE,
  next_seq INTEGER NOT NULL CHECK(next_seq > 0)
);

CREATE TABLE IF NOT EXISTS snapshots (
  snapshot_id INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id TEXT NOT NULL REFERENCES runs(run_id) ON DELETE CASCADE,
  bead_id TEXT,
  captured_at TEXT NOT NULL,
  source TEXT NOT NULL,
  snapshot_json TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS errors (
  error_id INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id TEXT NOT NULL REFERENCES runs(run_id) ON DELETE CASCADE,
  occurred_at TEXT NOT NULL,
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
  db.exec("PRAGMA journal_mode=WAL")
  db.exec("PRAGMA busy_timeout = " & $DefaultBusyTimeoutMs)
  db.exec("PRAGMA foreign_keys=ON")
  Store(path: path, db: db)

proc initializeSchema*(store: Store) =
  store.db.execScript(StoreSchema)

proc initializeStore*(path: string): Store =
  result = openStore(path)
  initializeSchema(result)

proc close*(store: var Store) =
  store.db.close()

proc reserveEventSeq*(store: Store, runId: string): int64 =
  store.db.transaction:
    store.db.exec(
      "INSERT OR IGNORE INTO event_cursors(run_id, next_seq) VALUES(?, 1)",
      runId
    )
    result = store.db.value(
      "SELECT next_seq FROM event_cursors WHERE run_id = ?",
      runId
    ).get.fromDbValue(int64)
    store.db.exec(
      "UPDATE event_cursors SET next_seq = next_seq + 1 WHERE run_id = ?",
      runId
    )

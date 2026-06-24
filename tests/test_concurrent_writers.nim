import std/[os, osproc, streams, strutils, unittest]

import tiny_sqlite

import swarmy_core/events
import swarmy_core/persistence

const
  EventsPerWriter = 20
  WriterTimeoutMs = 30000

proc timestampFor(i: int): string =
  let second = i mod 60
  "2026-06-24T00:00:" & (if second < 10: "0" else: "") & $second & "Z"

proc insertRunAndBead(store: Store, runId, beadId: string) =
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
    VALUES(?, ?, 'Concurrent writer bead', '2026-06-24T00:00:00Z')
    """,
    runId,
    beadId
  )

proc scalarInt(store: Store, sql: string): int64 =
  store.db.value(sql).get.fromDbValue(int64)

proc runWriter(dbPath, runId, beadId, writerId: string, count: int) =
  var store = openStore(dbPath)
  try:
    for i in 0 ..< count:
      discard store.recordStageEvent(
        writerId & "-" & $i,
        runId,
        beadId,
        timestampFor(i),
        if i mod 2 == 0: stageCoding else: stageReview,
        source = "concurrency-test"
      )
      sleep(1)
  finally:
    store.close()

if paramCount() == 6 and paramStr(1) == "writer":
  runWriter(
    paramStr(2),
    paramStr(3),
    paramStr(4),
    paramStr(5),
    parseInt(paramStr(6))
  )
  quit(0)

proc withTempDb(body: proc(path: string)) =
  let dir = getTempDir() / "swarmy-concurrent-test-" & $getCurrentProcessId()
  let path = dir / "swarmy.db"
  if dirExists(dir):
    removeDir(dir)
  createDir(dir)
  try:
    body(path)
  finally:
    removeDir(dir)

suite "concurrent writers":
  test "process writers preserve run isolation and cursor uniqueness":
    withTempDb proc(path: string) =
      var store = initializeStore(path)
      try:
        store.insertRunAndBead("run-a", "bead-a")
        store.insertRunAndBead("run-b", "bead-b")
      finally:
        store.close()

      let exe = getAppFilename()
      let writerSpecs = [
        ("run-a", "bead-a", "writer-a1"),
        ("run-a", "bead-a", "writer-a2"),
        ("run-b", "bead-b", "writer-b1"),
        ("run-b", "bead-b", "writer-b2"),
      ]

      var processes: seq[Process]
      for spec in writerSpecs:
        let (runId, beadId, writerId) = spec
        processes.add startProcess(
          exe,
          workingDir = getCurrentDir(),
          args = @[
            "writer",
            path,
            runId,
            beadId,
            writerId,
            $EventsPerWriter,
          ],
          options = {poStdErrToStdOut}
        )

      for process in processes:
        let exitCode = process.waitForExit(WriterTimeoutMs)
        let output = process.outputStream.readAll()
        if exitCode != 0:
          echo output
        check exitCode == 0
        process.close()

      var verify = openStore(path)
      try:
        let perRun = EventsPerWriter * 2
        check verify.scalarInt("SELECT COUNT(*) FROM events") == perRun * 2
        check verify.scalarInt("SELECT COUNT(*) FROM events WHERE run_id = 'run-a'") == perRun
        check verify.scalarInt("SELECT COUNT(*) FROM events WHERE run_id = 'run-b'") == perRun
        check verify.scalarInt("SELECT COUNT(DISTINCT seq) FROM events WHERE run_id = 'run-a'") == perRun
        check verify.scalarInt("SELECT COUNT(DISTINCT seq) FROM events WHERE run_id = 'run-b'") == perRun
        check verify.scalarInt("SELECT MIN(seq) FROM events WHERE run_id = 'run-a'") == 1
        check verify.scalarInt("SELECT MIN(seq) FROM events WHERE run_id = 'run-b'") == 1
        check verify.scalarInt("SELECT MAX(seq) FROM events WHERE run_id = 'run-a'") == perRun
        check verify.scalarInt("SELECT MAX(seq) FROM events WHERE run_id = 'run-b'") == perRun
        check verify.scalarInt("SELECT next_seq FROM event_cursors WHERE run_id = 'run-a'") == perRun + 1
        check verify.scalarInt("SELECT next_seq FROM event_cursors WHERE run_id = 'run-b'") == perRun + 1
        check verify.scalarInt("SELECT COUNT(*) FROM events WHERE run_id = 'run-a' AND bead_id != 'bead-a'") == 0
        check verify.scalarInt("SELECT COUNT(*) FROM events WHERE run_id = 'run-b' AND bead_id != 'bead-b'") == 0
      finally:
        verify.close()

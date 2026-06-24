import std/[os, osproc, streams, strutils, times, unittest]

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

proc runWriter(
  dbPath,
  runId,
  beadId,
  writerId: string,
  count: int,
  readyDir,
  startPath,
  resultDir: string
) =
  writeFile(readyDir / writerId, "ready\n")
  while not fileExists(startPath):
    sleep(1)

  let started = epochTime()
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

  let finished = epochTime()
  writeFile(resultDir / writerId, $started & "\n" & $finished & "\n")

if paramCount() == 9 and paramStr(1) == "writer":
  runWriter(
    paramStr(2),
    paramStr(3),
    paramStr(4),
    paramStr(5),
    parseInt(paramStr(6)),
    paramStr(7),
    paramStr(8),
    paramStr(9)
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

proc waitForReadyFiles(readyDir: string, writerIds: openArray[string]) =
  let deadline = epochTime() + 5.0
  while epochTime() < deadline:
    var ready = true
    for writerId in writerIds:
      ready = ready and fileExists(readyDir / writerId)
    if ready:
      return
    sleep(5)

  raise newException(IOError, "timed out waiting for writer readiness markers")

proc waitForProcess(process: Process): int =
  result = process.waitForExit(WriterTimeoutMs)
  if process.running():
    process.kill()
    discard process.waitForExit(1000)
    result = -1

proc assertWriterOverlap(resultDir: string, writerIds: openArray[string]) =
  var latestStart = 0.0
  var earliestFinish = high(float)

  for writerId in writerIds:
    let lines = readFile(resultDir / writerId).strip().splitLines()
    check lines.len == 2
    let started = parseFloat(lines[0])
    let finished = parseFloat(lines[1])
    latestStart = max(latestStart, started)
    earliestFinish = min(earliestFinish, finished)

  check latestStart <= earliestFinish

suite "concurrent writers":
  test "process writers preserve run isolation and cursor uniqueness":
    withTempDb proc(path: string) =
      let baseDir = parentDir(path)
      let readyDir = baseDir / "ready"
      let resultDir = baseDir / "results"
      let startPath = baseDir / "start"
      createDir(readyDir)
      createDir(resultDir)

      var store = initializeStore(path)
      try:
        store.insertRunAndBead("run-a", "bead-a")
        store.insertRunAndBead("run-b", "bead-b")
      finally:
        store.close()

      let exe = getAppFilename()
      let writerIds = ["writer-a1", "writer-a2", "writer-b1", "writer-b2"]
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
            readyDir,
            startPath,
            resultDir,
          ],
          options = {poStdErrToStdOut}
        )

      waitForReadyFiles(readyDir, writerIds)

      var lockStore = openStore(path)
      lockStore.db.exec("BEGIN IMMEDIATE")
      writeFile(startPath, "go\n")
      sleep(100)
      lockStore.db.exec("COMMIT")
      lockStore.close()

      for process in processes:
        let exitCode = process.waitForProcess()
        let output = process.outputStream.readAll()
        if exitCode != 0:
          echo output
        check exitCode == 0
        process.close()

      assertWriterOverlap(resultDir, writerIds)

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
        check verify.scalarInt("SELECT COUNT(*) FROM events WHERE run_id = 'run-a' AND event_id LIKE 'writer-a1-%'") == EventsPerWriter
        check verify.scalarInt("SELECT COUNT(*) FROM events WHERE run_id = 'run-a' AND event_id LIKE 'writer-a2-%'") == EventsPerWriter
        check verify.scalarInt("SELECT COUNT(*) FROM events WHERE run_id = 'run-b' AND event_id LIKE 'writer-b1-%'") == EventsPerWriter
        check verify.scalarInt("SELECT COUNT(*) FROM events WHERE run_id = 'run-b' AND event_id LIKE 'writer-b2-%'") == EventsPerWriter
        check verify.scalarInt("SELECT COUNT(*) FROM events WHERE run_id = 'run-a' AND event_id LIKE 'writer-b%'") == 0
        check verify.scalarInt("SELECT COUNT(*) FROM events WHERE run_id = 'run-b' AND event_id LIKE 'writer-a%'") == 0
      finally:
        verify.close()

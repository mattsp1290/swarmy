import std/[options, os, osproc, strutils, times, unittest]

import tiny_sqlite

import swarmy_core/events
import swarmy_core/persistence

const
  RestartTimeoutMs = 30000
  RunId = "restart-run"
  BeadId = "restart-bead"

proc insertRunAndBead(store: Store) =
  store.db.exec(
    """
    INSERT INTO runs(run_id, repo_path, created_at, updated_at)
    VALUES(?, '/restart-repo', '2026-06-24T00:00:00Z', '2026-06-24T00:00:00Z')
    """,
    RunId
  )
  store.db.exec(
    """
    INSERT INTO beads(run_id, bead_id, title, updated_at)
    VALUES(?, ?, 'Restart persistence bead', '2026-06-24T00:00:00Z')
    """,
    RunId,
    BeadId
  )

proc scalarInt(store: Store, sql: string): int64 =
  store.db.value(sql).get.fromDbValue(int64)

proc writeStage(dbPath: string) =
  var store = initializeStore(dbPath)
  try:
    store.insertRunAndBead()
    discard store.recordStageEvent(
      "restart-event-1",
      RunId,
      BeadId,
      "2026-06-24T00:00:01Z",
      stageComplete,
      source = "restart-test"
    )
  finally:
    store.close()

proc readStage(dbPath: string) =
  var store = openStore(dbPath)
  try:
    let found = store.latestBeadStage(RunId, BeadId)
    if found.isNone:
      stderr.write("missing bead stage after restart\n")
      quit(3)

    let stage = found.get
    if stage.stage != stageComplete:
      stderr.write("unexpected stage after restart: " & $stage.stage & "\n")
      quit(4)
    if stage.eventId != "restart-event-1":
      stderr.write("unexpected event id after restart: " & stage.eventId & "\n")
      quit(5)
    if stage.seq != 1:
      stderr.write("unexpected sequence after restart: " & $stage.seq & "\n")
      quit(6)

    let nextSeq = store.recordStageEvent(
      "restart-event-2",
      RunId,
      BeadId,
      "2026-06-24T00:00:02Z",
      stageReview,
      source = "restart-test"
    )
    if nextSeq != 2:
      stderr.write("unexpected post-restart sequence: " & $nextSeq & "\n")
      quit(7)

    let latest = store.latestBeadStage(RunId, BeadId)
    if latest.isNone:
      stderr.write("missing latest stage after post-restart append\n")
      quit(8)
    let appended = latest.get
    if appended.stage != stageReview:
      stderr.write("unexpected post-restart stage: " & $appended.stage & "\n")
      quit(9)
    if appended.eventId != "restart-event-2":
      stderr.write(
        "unexpected post-restart event id: " & appended.eventId & "\n"
      )
      quit(10)
    if appended.seq != 2:
      stderr.write("unexpected latest sequence: " & $appended.seq & "\n")
      quit(11)

    if store.scalarInt("SELECT COUNT(*) FROM events") != 2:
      stderr.write("unexpected persisted event count after restart\n")
      quit(12)
    if store.scalarInt("SELECT next_seq FROM event_cursors WHERE run_id = '" & RunId & "'") != 3:
      stderr.write("unexpected persisted cursor after restart\n")
      quit(13)

    stdout.write(
      "reader " & stage.runId & " " & stage.beadId & " " & $stage.stage &
        " then " & $appended.stage & "\n"
    )
  finally:
    store.close()

if paramCount() == 2 and paramStr(1) == "writer":
  writeStage(paramStr(2))
  quit(0)

if paramCount() == 2 and paramStr(1) == "reader":
  readStage(paramStr(2))
  quit(0)

proc withTempDb(body: proc(path: string)) =
  var dir = ""
  for attempt in 0 ..< 1000:
    let candidate = getTempDir() / "swarmy-restart-test-" &
      $getCurrentProcessId() & "-" & $epochTime() & "-" & $attempt
    if not dirExists(candidate):
      createDir(candidate)
      dir = candidate
      break
  if dir.len == 0:
    raise newException(IOError, "could not create unique restart test directory")

  let path = dir / "swarmy.db"
  try:
    body(path)
  finally:
    removeDir(dir)

proc waitForProcess(process: Process): tuple[exitCode: int, output: string] =
  result.exitCode = process.waitForExit(RestartTimeoutMs)
  if process.running():
    process.kill()
    discard process.waitForExit(1000)
    result.exitCode = -1

proc runHelper(mode, dbPath: string): tuple[exitCode: int, output: string] =
  let logPath = parentDir(dbPath) / (mode & ".log")
  let command = quoteShellPosix(getAppFilename()) & " " &
    quoteShellPosix(mode) & " " & quoteShellPosix(dbPath) & " > " &
    quoteShellPosix(logPath) & " 2>&1"
  let process = startProcess(
    "/bin/sh",
    workingDir = getCurrentDir(),
    args = @["-c", command],
    options = {poUsePath, poParentStreams}
  )
  try:
    result = process.waitForProcess()
    if fileExists(logPath):
      result.output = readFile(logPath)
  finally:
    process.close()

suite "restart persistence":
  test "separate processes read back persisted run bead stage":
    withTempDb proc(path: string) =
      let written = runHelper("writer", path)
      if written.exitCode != 0:
        echo written.output
      check written.exitCode == 0

      let read = runHelper("reader", path)
      if read.exitCode != 0:
        echo read.output
      check read.exitCode == 0
      check read.output.strip() == "reader restart-run restart-bead complete then review"

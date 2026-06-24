import std/[options, os, osproc, streams, strutils, times, unittest]

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

    stdout.write(stage.runId & " " & stage.beadId & " " & $stage.stage & "\n")
  finally:
    store.close()

if paramCount() == 2 and paramStr(1) == "writer":
  writeStage(paramStr(2))
  quit(0)

if paramCount() == 2 and paramStr(1) == "reader":
  readStage(paramStr(2))
  quit(0)

proc withTempDb(body: proc(path: string)) =
  let dir = getTempDir() / "swarmy-restart-test-" & $getCurrentProcessId() &
    "-" & $epochTime().int
  let path = dir / "swarmy.db"
  if dirExists(dir):
    removeDir(dir)
  createDir(dir)
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
  result.output = process.outputStream.readAll()

proc runHelper(mode, dbPath: string): tuple[exitCode: int, output: string] =
  let process = startProcess(
    getAppFilename(),
    workingDir = getCurrentDir(),
    args = @[mode, dbPath],
    options = {poStdErrToStdOut}
  )
  result = process.waitForProcess()
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
      check read.output.strip() == "restart-run restart-bead complete"

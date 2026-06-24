import std/[os, strutils, times, unittest]

import tiny_sqlite

import swarmy_cli/doctor
import swarmy_core/persistence
import swarmy_core/run_metadata

proc withTempRepo(body: proc(repo: string)) =
  let dir = getTempDir() / "swarmy-doctor-test-" & $getCurrentProcessId() &
    "-" & $epochTime().int
  if dirExists(dir):
    removeDir(dir)
  createDir(dir)
  try:
    body(dir)
  finally:
    removeDir(dir)

suite "swarmy doctor":
  test "uninitialized repo reports not initialized and succeeds":
    withTempRepo proc(repo: string) =
      let result = doctor.run(@["--repo", repo])
      check result.exitCode == 0
      check "not initialized" in result.output
      check result.error == ""

  test "rejects unexpected arguments":
    let result = doctor.run(@["--bogus"])
    check result.exitCode == 2
    check "unexpected argument '--bogus'" in result.error

  test "initialized repo reports config, db path, and redacted errors":
    withTempRepo proc(repo: string) =
      let initialized = initRun(repo)
      let metadata = initialized.metadata

      var store = initializeStore(metadata.dbPath)
      try:
        store.db.exec(
          """
          INSERT INTO runs(run_id, repo_path, created_at, updated_at)
          VALUES(?, ?, '2026-06-24T00:00:00Z', '2026-06-24T00:00:00Z')
          """,
          metadata.runId,
          metadata.repoPath
        )
        store.db.exec(
          "INSERT INTO errors(run_id, occurred_at, severity, message, context_json) VALUES(?, '2026-06-24T00:00:00Z', 'error', ?, '{}')",
          metadata.runId,
          "boom token=supersecret happened"
        )
      finally:
        store.close()

      let result = doctor.run(@["--repo", repo])
      check result.exitCode == 0
      check metadata.runId in result.output
      check metadata.dbPath in result.output
      check "[error]" in result.output
      check "2026-06-24T00:00:00Z" in result.output
      check "[REDACTED]" in result.output
      check "supersecret" notin result.output

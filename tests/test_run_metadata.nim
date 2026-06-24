import std/[json, options, os, strutils, times, unittest]

import swarmy_core/run_metadata

proc withTempRepo(body: proc(path: string)) =
  let path = getTempDir() / "swarmy-test-" & $getCurrentProcessId() & "-" & $epochTime().int
  createDir(path)
  try:
    body(path)
  finally:
    removeDir(path)

suite "run metadata":
  test "init creates repo-local metadata":
    withTempRepo proc(repo: string) =
      let initialized = initRun(repo)

      check initialized.created
      check fileExists(repo / ".swarmy" / "run.json")
      check initialized.metadata.schemaVersion == 1
      check initialized.metadata.runId.startsWith("run-")
      check initialized.metadata.repoPath == normalizedPath(absolutePath(repo))
      check initialized.metadata.dbPath == normalizedPath(absolutePath(repo)) / ".swarmy" / "swarmy.db"

      let node = parseFile(repo / ".swarmy" / "run.json")
      check node["run_id"].getStr == initialized.metadata.runId

  test "init is idempotent":
    withTempRepo proc(repo: string) =
      let first = initRun(repo)
      let second = initRun(repo)

      check first.created
      check not second.created
      check second.metadata.runId == first.metadata.runId
      check second.metadata.createdAt == first.metadata.createdAt

  test "custom db path is recorded on first init":
    withTempRepo proc(repo: string) =
      let initialized = initRun(repo, some("/tmp/swarmy.db"))

      check initialized.metadata.dbPath == "/tmp/swarmy.db"

  test "symlinked metadata directory is rejected":
    withTempRepo proc(repo: string) =
      when defined(windows):
        skip()
      else:
        let target = getTempDir() / "swarmy-target-" & $getCurrentProcessId()
        createDir(target)
        try:
          createSymlink(target, repo / ".swarmy")
          expect ValueError:
            discard initRun(repo)
        finally:
          removeDir(target)

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
      check initialized.metadata.repoPath == canonicalRepoPath(repo)
      check initialized.metadata.dbPath == canonicalRepoPath(repo) / ".swarmy" / "swarmy.db"
      check initialized.metadata.configPath == canonicalRepoPath(repo) / ".swarmy" / "config.json"

      let node = parseFile(repo / ".swarmy" / "run.json")
      check node["run_id"].getStr == initialized.metadata.runId
      check node["config_path"].getStr == initialized.metadata.configPath

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

  test "relative custom db path is resolved under the repo":
    withTempRepo proc(repo: string) =
      let initialized = initRun(repo, some("state/swarmy.db"))

      check initialized.metadata.dbPath == canonicalRepoPath(repo) / "state" / "swarmy.db"

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

  test "symlinked repo path resolves to the real path":
    when defined(windows):
      skip()
    else:
      withTempRepo proc(repo: string) =
        let link = getTempDir() / "swarmy-repo-link-" & $getCurrentProcessId()
        try:
          createSymlink(repo, link)
          let initialized = initRun(link)

          check initialized.metadata.repoPath == canonicalRepoPath(repo)
          check fileExists(repo / ".swarmy" / "run.json")
        finally:
          if symlinkExists(link):
            removeFile(link)

  test "symlinked metadata file is rejected":
    withTempRepo proc(repo: string) =
      when defined(windows):
        skip()
      else:
        createDir(repo / ".swarmy")
        let target = getTempDir() / "swarmy-run-target-" & $getCurrentProcessId()
        writeFile(target, "{}")
        try:
          createSymlink(target, repo / ".swarmy" / "run.json")
          expect ValueError:
            discard initRun(repo)
        finally:
          removeFile(target)

import std/[os, times]

type TempRepo* = object
  root*: string
  repo*: string
  dbPath*: string

var tempRepoCounter = 0

proc newTempRepo*(prefix = "swarmy-test"): TempRepo =
  inc tempRepoCounter
  let root = getTempDir() / prefix & "-" & $getCurrentProcessId() &
    "-" & $epochTime().int & "-" & $tempRepoCounter
  let repo = root / "repo"
  createDir(root)
  createDir(repo)
  TempRepo(
    root: root,
    repo: repo,
    dbPath: root / "swarmy.db"
  )

proc cleanup*(temp: TempRepo) =
  if temp.root.len > 0 and dirExists(temp.root):
    removeDir(temp.root)

proc withTempRepo*(body: proc(temp: TempRepo)) =
  let temp = newTempRepo()
  try:
    body(temp)
  finally:
    temp.cleanup()

import std/[json, os, strutils, times, unittest]

import swarmy_cli/preflight
import swarmy_core/bd_adapter

# --- fixtures ---------------------------------------------------------------

type
  FakeGit = object
    status: tuple[ec: int, output: string]
    branch: tuple[ec: int, output: string]
    revList: tuple[ec: int, output: string]
    lsRemote: tuple[ec: int, output: string]
    forEachRef: tuple[ec: int, output: string]
    checkIgnore: tuple[ec: int, output: string]

proc cleanGit(): FakeGit =
  ## A checkout that passes every git-driven check: clean tree, on main, in sync,
  ## origin reachable, no stale branches, reviews/ excluded.
  FakeGit(
    status: (0, ""),
    branch: (0, "main\n"),
    revList: (0, "0\t0\n"),
    lsRemote: (0, "deadbeef\tHEAD\n"),
    forEachRef: (0, "refs/heads/main\nrefs/remotes/origin/main\n"),
    checkIgnore: (0, "")
  )

proc runnerFor(cfg: FakeGit): GitRunner =
  result = proc(repo: string, args: seq[string]): tuple[exitCode: int, output: string] =
    if args.len == 0:
      return (1, "")
    case args[0]
    of "status": (cfg.status.ec, cfg.status.output)
    of "rev-parse": (cfg.branch.ec, cfg.branch.output)
    of "rev-list": (cfg.revList.ec, cfg.revList.output)
    of "ls-remote": (cfg.lsRemote.ec, cfg.lsRemote.output)
    of "for-each-ref": (cfg.forEachRef.ec, cfg.forEachRef.output)
    of "check-ignore": (cfg.checkIgnore.ec, cfg.checkIgnore.output)
    else: (1, "unexpected git args: " & args.join(" "))

proc bead(id: string, issueType: string): BeadSnapshot =
  BeadSnapshot(id: id, title: id, status: "open", issueType: issueType,
    rawJson: newJObject())

proc readyWith(beads: seq[BeadSnapshot]): ReadyReader =
  result = proc(repo: string): tuple[ok: bool, beads: seq[BeadSnapshot], error: string] =
    (true, beads, "")

proc readyUnavailable(): ReadyReader =
  result = proc(repo: string): tuple[ok: bool, beads: seq[BeadSnapshot], error: string] =
    (false, @[], "bd executable not found")

proc statusOf(checks: seq[PreflightCheck], name: string): CheckStatus =
  for c in checks:
    if c.name == name:
      return c.status
  raise newException(ValueError, "no check named " & name)

proc withTempRepo(body: proc(repo: string)) =
  let dir = getTempDir() / "swarmy-preflight-test-" & $getCurrentProcessId() &
    "-" & $epochTime().int
  if dirExists(dir):
    removeDir(dir)
  createDir(dir)
  createDir(dir / ".git")
  try:
    body(dir)
  finally:
    removeDir(dir)

# --- classifier (owned by task 03) ------------------------------------------

suite "classifyReady":
  test "splits epics from concrete work case-insensitively":
    let beads = @[
      bead("swarmy-1", "epic"),
      bead("swarmy-2", "task"),
      bead("swarmy-3", "EPIC"),
      bead("swarmy-4", "feature"),
      bead("swarmy-5", "chore"),
      bead("swarmy-6", "bug")
    ]
    let mix = classifyReady(beads)
    check mix.epics.len == 2
    check mix.concrete.len == 4
    check mix.epics[0].id == "swarmy-1"
    check mix.concrete[0].id == "swarmy-2"

  test "isEpic ignores surrounding whitespace and case":
    check bead("a", " Epic ").isEpic
    check not bead("b", "task").isEpic
    check not bead("c", "").isEpic

# --- preflight checks -------------------------------------------------------

suite "swarmy preflight":
  test "clean ready repo passes with exit 0":
    withTempRepo proc(repo: string) =
      let result = preflight.run(
        @["--repo", repo],
        runnerFor(cleanGit()),
        readyWith(@[bead("swarmy-1", "task")])
      )
      check result.exitCode == 0
      let checks = buildChecks(repo, "main", runnerFor(cleanGit()),
        readyWith(@[bead("swarmy-1", "task")]))
      check statusOf(checks, "working-tree") == csPass
      check statusOf(checks, "lock-file") == csPass
      check statusOf(checks, "stale-branches") == csPass
      check statusOf(checks, "beads") == csPass
      check "READY" in result.output

  test "dirty working tree fails with exit 1":
    withTempRepo proc(repo: string) =
      var cfg = cleanGit()
      cfg.status = (0, " M src/foo.nim\n?? bar.txt\n")
      let result = preflight.run(@["--repo", repo], runnerFor(cfg),
        readyWith(@[bead("swarmy-1", "task")]))
      check result.exitCode == 1
      check "NOT READY" in result.output
      check "[FAIL] working-tree" in result.output

  test "stale loop branch present fails with exit 1":
    withTempRepo proc(repo: string) =
      var cfg = cleanGit()
      cfg.forEachRef = (0,
        "refs/heads/main\nrefs/heads/bead-swarm/iteration-7\n" &
        "refs/remotes/origin/ralph/iteration-3\n")
      let result = preflight.run(@["--repo", repo], runnerFor(cfg),
        readyWith(@[bead("swarmy-1", "task")]))
      check result.exitCode == 1
      check "[FAIL] stale-branches" in result.output
      check "bead-swarm/iteration-7" in result.output

  test "lock file present fails with exit 1":
    withTempRepo proc(repo: string) =
      writeFile(repo / ".git" / "bead-swarm.lock", "owner-token\n")
      let result = preflight.run(@["--repo", repo], runnerFor(cleanGit()),
        readyWith(@[bead("swarmy-1", "task")]))
      check result.exitCode == 1
      check "[FAIL] lock-file" in result.output

  test "only epics ready warns but stays ready (exit 0)":
    withTempRepo proc(repo: string) =
      let result = preflight.run(@["--repo", repo], runnerFor(cleanGit()),
        readyWith(@[bead("swarmy-1", "epic"), bead("swarmy-2", "epic")]))
      check result.exitCode == 0
      let checks = buildChecks(repo, "main", runnerFor(cleanGit()),
        readyWith(@[bead("swarmy-1", "epic"), bead("swarmy-2", "epic")]))
      check statusOf(checks, "beads") == csWarn
      check "only 2 epic(s) ready" in result.output

  test "wrong branch and missing origin warn but do not fail":
    withTempRepo proc(repo: string) =
      var cfg = cleanGit()
      cfg.branch = (0, "bead-swarm/iteration-9\n")
      cfg.revList = (128, "fatal: bad revision\n")
      cfg.lsRemote = (2, "fatal: 'origin' does not appear to be a git repository\n")
      let result = preflight.run(@["--repo", repo], runnerFor(cfg),
        readyWith(@[bead("swarmy-1", "task")]))
      check result.exitCode == 0
      check "[WARN] branch" in result.output
      check "[WARN] sync" in result.output
      check "[WARN] origin" in result.output

  test "reviews not excluded warns":
    withTempRepo proc(repo: string) =
      var cfg = cleanGit()
      cfg.checkIgnore = (1, "")
      let checks = buildChecks(repo, "main", runnerFor(cfg),
        readyWith(@[bead("swarmy-1", "task")]))
      check statusOf(checks, "reviews-excluded") == csWarn

  test "unavailable beads warns rather than failing":
    withTempRepo proc(repo: string) =
      let result = preflight.run(@["--repo", repo], runnerFor(cleanGit()),
        readyUnavailable())
      check result.exitCode == 0
      check "[WARN] beads: bd unavailable" in result.output

  test "json output is structured and machine-readable":
    withTempRepo proc(repo: string) =
      let result = preflight.run(@["--repo", repo, "--json"], runnerFor(cleanGit()),
        readyWith(@[bead("swarmy-1", "task")]))
      check result.exitCode == 0
      let parsed = parseJson(result.output)
      check parsed["ready"].getBool
      check parsed["status"].getStr == "PASS"
      check parsed["checks"].kind == JArray
      check parsed["checks"].len == 8

  test "rejects unexpected arguments with exit 2":
    let result = preflight.run(@["--bogus"], runnerFor(cleanGit()),
      readyWith(@[]))
    check result.exitCode == 2
    check "unexpected argument '--bogus'" in result.error

  test "--main overrides the expected base branch":
    withTempRepo proc(repo: string) =
      var cfg = cleanGit()
      cfg.branch = (0, "trunk\n")
      let checks = buildChecks(repo, "trunk", runnerFor(cfg),
        readyWith(@[bead("swarmy-1", "task")]))
      check statusOf(checks, "branch") == csPass

## `swarmy preflight` — loop-readiness checks for /bead-swarm and /ralph runs.
##
## Doctor (`doctor.nim`) reports *run health* from swarmy's own SQLite store.
## Preflight answers a different question: is this checkout *ready to start a
## loop iteration*? It inspects git refs, the working tree, lock files, and Beads
## readiness — all strictly **read-only** (no fetch, no ref mutation, no bd
## writes), mirroring the iter-23 lesson that a diagnostic must never mutate the
## thing it diagnoses.
##
## Git and Beads access are injected (`GitRunner` / `ReadyReader`) so the checks
## are deterministic under test; `run` wires the real implementations.

import std/[json, os, osproc, streams, strutils]

import swarmy_cli/dispatch_types
import swarmy_core/bd_adapter
import swarmy_core/diagnostics

type
  CheckStatus* = enum
    csPass = "PASS"
    csWarn = "WARN"
    csFail = "FAIL"

  PreflightCheck* = object
    name*: string
    status*: CheckStatus
    detail*: string

  GitRunner* = proc(repo: string, args: seq[string]): tuple[exitCode: int, output: string] {.closure.}

  ReadyReader* = proc(repo: string): tuple[ok: bool, beads: seq[BeadSnapshot], error: string] {.closure.}

  PreflightOptions = object
    repo: string
    mainBranch: string
    json: bool

const DefaultMainBranch = "main"

# --- argument parsing -------------------------------------------------------

proc requireValue(args: seq[string], i: int, flag: string): tuple[ok: bool, value: string, error: string] =
  if i + 1 >= args.len or args[i + 1].startsWith("--"):
    return (false, "", "swarmy preflight: " & flag & " requires a value\n")
  (true, args[i + 1], "")

proc parseArgs(args: seq[string]): tuple[ok: bool, options: PreflightOptions, error: string] =
  result.options.repo = "."
  result.options.mainBranch = DefaultMainBranch

  var i = 0
  while i < args.len:
    case args[i]
    of "--repo":
      let value = requireValue(args, i, "--repo")
      if not value.ok:
        return (false, result.options, value.error)
      result.options.repo = value.value
      i += 2
    of "--main":
      let value = requireValue(args, i, "--main")
      if not value.ok:
        return (false, result.options, value.error)
      result.options.mainBranch = value.value
      i += 2
    of "--json":
      result.options.json = true
      i += 1
    else:
      return (false, result.options, "swarmy preflight: unexpected argument '" & args[i] & "'\n")

  (true, result.options, "")

# --- real git / beads runners ----------------------------------------------

proc realGit(repo: string, args: seq[string]): tuple[exitCode: int, output: string] =
  ## Read-only git invocation. Only callers in this module supply args, and every
  ## subcommand used here (status, rev-parse, rev-list, ls-remote, for-each-ref,
  ## check-ignore) is non-mutating.
  if findExe("git").len == 0:
    return (127, "git executable not found")
  var process: Process
  try:
    process = startProcess(
      "git",
      workingDir = repo,
      args = args,
      options = {poUsePath, poStdErrToStdOut}
    )
  except OSError as error:
    return (127, error.msg)
  try:
    let output = process.outputStream.readAll()
    let code = process.waitForExit()
    (code, output)
  finally:
    process.close()

proc realReady(repo: string): tuple[ok: bool, beads: seq[BeadSnapshot], error: string] =
  try:
    (true, readReadyBeads(repo), "")
  except BdSnapshotError as error:
    (false, @[], $error.kind & ": " & error.msg)
  except CatchableError as error:
    (false, @[], error.msg)

# --- checks -----------------------------------------------------------------

proc check(name: string, status: CheckStatus, detail: string): PreflightCheck =
  PreflightCheck(name: name, status: status, detail: detail)

proc resolveMainBranch(repo, requested: string): string =
  ## `--main` wins; otherwise honor a `.ralph` file's `main_branch=BRANCH` line
  ## if present (this is the format the loop tooling and the `/review` skill use).
  ## A `.ralph` without a parseable `main_branch=` line falls back to the default.
  if requested != DefaultMainBranch:
    return requested
  let ralph = repo / ".ralph"
  if fileExists(ralph):
    try:
      for line in readFile(ralph).splitLines():
        let stripped = line.strip()
        if stripped.startsWith("main_branch="):
          let value = stripped["main_branch=".len .. ^1].strip()
          if value.len > 0:
            return value
    except CatchableError:
      discard
  requested

proc loopBranchName(refName: string): string =
  ## The branch name within a full ref, dropping `refs/heads/` or
  ## `refs/remotes/<remote>/` so the loop-namespace match anchors on real path
  ## segments (e.g. `feature/ralph/iteration-x` is NOT a loop branch).
  let name = refName.strip()
  if name.startsWith("refs/heads/"):
    return name["refs/heads/".len .. ^1]
  if name.startsWith("refs/remotes/"):
    let rest = name["refs/remotes/".len .. ^1]
    let slash = rest.find('/')
    if slash >= 0:
      return rest[slash + 1 .. ^1]
    return rest
  name

proc isLoopBranch(branch: string): bool =
  branch.startsWith("ralph/iteration-") or
    branch.startsWith("bead-swarm/iteration-") or
    branch.startsWith("bead-swarm/recovery-")

proc staleLoopBranches(refs: string): seq[string] =
  ## Loop-namespace branches that should be cleaned up between runs. The match
  ## anchors on the branch name's leading path segment, so unrelated branches
  ## like `feature/ralph/iteration-notes` are not flagged. The reported name
  ## keeps its location (`origin/...` for remotes) for actionable output.
  for raw in refs.splitLines():
    let name = raw.strip()
    if name.len == 0:
      continue
    if isLoopBranch(loopBranchName(name)):
      let reported =
        if name.startsWith("refs/heads/"): name["refs/heads/".len .. ^1]
        elif name.startsWith("refs/remotes/"): name["refs/remotes/".len .. ^1]
        else: name
      result.add reported

proc buildChecks*(
  repo: string,
  mainBranch: string,
  git: GitRunner,
  ready: ReadyReader
): seq[PreflightCheck] =
  # 1. Clean working tree.
  let status = git(repo, @["status", "--porcelain"])
  if status.exitCode != 0:
    result.add check("working-tree", csFail, "git status failed: " & status.output.strip())
  elif status.output.strip().len == 0:
    result.add check("working-tree", csPass, "clean")
  else:
    let n = status.output.strip().splitLines().len
    result.add check("working-tree", csFail, $n & " uncommitted change(s)")

  # 2. On the expected base branch.
  let branchResult = git(repo, @["rev-parse", "--abbrev-ref", "HEAD"])
  let branch = branchResult.output.strip()
  if branchResult.exitCode != 0:
    result.add check("branch", csWarn, "cannot determine current branch")
  elif branch == mainBranch:
    result.add check("branch", csPass, "on " & mainBranch)
  else:
    result.add check("branch", csWarn, "on '" & branch & "', expected '" & mainBranch & "'")

  # 3. Up to date with origin/<main>.
  let counts = git(repo, @["rev-list", "--left-right", "--count",
    "origin/" & mainBranch & "...HEAD"])
  if counts.exitCode != 0:
    result.add check("sync", csWarn, "cannot compare with origin/" & mainBranch)
  else:
    let parts = counts.output.strip().splitWhitespace()
    if parts.len == 2:
      let behind = parts[0]
      let ahead = parts[1]
      if behind != "0":
        result.add check("sync", csFail, "behind origin/" & mainBranch & " by " & behind)
      elif ahead != "0":
        result.add check("sync", csWarn, "ahead of origin/" & mainBranch & " by " & ahead)
      else:
        result.add check("sync", csPass, "up to date with origin/" & mainBranch)
    else:
      result.add check("sync", csWarn, "unexpected rev-list output")

  # 4. Origin reachable.
  let lsRemote = git(repo, @["ls-remote", "--exit-code", "origin", "HEAD"])
  if lsRemote.exitCode == 0:
    result.add check("origin", csPass, "reachable")
  else:
    result.add check("origin", csWarn, "origin unreachable or unset")

  # 5. No stale loop branches.
  let refs = git(repo, @["for-each-ref", "--format=%(refname)",
    "refs/heads/", "refs/remotes/"])
  if refs.exitCode != 0:
    result.add check("stale-branches", csWarn, "cannot list refs")
  else:
    let stale = staleLoopBranches(refs.output)
    if stale.len == 0:
      result.add check("stale-branches", csPass, "none")
    else:
      result.add check("stale-branches", csFail,
        $stale.len & " stale loop branch(es): " & stale.join(", "))

  # 6. No lock file.
  if fileExists(repo / ".git" / "bead-swarm.lock"):
    result.add check("lock-file", csFail, ".git/bead-swarm.lock present")
  else:
    result.add check("lock-file", csPass, "absent")

  # 7. reviews/ excluded from version control.
  let ignored = git(repo, @["check-ignore", "-q", "reviews/"])
  if ignored.exitCode == 0:
    result.add check("reviews-excluded", csPass, "reviews/ is git-ignored")
  else:
    result.add check("reviews-excluded", csWarn,
      "reviews/ not excluded (expected in .git/info/exclude)")

  # 8 & 9. Beads readiness + epic/task mix (shared classifier).
  let bd = ready(repo)
  if not bd.ok:
    result.add check("beads", csWarn, "bd unavailable: " & bd.error)
  elif bd.beads.len == 0:
    result.add check("beads", csWarn, "no ready beads")
  else:
    let mix = classifyReady(bd.beads)
    if mix.concrete.len == 0:
      result.add check("beads", csWarn,
        "only " & $mix.epics.len & " epic(s) ready (no concrete work)")
    else:
      result.add check("beads", csPass,
        $mix.concrete.len & " concrete + " & $mix.epics.len & " epic(s) ready")

# --- rendering --------------------------------------------------------------

proc worstStatus(checks: seq[PreflightCheck]): CheckStatus =
  result = csPass
  for c in checks:
    if c.status == csFail:
      return csFail
    if c.status == csWarn:
      result = csWarn

proc renderText(checks: seq[PreflightCheck]): string =
  result = "swarmy preflight\n"
  for c in checks:
    result.add "  [" & $c.status & "] " & c.name & ": " & c.detail & "\n"
  case worstStatus(checks)
  of csFail: result.add "result: NOT READY (one or more checks failed)\n"
  of csWarn: result.add "result: READY WITH WARNINGS\n"
  of csPass: result.add "result: READY\n"

proc renderJson(checks: seq[PreflightCheck]): string =
  var arr = newJArray()
  for c in checks:
    arr.add %*{"name": c.name, "status": $c.status, "detail": c.detail}
  let worst = worstStatus(checks)
  let doc = %*{
    "ready": worst != csFail,
    "status": $worst,
    "checks": arr
  }
  doc.pretty & "\n"

proc exitCodeFor(checks: seq[PreflightCheck]): int =
  if worstStatus(checks) == csFail: 1 else: 0

# --- entry point ------------------------------------------------------------

proc run*(
  args: seq[string],
  git: GitRunner = realGit,
  ready: ReadyReader = realReady
): CliResult =
  let parsed = parseArgs(args)
  if not parsed.ok:
    return CliResult(exitCode: 2, error: parsed.error)

  try:
    let mainBranch = resolveMainBranch(parsed.options.repo, parsed.options.mainBranch)
    let checks = buildChecks(parsed.options.repo, mainBranch, git, ready)
    let rendered =
      if parsed.options.json: renderJson(checks)
      else: renderText(checks)
    CliResult(exitCode: exitCodeFor(checks), output: redactDiagnostic(rendered))
  except CatchableError as err:
    CliResult(exitCode: 1, error: "swarmy preflight: " & err.msg & "\n")

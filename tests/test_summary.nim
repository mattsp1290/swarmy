import std/[json, os, strutils, times, unittest]

import swarmy_cli/summary
import swarmy_core/bd_adapter

# --- fixtures ---------------------------------------------------------------

const FixedClock = "2026-06-24T12:00:00Z"

proc fixedClock(): string = FixedClock

proc bead(id, issueType, status: string): BeadSnapshot =
  BeadSnapshot(id: id, title: id, status: status, issueType: issueType,
    rawJson: newJObject())

proc readyWith(beads: seq[BeadSnapshot]): BeadReader =
  result = proc(repo: string): tuple[ok: bool, beads: seq[BeadSnapshot], error: string] =
    (true, beads, "")

proc unavailable(): BeadReader =
  result = proc(repo: string): tuple[ok: bool, beads: seq[BeadSnapshot], error: string] =
    (false, @[], "bd executable not found")

proc withTempRepo(body: proc(repo: string)) =
  let dir = getTempDir() / "swarmy-summary-test-" & $getCurrentProcessId() &
    "-" & $epochTime().int
  if dirExists(dir):
    removeDir(dir)
  createDir(dir)
  try:
    body(dir)
  finally:
    removeDir(dir)

proc writeIteration(repo: string, iteration: int, body: string) =
  let dir = repo / ".agents/bead-swarm/history"
  createDir(dir)
  writeFile(dir / ("iteration-" & $iteration & ".json"), body)

# --- tests ------------------------------------------------------------------

suite "swarmy summary":
  test "zero history files yields a valid empty-ish manifest, exit 0":
    withTempRepo proc(repo: string) =
      let result = summary.run(@["--repo", repo, "--json"],
        readyWith(@[]), readyWith(@[]), fixedClock)
      check result.exitCode == 0
      let parsed = parseJson(result.output)
      check parsed["history_count"].getInt == 0
      check parsed["generated_at"].getStr == FixedClock
      check parsed["last_iteration"].getInt == 0

  test "markdown for empty history notes no iterations":
    withTempRepo proc(repo: string) =
      let result = summary.run(@["--repo", repo],
        readyWith(@[]), readyWith(@[]), fixedClock)
      check result.exitCode == 0
      check "no iteration history yet" in result.output

  test "reconciles multiple iterations and dedups cumulative done":
    withTempRepo proc(repo: string) =
      writeIteration(repo, 1, """
        {"iteration":1,"branch":"bead-swarm/iteration-1-a","main_branch":"main",
         "merge_target":"main","status":"complete","beads_done":["a-1","a-2"],
         "validation":["nimble build: pass"],"reviews":[]}
      """)
      writeIteration(repo, 2, """
        {"iteration":2,"branch":"bead-swarm/iteration-2-b","main_branch":"main",
         "merge_target":"main","status":"complete","beads_done":["a-2","a-3"],
         "validation":["nimble test: pass"],
         "reviews":[{"reviewer":"redowl","verdict":"APPROVE"}]}
      """)
      let listed = readyWith(@[bead("a-4", "task", "open"), bead("a-1", "task", "closed")])
      let ready = readyWith(@[bead("a-4", "task", "open"), bead("e-9", "epic", "open")])
      let result = summary.run(@["--repo", repo, "--json"], ready, listed, fixedClock)
      check result.exitCode == 0
      let parsed = parseJson(result.output)
      # Cumulative, de-duplicated done set across both iterations.
      let done = parsed["beads_done"].to(seq[string])
      check done == @["a-1", "a-2", "a-3"]
      # Last-iteration fields win.
      check parsed["last_iteration"].getInt == 2
      check parsed["last_branch"].getStr == "bead-swarm/iteration-2-b"
      check parsed["reviews"].len == 1
      check parsed["reviews"][0]["verdict"].getStr == "APPROVE"
      # Open count from bd list excludes the closed bead.
      check parsed["beads_open"].getInt == 1
      # recommended_next excludes epics.
      let nextUp = parsed["recommended_next"].to(seq[string])
      check nextUp == @["a-4"]

  test "blocked iteration reports validation FAIL and partial risk":
    withTempRepo proc(repo: string) =
      writeIteration(repo, 1, """
        {"iteration":1,"branch":"bead-swarm/iteration-1-x","main_branch":"main",
         "merge_target":"main","status":"blocked","beads_done":[],
         "beads_partial":["p-1"],"beads_blocked":["b-1"],
         "validation":["nimble test: failed"],
         "review_blocker_summary":["reviewer requested changes"],
         "reviews":[{"reviewer":"scout","verdict":"REQUEST_CHANGES"}]}
      """)
      let result = summary.run(@["--repo", repo, "--json"],
        readyWith(@[]), readyWith(@[]), fixedClock)
      let parsed = parseJson(result.output)
      check parsed["latest_validation"]["passed"].getBool == false
      check parsed["status"].getStr == "blocked"
      let risks = parsed["unresolved_risks"].to(seq[string])
      check "reviewer requested changes" in risks
      check "bead partially satisfied: p-1" in risks

  test "malformed history file is skipped, not fatal":
    withTempRepo proc(repo: string) =
      writeIteration(repo, 1, """{"iteration":1,"status":"complete","beads_done":["ok-1"]}""")
      writeIteration(repo, 2, "{ this is not valid json ")
      let result = summary.run(@["--repo", repo, "--json"],
        readyWith(@[]), readyWith(@[]), fixedClock)
      check result.exitCode == 0
      let parsed = parseJson(result.output)
      check parsed["history_count"].getInt == 1
      check parsed["beads_done"].to(seq[string]) == @["ok-1"]

  test "--write emits latest.md and summary.json":
    withTempRepo proc(repo: string) =
      writeIteration(repo, 1, """
        {"iteration":1,"branch":"bead-swarm/iteration-1-x","main_branch":"main",
         "merge_target":"main","status":"complete","beads_done":["a-1"],
         "validation":["build: pass"],"reviews":[]}
      """)
      let result = summary.run(@["--repo", repo, "--write"],
        readyWith(@[]), readyWith(@[]), fixedClock)
      check result.exitCode == 0
      let latest = repo / ".agents/bead-swarm/latest.md"
      let summaryJson = repo / ".agents/bead-swarm/summary.json"
      check fileExists(latest)
      check fileExists(summaryJson)
      check "# Swarmy run summary" in readFile(latest)
      check parseJson(readFile(summaryJson))["last_iteration"].getInt == 1

  test "beads_open is unknown when bd is unavailable":
    withTempRepo proc(repo: string) =
      writeIteration(repo, 1, """{"iteration":1,"status":"complete","beads_done":[]}""")
      let result = summary.run(@["--repo", repo, "--json"],
        unavailable(), unavailable(), fixedClock)
      let parsed = parseJson(result.output)
      check parsed["beads_open"].kind == JNull

  test "rejects unexpected arguments with exit 2":
    let result = summary.run(@["--bogus"],
      readyWith(@[]), readyWith(@[]), fixedClock)
    check result.exitCode == 2
    check "unexpected argument '--bogus'" in result.error

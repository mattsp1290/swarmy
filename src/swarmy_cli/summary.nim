## `swarmy summary` — compact current-run manifest.
##
## Recovering "where is this run and what's next" used to mean reading and
## reconciling every `.agents/bead-swarm/history/iteration-*.json` file. This
## command folds those history files together with swarmy's own SQLite store and
## live `bd` readiness into a single compact manifest, and can write it to
## `.agents/bead-swarm/latest.md` (+ `summary.json`) so the next agent reads ONE
## file.
##
## It is read-only with respect to the store and history JSON; the only files it
## writes are the derived `latest.md` / `summary.json` audit artifacts. bd access
## and the clock are injected so the output is deterministic under test.

import std/[algorithm, json, os, strutils, times]

import tiny_sqlite

import swarmy_cli/dispatch_types
import swarmy_core/bd_adapter
import swarmy_core/diagnostics
import swarmy_core/persistence
import swarmy_core/run_metadata

type
  ReviewVerdict* = object
    reviewer*: string
    verdict*: string
    artifact*: string

  Iteration = object
    iteration: int
    branch: string
    mainBranch: string
    mergeTarget: string
    status: string
    executionMode: string
    degradedReason: string
    reviewMode: string
    reviewAssurance: string
    findingsFixedReReviewed: bool
    beadsDone: seq[string]
    beadsBlocked: seq[string]
    beadsPartial: seq[string]
    validation: seq[string]
    reviewBlockerSummary: seq[string]
    reviews: seq[ReviewVerdict]

  Manifest* = object
    runId*: string
    repo*: string
    generatedAt*: string
    historyCount*: int
    lastIteration*: int
    lastBranch*: string
    mainBranch*: string
    mergeTarget*: string
    status*: string
    executionMode*: string
    degradedReason*: string
    reviewMode*: string
    beadsDone*: seq[string]
    beadsBlocked*: seq[string]
    beadsPartial*: seq[string]
    beadsOpen*: int
    beadsOpenKnown*: bool
    recommendedNext*: seq[string]
    latestValidation*: seq[string]
    validationPassed*: bool
    unresolvedRisks*: seq[string]
    lastReviews*: seq[ReviewVerdict]
    recentErrors*: int

  BeadReader* = proc(repo: string): tuple[ok: bool, beads: seq[BeadSnapshot], error: string] {.closure.}
  Clock* = proc(): string {.closure.}

  SummaryOptions = object
    repo: string
    json: bool
    write: bool

const
  RecommendedLimit = 10
  HistorySubdir = ".agents/bead-swarm/history"

# --- argument parsing -------------------------------------------------------

proc requireValue(args: seq[string], i: int, flag: string): tuple[ok: bool, value: string, error: string] =
  if i + 1 >= args.len or args[i + 1].startsWith("--"):
    return (false, "", "swarmy summary: " & flag & " requires a path\n")
  (true, args[i + 1], "")

proc parseArgs(args: seq[string]): tuple[ok: bool, options: SummaryOptions, error: string] =
  result.options.repo = "."

  var i = 0
  while i < args.len:
    case args[i]
    of "--repo":
      let value = requireValue(args, i, "--repo")
      if not value.ok:
        return (false, result.options, value.error)
      result.options.repo = value.value
      i += 2
    of "--json":
      result.options.json = true
      i += 1
    of "--write":
      result.options.write = true
      i += 1
    else:
      return (false, result.options, "swarmy summary: unexpected argument '" & args[i] & "'\n")

  (true, result.options, "")

# --- history parsing --------------------------------------------------------

proc strArray(node: JsonNode, key: string): seq[string] =
  if node.hasKey(key) and node[key].kind == JArray:
    for item in node[key]:
      if item.kind == JString:
        result.add item.getStr

proc parseReviews(node: JsonNode): seq[ReviewVerdict] =
  if node.hasKey("reviews") and node["reviews"].kind == JArray:
    for r in node["reviews"]:
      if r.kind == JObject:
        result.add ReviewVerdict(
          reviewer: r{"reviewer"}.getStr(""),
          verdict: r{"verdict"}.getStr(""),
          artifact: r{"artifact"}.getStr("")
        )

proc parseIteration(node: JsonNode): Iteration =
  Iteration(
    iteration: node{"iteration"}.getInt(0),
    branch: node{"branch"}.getStr(""),
    mainBranch: node{"main_branch"}.getStr(""),
    mergeTarget: node{"merge_target"}.getStr(""),
    status: node{"status"}.getStr(""),
    executionMode: node{"execution_mode"}.getStr(""),
    degradedReason: node{"degraded_reason"}.getStr(""),
    reviewMode: node{"review_mode"}.getStr(""),
    reviewAssurance: node{"review_assurance"}.getStr(""),
    findingsFixedReReviewed: node{"findings_fixed_re_reviewed"}.getBool(false),
    beadsDone: node.strArray("beads_done"),
    beadsBlocked: node.strArray("beads_blocked"),
    beadsPartial: node.strArray("beads_partial"),
    validation: node.strArray("validation"),
    reviewBlockerSummary: node.strArray("review_blocker_summary"),
    reviews: parseReviews(node)
  )

proc readHistory*(historyDir: string): seq[Iteration] =
  ## Parse every iteration-*.json under historyDir, tolerating missing or
  ## malformed files (a bad file is skipped, not fatal). Sorted ascending by
  ## iteration number.
  if not dirExists(historyDir):
    return @[]
  for path in walkFiles(historyDir / "iteration-*.json"):
    try:
      let node = parseJson(readFile(path))
      if node.kind == JObject:
        result.add parseIteration(node)
    except CatchableError:
      continue
  result.sort(proc(a, b: Iteration): int = cmp(a.iteration, b.iteration))

# --- aggregation ------------------------------------------------------------

proc looksLikeFailure(entry: string): bool =
  ## True when a free-text `validation` entry reports a failing result. The
  ## convention is "<check>: <result>" (e.g. "nimble test: failed"). Negated
  ## phrasings like "no failures" / "0 failures" / "without failures" are NOT
  ## failures, so they are excluded before the failure markers are checked.
  let lowered = entry.toLowerAscii()
  if "no fail" in lowered or "0 fail" in lowered or "zero fail" in lowered or
     "without fail" in lowered or "not fail" in lowered:
    return false
  ": fail" in lowered or "fail:" in lowered or " failed" in lowered or
    " failing" in lowered or "[fail]" in lowered or lowered.startsWith("fail") or
    lowered.endsWith("failed")

proc validationPassed(status: string, entries: seq[string]): bool =
  ## Heuristic pass/fail derived from the last iteration's `validation` array
  ## (which is a list of free-text entries, not a boolean) plus its status.
  for entry in entries:
    if looksLikeFailure(entry):
      return false
  status != "blocked"

proc dedupAppend(acc: var seq[string], items: seq[string]) =
  for item in items:
    if item notin acc:
      acc.add item

proc countOpen(beads: seq[BeadSnapshot]): int =
  for bead in beads:
    if bead.status.strip().toLowerAscii() != "closed":
      inc result

proc buildManifest*(
  runId, repo, generatedAt: string,
  history: seq[Iteration],
  ready: tuple[ok: bool, beads: seq[BeadSnapshot], error: string],
  listed: tuple[ok: bool, beads: seq[BeadSnapshot], error: string],
  recentErrors: int
): Manifest =
  result.runId = runId
  result.repo = repo
  result.generatedAt = generatedAt
  result.historyCount = history.len
  result.recentErrors = recentErrors

  # Cumulative completed beads across the whole run.
  for it in history:
    result.beadsDone.dedupAppend(it.beadsDone)

  if history.len > 0:
    let last = history[^1]
    result.lastIteration = last.iteration
    result.lastBranch = last.branch
    result.mainBranch = last.mainBranch
    result.mergeTarget = last.mergeTarget
    result.status = last.status
    result.executionMode = last.executionMode
    result.degradedReason = last.degradedReason
    result.reviewMode = last.reviewMode
    result.beadsBlocked = last.beadsBlocked
    result.beadsPartial = last.beadsPartial
    result.latestValidation = last.validation
    result.validationPassed = validationPassed(last.status, last.validation)
    result.lastReviews = last.reviews
    # Unresolved risks: review blockers plus any partially-satisfied beads.
    for entry in last.reviewBlockerSummary:
      result.unresolvedRisks.add entry
    for bead in last.beadsPartial:
      result.unresolvedRisks.add "bead partially satisfied: " & bead
  else:
    result.validationPassed = false

  # Open count comes from bd, never from history (no beads_open field exists).
  if listed.ok:
    result.beadsOpen = countOpen(listed.beads)
    result.beadsOpenKnown = true

  # Recommended next: concrete (non-epic) ready beads via the shared classifier.
  if ready.ok:
    let mix = classifyReady(ready.beads)
    for bead in mix.concrete:
      if result.recommendedNext.len >= RecommendedLimit:
        break
      result.recommendedNext.add bead.id

# --- rendering --------------------------------------------------------------

proc toJsonNode(reviews: seq[ReviewVerdict]): JsonNode =
  result = newJArray()
  for r in reviews:
    result.add %*{"reviewer": r.reviewer, "verdict": r.verdict, "artifact": r.artifact}

proc toJson*(m: Manifest): JsonNode =
  %*{
    "run_id": m.runId,
    "repo": m.repo,
    "generated_at": m.generatedAt,
    "history_count": m.historyCount,
    "last_iteration": m.lastIteration,
    "last_branch": m.lastBranch,
    "main_branch": m.mainBranch,
    "merge_target": m.mergeTarget,
    "status": m.status,
    "execution_mode": m.executionMode,
    "degraded_reason": m.degradedReason,
    "review_mode": m.reviewMode,
    "beads_done": m.beadsDone,
    "beads_blocked": m.beadsBlocked,
    "beads_partial": m.beadsPartial,
    "beads_open": (if m.beadsOpenKnown: %m.beadsOpen else: newJNull()),
    "recommended_next": m.recommendedNext,
    "latest_validation": {
      "passed": m.validationPassed,
      "entries": m.latestValidation
    },
    "unresolved_risks": m.unresolvedRisks,
    "reviews": toJsonNode(m.lastReviews),
    "recent_errors": m.recentErrors
  }

proc renderJson(m: Manifest): string =
  m.toJson.pretty & "\n"

proc bullets(items: seq[string], empty = "_none_"): string =
  if items.len == 0:
    return "- " & empty & "\n"
  for item in items:
    result.add "- " & item & "\n"

proc renderMarkdown*(m: Manifest): string =
  result = "# Swarmy run summary\n\n"
  result.add "- Run: `" & m.runId & "`\n"
  result.add "- Repo: `" & m.repo & "`\n"
  result.add "- Generated: " & m.generatedAt & "\n"
  if m.historyCount == 0:
    result.add "- History: no iteration history yet\n"
    return
  result.add "- Last iteration: " & $m.lastIteration & " (branch `" &
    m.lastBranch & "`, status `" & m.status & "`)\n"
  result.add "- Main branch: `" & m.mainBranch & "` → merged into `" &
    m.mergeTarget & "`\n"
  if m.executionMode.len > 0:
    result.add "- Execution mode: " & m.executionMode
    if m.degradedReason.len > 0:
      result.add " (" & m.degradedReason & ")"
    result.add "\n"

  result.add "\n## Beads\n"
  result.add "- Done (cumulative, " & $m.beadsDone.len & "): " &
    (if m.beadsDone.len == 0: "_none_" else: m.beadsDone.join(", ")) & "\n"
  result.add "- Blocked: " &
    (if m.beadsBlocked.len == 0: "_none_" else: m.beadsBlocked.join(", ")) & "\n"
  result.add "- Partial: " &
    (if m.beadsPartial.len == 0: "_none_" else: m.beadsPartial.join(", ")) & "\n"
  result.add "- Open (from bd): " &
    (if m.beadsOpenKnown: $m.beadsOpen else: "unknown") & "\n"
  result.add "- Recommended next (concrete, non-epic): " &
    (if m.recommendedNext.len == 0: "_none_" else: m.recommendedNext.join(", ")) & "\n"

  result.add "\n## Latest validation (" &
    (if m.validationPassed: "PASS" else: "FAIL") & ")\n"
  result.add bullets(m.latestValidation)

  result.add "\n## Review\n"
  if m.lastReviews.len == 0:
    result.add "- _no reviews recorded_\n"
  else:
    for r in m.lastReviews:
      result.add "- " & r.reviewer & ": " & r.verdict & "\n"
  if m.reviewMode.len > 0:
    result.add "- Review mode: " & m.reviewMode & "\n"

  result.add "\n## Unresolved risks\n"
  result.add bullets(m.unresolvedRisks)

  if m.recentErrors > 0:
    result.add "\n## Diagnostics\n- Recent errors in store: " &
      $m.recentErrors & "\n"

# --- real readers -----------------------------------------------------------

proc realReady(repo: string): tuple[ok: bool, beads: seq[BeadSnapshot], error: string] =
  try:
    (true, readReadyBeads(repo), "")
  except CatchableError as error:
    (false, @[], error.msg)

proc realListed(repo: string): tuple[ok: bool, beads: seq[BeadSnapshot], error: string] =
  try:
    (true, readListedBeads(repo), "")
  except CatchableError as error:
    (false, @[], error.msg)

proc realClock(): string =
  now().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")

proc storeRunInfo(repo: string): tuple[runId: string, recentErrors: int] =
  ## Best-effort read of swarmy's own store: run id from metadata, error count
  ## from the db if present. Never fatal — an uninitialized repo yields empties.
  let metaPath = metadataPath(repo)
  if not fileExists(metaPath):
    return ("", 0)
  try:
    let metadata = readRunMetadata(metaPath)
    result.runId = metadata.runId
    if fileExists(metadata.dbPath):
      var store = openReadOnlyStore(metadata.dbPath)
      try:
        result.recentErrors = store.db.value(
          "SELECT COUNT(*) FROM errors WHERE run_id = ?", metadata.runId
        ).get.fromDbValue(int64).int
      finally:
        store.close()
  except CatchableError:
    discard

# --- entry point ------------------------------------------------------------

proc canonicalize(repo: string): string =
  try: canonicalRepoPath(repo)
  except CatchableError: repo

proc iterationsToJson(history: seq[Iteration]): JsonNode =
  ## Pure: per-iteration review verdicts and degraded-review signals. Note
  ## `review_assurance` is the review-degradation signal (distinct from the
  ## orchestration-level `execution_mode`).
  result = newJArray()
  for it in history:
    result.add %*{
      "iteration": it.iteration,
      "branch": it.branch,
      "status": it.status,
      "execution_mode": it.executionMode,
      "degraded_reason": it.degradedReason,
      "review_mode": it.reviewMode,
      "review_assurance": it.reviewAssurance,
      "findings_fixed_re_reviewed": it.findingsFixedReReviewed,
      "validation_passed": validationPassed(it.status, it.validation),
      "reviews": toJsonNode(it.reviews),
      "review_blocker_summary": it.reviewBlockerSummary
    }

proc generate*(
  repo, generatedAt: string,
  ready: BeadReader = realReady,
  listed: BeadReader = realListed
): Manifest =
  let canonicalRepo = canonicalize(repo)
  let storeInfo = storeRunInfo(canonicalRepo)
  let history = readHistory(canonicalRepo / HistorySubdir)
  buildManifest(
    storeInfo.runId,
    canonicalRepo,
    generatedAt,
    history,
    ready(canonicalRepo),
    listed(canonicalRepo),
    storeInfo.recentErrors
  )

proc generateNow*(repo: string): Manifest =
  ## Convenience for non-CLI callers: stamp the manifest with the current time
  ## using the production bd readers.
  generate(repo, realClock())

proc iterationsJson*(repo: string): JsonNode =
  ## Per-iteration health derived from the history dir. Derivation stays in this
  ## module (the single owner of history parsing) so callers do not re-derive it.
  iterationsToJson(readHistory(canonicalize(repo) / HistorySubdir))

proc healthView*(repo: string): tuple[manifest: Manifest, iterations: JsonNode] =
  ## Single-pass health view for the HTTP surface: parses the history dir ONCE
  ## and produces both the run-health manifest and the per-iteration array,
  ## instead of the server calling generateNow + iterationsJson (which would
  ## parse history twice).
  let canonicalRepo = canonicalize(repo)
  let storeInfo = storeRunInfo(canonicalRepo)
  let history = readHistory(canonicalRepo / HistorySubdir)
  result.manifest = buildManifest(
    storeInfo.runId,
    canonicalRepo,
    realClock(),
    history,
    realReady(canonicalRepo),
    realListed(canonicalRepo),
    storeInfo.recentErrors
  )
  result.iterations = iterationsToJson(history)

proc run*(
  args: seq[string],
  ready: BeadReader = realReady,
  listed: BeadReader = realListed,
  clock: Clock = realClock
): CliResult =
  let parsed = parseArgs(args)
  if not parsed.ok:
    return CliResult(exitCode: 2, error: parsed.error)

  try:
    let manifest = generate(parsed.options.repo, clock(), ready, listed)

    if parsed.options.write:
      let historyDir = manifest.repo / HistorySubdir
      createDir(historyDir)
      let latestPath = manifest.repo / ".agents/bead-swarm/latest.md"
      writeFile(latestPath, renderMarkdown(manifest))
      writeFile(historyDir.parentDir / "summary.json", renderJson(manifest))

    let rendered =
      if parsed.options.json: renderJson(manifest)
      else: renderMarkdown(manifest)
    CliResult(exitCode: 0, output: redactDiagnostic(rendered))
  except CatchableError as err:
    CliResult(exitCode: 1, error: "swarmy summary: " & err.msg & "\n")

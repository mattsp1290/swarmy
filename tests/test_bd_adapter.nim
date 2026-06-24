import std/[options, strutils, unittest]

import swarmy_core/bd_adapter

type
  FakeBd = object
    result: BdCommandResult
    seenArgs: seq[seq[string]]

var fake: FakeBd

proc fakeRunner(repoPath: string, args: seq[string], timeoutMs: int): BdCommandResult =
  check repoPath == "/repo"
  check timeoutMs == 1234
  fake.seenArgs.add args
  fake.result

proc setFake(output: string, exitCode = 0, timedOut = false) =
  fake = FakeBd(result: BdCommandResult(exitCode: exitCode, output: output, timedOut: timedOut))

proc fixture(id = "swarmy-3z4", status = "open", updatedAt = "2026-06-24T00:00:00Z"): string =
  """
  [{
    "id": "$1",
    "title": "Reconstruct bead snapshots from bd",
    "description": "Read canonical Beads state",
    "notes": "fixture notes",
    "status": "$2",
    "priority": 1,
    "issue_type": "feature",
    "updated_at": "$3",
    "closed_at": null,
    "labels": ["data"]
  }]
  """ % [id, status, updatedAt]

suite "bd adapter":
  test "reads ready snapshots with a read-only bd command":
    setFake(fixture())

    let snapshots = readReadyBeads("/repo", fakeRunner, timeoutMs = 1234, limit = 20)

    check snapshots.len == 1
    check snapshots[0].id == "swarmy-3z4"
    check snapshots[0].title == "Reconstruct bead snapshots from bd"
    check snapshots[0].status == "open"
    check snapshots[0].priority == 1
    check snapshots[0].issueType == "feature"
    check snapshots[0].labels == @["data"]
    check fake.seenArgs == @[@["ready", "--json", "--limit", "20"]]

  test "reads listed snapshots with bd list":
    setFake(fixture(id = "swarmy-other", status = "closed"))

    let snapshots = readListedBeads("/repo", fakeRunner, timeoutMs = 1234)

    check snapshots.len == 1
    check snapshots[0].id == "swarmy-other"
    check snapshots[0].status == "closed"
    check fake.seenArgs == @[@["list", "--json"]]

  test "reads one exact bead from bd show":
    setFake(fixture())

    let snapshot = readBead("/repo", "swarmy-3z4", fakeRunner, timeoutMs = 1234)

    check snapshot.id == "swarmy-3z4"
    check snapshot.notes == "fixture notes"
    check snapshot.updatedAt == "2026-06-24T00:00:00Z"
    check snapshot.closedAt.isNone
    check fake.seenArgs == @[@["show", "swarmy-3z4", "--json"]]

  test "maps command timeout to typed error":
    setFake("", timedOut = true)

    expect BdSnapshotError:
      discard readReadyBeads("/repo", fakeRunner, timeoutMs = 1234)

    try:
      discard readReadyBeads("/repo", fakeRunner, timeoutMs = 1234)
    except BdSnapshotError as error:
      check error.kind == bdTimeout

  test "maps non-Beads repositories to typed error":
    setFake("not a Beads repository", exitCode = 1)

    try:
      discard readListedBeads("/repo", fakeRunner, timeoutMs = 1234)
      fail()
    except BdSnapshotError as error:
      check error.kind == bdNotRepository

  test "maps failed bd commands to typed error":
    setFake("failed to open database: locked", exitCode = 1)

    try:
      discard readListedBeads("/repo", fakeRunner, timeoutMs = 1234)
      fail()
    except BdSnapshotError as error:
      check error.kind == bdCommandFailed
      check error.exitCode == 1

  test "rejects malformed output":
    setFake("""{"error":"shape"}""")

    try:
      discard readListedBeads("/repo", fakeRunner, timeoutMs = 1234)
      fail()
    except BdSnapshotError as error:
      check error.kind == bdMalformedOutput

  test "handles deleted or renamed bead show output":
    setFake(fixture(id = "swarmy-renamed"))

    try:
      discard readBead("/repo", "swarmy-3z4", fakeRunner, timeoutMs = 1234)
      fail()
    except BdSnapshotError as error:
      check error.kind == bdDeletedOrRenamed

  test "rejects stale show snapshots when caller has a newer timestamp":
    setFake(fixture(updatedAt = "2026-06-24T00:00:00Z"))

    try:
      discard readBead(
        "/repo",
        "swarmy-3z4",
        fakeRunner,
        timeoutMs = 1234,
        minimumUpdatedAt = some("2026-06-24T00:00:01Z")
      )
      fail()
    except BdSnapshotError as error:
      check error.kind == bdStaleSnapshot

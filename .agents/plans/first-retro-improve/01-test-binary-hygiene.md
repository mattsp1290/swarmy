# 01 — Generated test-binary hygiene

**Priority:** P0 (cheap, recurs every `nimble test`, flagged in BOTH retros)
**Retro origin:**
- Retro 1: "Nim test runs produced generated binaries and build artifacts that
  required manual cleanup. This is easy to miss during long autonomous runs."
- Retro 2: "Generated Nim test binaries (`tests/test_*`) reappeared after every
  `nimble test` and needed manual `rm` before staging (also flagged last session;
  still not solved by `.gitignore` or a test convention)."

## Problem (grounded)

`swarmy.nimble` (lines 19–22) runs each test in place:

```nim
task test, "Run Nim tests":
  for file in listFiles("tests"):
    if file.startsWith("tests" / "test_") and file.endsWith(".nim"):
      exec "nim c -r --path:src --hints:off --verbosity:0 " & file
```

`nim c -r tests/test_foo.nim` writes the compiled executable to `tests/test_foo`
(same dir, no extension). Those binaries are **not** ignored — `.gitignore` ignores
`nimcache/`, `*.db`, Playwright dirs, etc., but nothing matches `tests/test_*`
binaries. A naive `tests/test_*` ignore pattern is wrong because it would also
ignore the `tests/test_*.nim` **source** files.

Result: after every test run, `git status` shows ~15 untracked binaries that must
be manually `rm`'d before staging — a real hazard in an autonomous loop that stages
by allowlist.

## Proposed change

Redirect the compiled test binaries (and their per-test nimcache) into the
already-ignored `nimcache/` tree so they never appear in `git status`. Edit the
`test` task in `swarmy.nimble`:

```nim
task test, "Run Nim tests":
  let binDir = "nimcache" / "testbin"
  mkDir(binDir)
  for file in listFiles("tests"):
    if file.startsWith("tests" / "test_") and file.endsWith(".nim"):
      let name = file.splitFile.name
      exec "nim c -r --path:src --hints:off --verbosity:0 " &
           "--nimcache:" & ("nimcache" / "testcache" / name) & " " &
           "-o:" & (binDir / name) & " " & file
```

Notes:
- `nimcache/` is already in `.gitignore` (line 1), so both the binary and the
  per-test cache disappear from `git status`.
- `mkDir` is idempotent in nimscript; safe to call every run.
- `-o:` sets the output path; `-r` still runs the produced binary, so behavior is
  unchanged — only the artifact location moves.
- Per-test `--nimcache` subdirs avoid cross-test cache collisions when names differ;
  this is optional but cheap insurance.

### Alternative (if the maintainer prefers an explicit dir over nimcache)

Output to `tests/.bin/` and add `tests/.bin/` to `.gitignore`. Less preferred
because it adds a second ignored location; the nimcache approach reuses an existing
one.

## Acceptance criteria

- After `nimble test` from a clean tree, `git status --porcelain` shows **no**
  untracked `tests/test_*` entries.
- All existing tests still execute and pass (the `-r` run is preserved).
- CI `backend` job (`.github/workflows/ci.yml`, `nimble test`) stays green.

## Validation

```sh
git stash --include-untracked   # optional, to start clean
nimble test
git status --porcelain          # expect: nothing under tests/
```

Also run the smoke path to be safe: `tests/smoke.sh` (or `npm run test:smoke`).

## Scope / risk

- Single-file change to `swarmy.nimble`. Low risk.
- Do not change the test *selection* logic (`startsWith("tests"/"test_")`) — only
  the output location.
- If `--nimcache` per-test causes longer cold builds in CI, drop the per-test
  `--nimcache` and keep just `-o:` into `nimcache/testbin`.

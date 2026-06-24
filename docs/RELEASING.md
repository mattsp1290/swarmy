# Releasing swarmy

This document describes how continuous integration gates changes, how to build a
local release artifact, what that artifact contains, and how to cut a version
bump. None of these steps require external services (no databases or cloud
credentials); tests run against embedded sqlite with stubbed APIs.

## CI gates

CI is defined in [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) and
runs on every push and pull request to `main` (plus manual `workflow_dispatch`).
All jobs run on `ubuntu-latest`. Nim is installed via the official `choosenim`
script, so the toolchain tracks upstream stable (>= 2.2.4).

| Job        | What it does                                                              |
|------------|--------------------------------------------------------------------------|
| `backend`  | `nimble install --depsOnly`, `nimble test`, `nimble build`.              |
| `frontend` | `npm ci`, web build, `node:test` suite, Playwright chromium UI smoke.    |
| `smoke`    | Root `npm run build` (Nim + web) then `tests/smoke.sh`.                  |
| `package`  | Needs `backend` + `frontend`; runs `scripts/package.sh`, uploads tarball.|

`tests/smoke.sh` runs the backend build, frontend build, a serve check, and an
end-to-end check. The e2e step skips cleanly when the `bd` CLI is absent, so CI
needs no Beads setup. `python3` and `curl` are preinstalled on the runner.

## Building a local artifact

Run the packaging script from anywhere; it resolves the repo root itself:

```bash
scripts/package.sh              # build backend + web, then package
scripts/package.sh --skip-build # reuse existing ./swarmy and apps/web/dist
```

It reads the version from `swarmy.nimble`, detects OS/arch via `uname`, and
writes:

```
dist/swarmy-<version>-<os>-<arch>.tar.gz
dist/swarmy-<version>-<os>-<arch>.tar.gz.sha256
```

`dist/` is git-ignored. The script is idempotent and safe to re-run.

### Artifact contents

The tarball expands to a single top-level `swarmy-<version>-<os>-<arch>/`
directory containing:

```
bin/swarmy        # the compiled backend binary
web/              # the built Svelte bundle (web/index.html, web/assets/...)
README.md
LICENSE
```

### Running the artifact

```bash
tar xzf swarmy-<version>-<os>-<arch>.tar.gz
cd swarmy-<version>-<os>-<arch>
bin/swarmy serve --static-dir web
```

`serve` defaults can be overridden with `--host`, `--port`, `--repo`,
`--auth-token`, and `--max-body-bytes`.

## Versioning

A release version lives in three places that must be bumped together:

1. `swarmy.nimble` — `version = "X.Y.Z"`
2. `apps/web/package.json` — `"version": "X.Y.Z"`
3. `src/swarmy_core/app.nim` — `Version* = "X.Y.Z"`

The packaging script and CI derive the artifact name from `swarmy.nimble`, so
that file is the source of truth for the tarball name.

## First release (0.1.0)

Initial release of swarmy — "loops made visible".

- Nim backend (`swarmy` binary) with CLI dispatch, an MCP stdio server, and an
  HTTP server that serves the bundled web UI.
- Svelte/Vite web frontend, built to a static bundle served via
  `swarmy serve --static-dir web`.
- Embedded sqlite persistence (via `tiny_sqlite`); no external database needed.
- CI runs backend tests, frontend build/tests, a smoke suite, and produces a
  downloadable release tarball.

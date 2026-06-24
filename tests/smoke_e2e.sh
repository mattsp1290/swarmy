#!/usr/bin/env bash
# Full first-milestone end-to-end smoke test (swarmy-e24).
#
# One command that exercises the real user-facing path:
#   1. initialize a temp Beads repo (when bd is available),
#   2. run `swarmy init`,
#   3. record synthetic `coding` then `review` stage events via the real CLI,
#   4. start the API against that repo,
#   5. verify the UI-facing state endpoints reflect the recorded run/bead/stages.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWARMY="${ROOT}/swarmy"
PORT="${SWARMY_SMOKE_E2E_PORT:-18182}"
BEAD="swarmy-smoke-1"
TMPDIR="$(mktemp -d)"
REPO="${TMPDIR}/repo"
SERVE_PID=""

cleanup() {
  if [[ -n "${SERVE_PID}" ]]; then
    kill "${SERVE_PID}" 2>/dev/null || true
    wait "${SERVE_PID}" 2>/dev/null || true
  fi
  rm -rf "${TMPDIR}"
}
trap cleanup EXIT

command -v curl >/dev/null 2>&1 || { echo "smoke-e2e: curl is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "smoke-e2e: python3 is required" >&2; exit 1; }

# Ensure the binary and web build exist (cheap no-ops once built).
[[ -x "${SWARMY}" ]] || (cd "${ROOT}" && nimble build)
[[ -f "${ROOT}/apps/web/dist/index.html" ]] || \
  (cd "${ROOT}" && npm run build --workspace apps/web)

mkdir -p "${REPO}"

# 1. Temp Beads repo (the swarm substrate). Best-effort: the swarmy state path
#    does not depend on bd, so skip cleanly when bd/dolt is unavailable.
if command -v bd >/dev/null 2>&1; then
  ( cd "${REPO}" && git init -q && bd init >/dev/null 2>&1 ) \
    && echo "smoke-e2e: initialized temp Beads repo" \
    || echo "smoke-e2e: bd init skipped (bd present but init failed)"
else
  echo "smoke-e2e: bd not found; skipping Beads repo init"
fi

# 2. swarmy init creates the local .swarmy run + store.
"${SWARMY}" init --repo "${REPO}" >/dev/null

# 3. Record synthetic coding then review events through the real CLI path.
"${SWARMY}" stage --repo "${REPO}" --event-id evt-coding \
  --bead "${BEAD}" --stage coding --title "Smoke bead" >/dev/null
"${SWARMY}" stage --repo "${REPO}" --event-id evt-review \
  --bead "${BEAD}" --stage review --title "Smoke bead" >/dev/null

# 4. Start the API against the repo.
"${SWARMY}" serve \
  --host 127.0.0.1 \
  --port "${PORT}" \
  --static-dir "${ROOT}/apps/web/dist" \
  --repo "${REPO}" \
  >"${TMPDIR}/serve.log" 2>&1 &
SERVE_PID="$!"

# Fail fast if our own server could not bind (e.g. the port is already held by
# a leaked/foreign process): otherwise every assertion below would silently run
# against that other server. swarmy serve exits non-zero and logs "failed to
# start" on a bind error.
assert_our_server_alive() {
  if grep -q "failed to start" "${TMPDIR}/serve.log" 2>/dev/null; then
    echo "smoke-e2e: swarmy serve failed to bind 127.0.0.1:${PORT} (port in use?)" >&2
    cat "${TMPDIR}/serve.log" >&2 || true
    exit 1
  fi
  if ! kill -0 "${SERVE_PID}" 2>/dev/null; then
    echo "smoke-e2e: swarmy serve process exited early" >&2
    cat "${TMPDIR}/serve.log" >&2 || true
    exit 1
  fi
}

# Wait for the server to accept requests, bailing out the moment our own
# process dies rather than waiting to query a stranger's server.
ready=0
for _ in $(seq 1 40); do
  assert_our_server_alive
  if curl -fsS "http://127.0.0.1:${PORT}/api/health" >"${TMPDIR}/health.json" 2>/dev/null; then
    ready=1
    break
  fi
  sleep 0.25
done
if [[ "${ready}" -ne 1 ]]; then
  echo "smoke-e2e: server did not become ready" >&2
  cat "${TMPDIR}/serve.log" >&2 || true
  exit 1
fi
# Re-check after a successful health probe to close the race where a foreign
# server answered while ours was still failing to bind.
assert_our_server_alive
grep -q '"status":"ok"' "${TMPDIR}/health.json"

# 5. Verify the UI-facing state endpoints reflect the recorded run/bead/stages.
curl -fsS "http://127.0.0.1:${PORT}/api/runs" >"${TMPDIR}/runs.json"
RUN_ID="$(
  python3 - "${TMPDIR}/runs.json" <<'PY'
import json, sys
with open(sys.argv[1]) as fh:
    data = json.load(fh)
runs = data["runs"]
assert runs, "no runs returned by /api/runs"
print(runs[0]["run_id"])
PY
)"
test -n "${RUN_ID}"

curl -fsS "http://127.0.0.1:${PORT}/api/runs/${RUN_ID}" >"${TMPDIR}/run.json"
python3 - "${TMPDIR}/run.json" "${BEAD}" <<'PY'
import json, sys
with open(sys.argv[1]) as fh:
    run = json.load(fh)
bead_id = sys.argv[2]
beads = {b["id"]: b for b in run["beads"]}
assert bead_id in beads, f"{bead_id} missing from run detail: {list(beads)}"
bead = beads[bead_id]
assert bead["swarm_stage"] == "review", f"expected review, got {bead.get('swarm_stage')}"
PY

# The polling seam used by the UI must return both stage events in order.
curl -fsS "http://127.0.0.1:${PORT}/api/runs/${RUN_ID}/events?after=0" \
  >"${TMPDIR}/events.json"
python3 - "${TMPDIR}/events.json" <<'PY'
import json, sys
with open(sys.argv[1]) as fh:
    payload = json.load(fh)
stages = [e.get("stage") for e in payload["events"] if e.get("stage")]
assert stages == ["coding", "review"], f"unexpected stage order: {stages}"
assert payload["latest_seq"] >= 2, payload["latest_seq"]
PY

echo "smoke-e2e: OK run=${RUN_ID} bead=${BEAD} stages=coding,review"

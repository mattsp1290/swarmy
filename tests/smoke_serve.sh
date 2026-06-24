#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${SWARMY_SMOKE_PORT:-18181}"
TMPDIR="$(mktemp -d)"
FIRST_PID=""

cleanup() {
  if [[ -n "${FIRST_PID}" ]]; then
    kill "${FIRST_PID}" 2>/dev/null || true
    wait "${FIRST_PID}" 2>/dev/null || true
  fi
  rm -rf "${TMPDIR}"
}
trap cleanup EXIT

"${ROOT}/swarmy" serve \
  --host 127.0.0.1 \
  --port "${PORT}" \
  --static-dir "${ROOT}/apps/web/dist" \
  >"${TMPDIR}/first.log" 2>&1 &
FIRST_PID="$!"

for _ in $(seq 1 40); do
  if curl -fsS "http://127.0.0.1:${PORT}/api/health" >"${TMPDIR}/health.json" &&
      curl -fsS "http://127.0.0.1:${PORT}/" >"${TMPDIR}/index.html" &&
      curl -fsS "http://127.0.0.1:${PORT}/assets/$(basename "${ROOT}"/apps/web/dist/assets/*.js)" >"${TMPDIR}/asset.js"; then
    break
  fi
  sleep 0.25
done

grep -q '"status":"ok"' "${TMPDIR}/health.json"
grep -q '<title>Swarmy</title>' "${TMPDIR}/index.html"
test -s "${TMPDIR}/asset.js"

set +e
"${ROOT}/swarmy" serve \
  --host 127.0.0.1 \
  --port "${PORT}" \
  --static-dir "${ROOT}/apps/web/dist" \
  >"${TMPDIR}/second.log" 2>&1
SECOND_CODE="$?"
set -e

test "${SECOND_CODE}" -eq 1
grep -q "swarmy serve: failed to start http://127.0.0.1:${PORT}" "${TMPDIR}/second.log"
if grep -q "Traceback" "${TMPDIR}/second.log"; then
  cat "${TMPDIR}/second.log"
  exit 1
fi

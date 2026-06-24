#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${ROOT}/tests/smoke_backend.sh"
"${ROOT}/tests/smoke_frontend.sh"
"${ROOT}/tests/smoke_serve.sh"

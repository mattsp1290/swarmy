#!/usr/bin/env bash
#
# package.sh — produce a local release artifact for swarmy.
#
# Builds the Nim backend binary and the Svelte web bundle, stages them into a
# self-contained directory, and emits a gzipped tarball plus a sha256 checksum
# under dist/ at the repo root. Requires no external services.
#
# Usage:
#   scripts/package.sh            # build everything, then package
#   scripts/package.sh --skip-build  # reuse existing ./swarmy and apps/web/dist
#
set -euo pipefail

# --- Resolve repo root (directory containing this script's parent) -----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT}"

SKIP_BUILD=0
for arg in "$@"; do
  case "${arg}" in
    --skip-build) SKIP_BUILD=1 ;;
    -h|--help)
      grep '^#' "${BASH_SOURCE[0]}" | grep -v '^#!' | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "package.sh: unknown argument: ${arg}" >&2
      exit 2
      ;;
  esac
done

# --- Derive version / platform metadata --------------------------------------
VERSION="$(sed -n 's/^version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' swarmy.nimble | head -n1)"
if [ -z "${VERSION}" ]; then
  echo "package.sh: could not read version from swarmy.nimble" >&2
  exit 1
fi
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
NAME="swarmy-${VERSION}-${OS}-${ARCH}"

echo "==> Packaging ${NAME}"

# --- Build (unless skipped) --------------------------------------------------
if [ "${SKIP_BUILD}" -eq 0 ]; then
  echo "==> Building Nim backend (nimble build)"
  nimble build
  echo "==> Building web frontend (apps/web)"
  npm run build --workspace apps/web
else
  echo "==> Skipping build (--skip-build); reusing existing artifacts"
fi

# --- Verify required build outputs exist -------------------------------------
BIN="${ROOT}/swarmy"
WEB_DIST="${ROOT}/apps/web/dist"
if [ ! -x "${BIN}" ]; then
  echo "package.sh: backend binary not found at ${BIN} (run without --skip-build)" >&2
  exit 1
fi
if [ ! -d "${WEB_DIST}" ] || [ ! -f "${WEB_DIST}/index.html" ]; then
  echo "package.sh: web bundle not found at ${WEB_DIST} (run without --skip-build)" >&2
  exit 1
fi

# --- Stage into a temp directory ---------------------------------------------
STAGE_PARENT="$(mktemp -d "${TMPDIR:-/tmp}/swarmy-pkg.XXXXXX")"
cleanup() { rm -rf "${STAGE_PARENT}"; }
trap cleanup EXIT

STAGE="${STAGE_PARENT}/${NAME}"
mkdir -p "${STAGE}/bin" "${STAGE}/web"

cp "${BIN}" "${STAGE}/bin/swarmy"
chmod +x "${STAGE}/bin/swarmy"
cp -R "${WEB_DIST}/." "${STAGE}/web/"
cp "${ROOT}/README.md" "${STAGE}/README.md"
cp "${ROOT}/LICENSE" "${STAGE}/LICENSE"

# --- Produce the tarball + checksum under dist/ ------------------------------
DIST="${ROOT}/dist"
mkdir -p "${DIST}"
TARBALL="${DIST}/${NAME}.tar.gz"
SHAFILE="${TARBALL}.sha256"

rm -f "${TARBALL}" "${SHAFILE}"
# -C the staging parent so the archive contains the top-level NAME/ directory.
tar -czf "${TARBALL}" -C "${STAGE_PARENT}" "${NAME}"

# sha256: prefer sha256sum, fall back to shasum (macOS).
if command -v sha256sum >/dev/null 2>&1; then
  ( cd "${DIST}" && sha256sum "${NAME}.tar.gz" > "${NAME}.tar.gz.sha256" )
  SHA="$(cut -d' ' -f1 < "${SHAFILE}")"
else
  ( cd "${DIST}" && shasum -a 256 "${NAME}.tar.gz" > "${NAME}.tar.gz.sha256" )
  SHA="$(cut -d' ' -f1 < "${SHAFILE}")"
fi

echo "==> Artifact: ${TARBALL}"
echo "==> SHA256:   ${SHA}"

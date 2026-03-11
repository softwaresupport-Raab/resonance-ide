#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VSCODE_DIR="${VSCODE_DIR:-${ROOT_DIR}/../vscode}"
MODE="patch"
QUALITY="${VSCODE_QUALITY:-stable}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --full)
      MODE="full"
      shift
      ;;
    --patch-only)
      MODE="patch"
      shift
      ;;
    --vscode-dir)
      VSCODE_DIR="$2"
      shift 2
      ;;
    --quality)
      QUALITY="$2"
      shift 2
      ;;
    *)
      echo "Unknown arg: $1" >&2
      echo "Usage: ./preflight.sh [--patch-only|--full] [--vscode-dir <path>] [--quality stable|insider]" >&2
      exit 2
      ;;
  esac
done

UPSTREAM_JSON="${ROOT_DIR}/upstream/${QUALITY}.json"
if [[ ! -f "${UPSTREAM_JSON}" ]]; then
  echo "Missing upstream definition: ${UPSTREAM_JSON}" >&2
  exit 1
fi

if [[ ! -d "${VSCODE_DIR}/.git" ]]; then
  echo "Missing vscode git repo at ${VSCODE_DIR}" >&2
  echo "Run ./get_repo.sh first." >&2
  exit 1
fi

MS_COMMIT="$(node -e "const fs=require('fs');const p=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));process.stdout.write(p.commit);" "${UPSTREAM_JSON}")"
MS_TAG="$(node -e "const fs=require('fs');const p=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));process.stdout.write(p.tag);" "${UPSTREAM_JSON}")"

if [[ -z "${RELEASE_VERSION:-}" ]]; then
  export RELEASE_VERSION="${MS_TAG}"
fi

export VSCODE_QUALITY="${QUALITY}"

source "${ROOT_DIR}/utils.sh"

echo "[preflight] quality=${QUALITY} commit=${MS_COMMIT} release=${RELEASE_VERSION}"

echo "[preflight] validating builtInExtensions VSIX checksums..."
node - <<'EOF' "${ROOT_DIR}/product.json" "${ROOT_DIR}"
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const product = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const root = process.argv[3];
const exts = product.builtInExtensions || [];
let failed = false;
for (const ext of exts) {
  if (!ext.vsix || !ext.sha256) continue;
  const localName = ext.vsix.split('/').pop();
  const filePath = path.join(root, localName);
  if (!fs.existsSync(filePath)) {
    console.error(`[checksum] missing VSIX file: ${filePath} for ${ext.name}`);
    failed = true;
    continue;
  }
  const hash = crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex');
  if (hash !== ext.sha256) {
    console.error(`[checksum] mismatch for ${ext.name}: expected ${ext.sha256}, actual ${hash}`);
    failed = true;
  } else {
    console.log(`[checksum] ok ${ext.name}`);
  }
}
if (failed) process.exit(1);
EOF

echo "[preflight] resetting vscode tree to clean upstream commit..."
git -C "${VSCODE_DIR}" checkout "${MS_COMMIT}"
git -C "${VSCODE_DIR}" reset --hard "${MS_COMMIT}"
git -C "${VSCODE_DIR}" clean -fd

echo "[preflight] applying patches in CI order..."
pushd "${VSCODE_DIR}" >/dev/null
for patch in "${ROOT_DIR}"/patches/*.patch; do
  apply_patch "${patch}" "quiet"
  echo "  ok $(basename "${patch}")"
done
popd >/dev/null

if [[ "${MODE}" == "full" ]]; then
  echo "[preflight] running extended compile checks..."
  pushd "${VSCODE_DIR}" >/dev/null
  export NODE_OPTIONS="--max-old-space-size=8192"
  npm run monaco-compile-check
  npm run valid-layers-check
  npm run gulp compile-build-without-mangling
  npm run gulp compile-extension-media
  npm run gulp compile-extensions-build
  popd >/dev/null
fi

echo "[preflight] success (${MODE})"

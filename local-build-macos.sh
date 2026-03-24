#!/usr/bin/env bash
# Local macOS arm64 build script
# Usage: ./local-build-macos.sh
set -ex

PATCHED_BUILD_SH=0

cleanup() {
  if [[ "${PATCHED_BUILD_SH}" == "1" ]] && [[ -f build.sh.bak ]]; then
    mv build.sh.bak build.sh
  fi
  rm -f /tmp/node-extra-ca-certs.pem
}

trap cleanup EXIT

# Ensure we're in the resonance-ide directory
cd "$(dirname "$0")"

# Ensure correct Node version (nvm doesn't auto-switch in non-interactive shells)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
nvm use 22.21.1 || { echo "Error: Node 22.21.1 not installed. Run: nvm install 22.21.1"; exit 1; }

export OS_NAME=osx
export VSCODE_ARCH=arm64
export VSCODE_QUALITY=stable
export SHOULD_BUILD=yes
export APP_NAME=Resonance
export BINARY_NAME=resonance
export CI_BUILD=no
export NODE_OPTIONS="--max-old-space-size=8192"

# Fix for Zscaler/corporate proxy SSL interception:
# Export system keychain CAs so Node.js trusts the corporate root CA
security find-certificate -a -p /Library/Keychains/System.keychain > /tmp/node-extra-ca-certs.pem 2>/dev/null
export NODE_EXTRA_CA_CERTS=/tmp/node-extra-ca-certs.pem

echo "=== Step 1: get_repo ==="
. ./get_repo.sh

echo "=== Step 2: build ==="
# Skip CLI build if Rust is not installed (code tunnel binary, not essential for IDE)
if ! command -v rustup &>/dev/null; then
  echo "⚠️  Rust not installed — skipping CLI tunnel binary build"
  if grep -q '\. \..\/build_cli\.sh' build.sh; then
    sed -i.bak 's|\. \..\/build_cli\.sh|echo "SKIP: build_cli.sh (no Rust)"|' build.sh
    PATCHED_BUILD_SH=1
  fi
fi
. ./build.sh

echo "=== Step 3: prepare_assets (unsigned) ==="
. ./prepare_assets.sh

echo "=== DONE ==="
echo "Output in: assets/"
ls -lh assets/ 2>/dev/null || echo "No assets directory found"

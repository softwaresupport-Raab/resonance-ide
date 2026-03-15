# Bundled CLI Tools — Implementation Plan

## Goal

Ship a standalone Node.js runtime + pre-installed CLI tools (Playwright MCP, Context7 MCP) inside the Resonance IDE app bundle so that **users need zero external dependencies** — no Node.js, no npm, no terminal setup.

---

## Current State

`product.json` configures MCP servers as:

```json
"mcp": {
  "servers": {
    "playwright": { "command": "npx", "args": ["@playwright/mcp@latest"] },
    "context7":   { "command": "npx", "args": ["@upstash/context7-mcp@latest"] }
  }
}
```

This requires `npx` (= Node.js) on the user's system PATH. If the user has no Node.js installed, both servers fail silently.

---

## Target State

```
# macOS
Resonance.app/Contents/Resources/
├── bundled-node/
│   └── bin/
│       ├── node          ← standalone Node.js 22.x binary (~45 MB)
│       └── npx
├── bundled-cli/
│   ├── playwright-mcp/
│   │   ├── node_modules/
│   │   └── package.json
│   └── context7-mcp/
│       ├── node_modules/
│       └── package.json

# Linux
VSCode-linux-x64/resources/
├── bundled-node/...
├── bundled-cli/...

# Windows
Resonance/resources/
├── bundled-node/...
├── bundled-cli/...
```

`product.json` changes to use resolved internal paths (no system dependencies):

```json
"mcp": {
  "servers": {
    "playwright": {
      "command": "${execPath}/../Resources/bundled-node/bin/node",
      "args": ["${execPath}/../Resources/bundled-cli/playwright-mcp/node_modules/@playwright/mcp/cli.js"]
    },
    "context7": {
      "command": "${execPath}/../Resources/bundled-node/bin/node",
      "args": ["${execPath}/../Resources/bundled-cli/context7-mcp/node_modules/@upstash/context7-mcp/cli.js"]
    }
  }
}
```

> **Note:** The exact `${execPath}` variable syntax depends on how the Cline extension resolves MCP config. This needs verification — see Task 0 below.

---

## No Conflict with User's Node.js

The bundled Node.js is a standalone binary in a private directory. It does **not** modify the user's `PATH`, does not register with `nvm`/`fnm`/Homebrew, and does not share `node_modules` or caches. If the user already has Node.js installed, both coexist without interference.

---

## Tasks

### Task 0 — Verify path variable support in MCP config

**What:** Determine how the Cline extension resolves the `command` field in MCP server config. Does it support `${execPath}` or similar variables? If not, we need to resolve the path at runtime in `McpHub.ts`.

**Where:** `resonance-extension/src/services/mcp/McpHub.ts` — the `StdioClientTransport` instantiation.

**Effort:** 1–2 hours research + possible small code change.

**Acceptance:** A bundled MCP server can be spawned using a path relative to the app installation directory, regardless of where the user installed the app.

---

### Task 1 — Create `prepare_bundled_cli.sh`

**What:** New build script in `resonance-ide/` that:

1. **Downloads the correct Node.js binary** for the target platform/arch:
   - Source: `https://nodejs.org/dist/v22.21.1/node-v22.21.1-{platform}-{arch}.tar.gz`
   - Platforms: `darwin-arm64`, `darwin-x64`, `linux-x64`, `win-x64`
   - Extracts only `bin/node` and `bin/npx` (skip docs, headers, npm full install)
   - Places into `bundled-node/bin/`

2. **Installs CLI tool packages** into isolated directories:
   ```bash
   mkdir -p bundled-cli/playwright-mcp
   cd bundled-cli/playwright-mcp
   npm init -y
   npm install @playwright/mcp@latest --omit=dev

   mkdir -p ../context7-mcp
   cd ../context7-mcp
   npm init -y
   npm install @upstash/context7-mcp@latest --omit=dev
   ```

3. **Copies results** into the build output directory:
   - macOS: `VSCode-darwin-${VSCODE_ARCH}/Resonance.app/Contents/Resources/`
   - Linux: `VSCode-linux-${VSCODE_ARCH}/resources/`
   - Windows: `VSCode-win32-${VSCODE_ARCH}/resources/`

**Where:** New file `resonance-ide/prepare_bundled_cli.sh`

**Effort:** 2–3 hours.

**Skeleton:**

```bash
#!/usr/bin/env bash
set -ex

NODE_VERSION="22.21.1"

# Determine platform string for Node.js download
case "${OS_NAME}" in
  osx)     NODE_PLATFORM="darwin"  ;;
  linux)   NODE_PLATFORM="linux"   ;;
  windows) NODE_PLATFORM="win"     ;;
esac

case "${VSCODE_ARCH}" in
  arm64) NODE_ARCH="arm64" ;;
  x64)   NODE_ARCH="x64"   ;;
esac

# --- Download Node.js ---
NODE_TARBALL="node-v${NODE_VERSION}-${NODE_PLATFORM}-${NODE_ARCH}.tar.gz"
NODE_URL="https://nodejs.org/dist/v${NODE_VERSION}/${NODE_TARBALL}"

mkdir -p bundled-node/bin
curl -fsSL "${NODE_URL}" | tar xz --strip-components=1 -C bundled-node

# Keep only what we need
find bundled-node -mindepth 1 -maxdepth 1 ! -name bin ! -name lib -exec rm -rf {} +

# --- Install CLI tools ---
install_cli_tool() {
  local name="$1"
  local package="$2"
  mkdir -p "bundled-cli/${name}"
  pushd "bundled-cli/${name}"
  npm init -y --silent
  npm install "${package}" --omit=dev --silent
  popd
}

install_cli_tool "playwright-mcp" "@playwright/mcp@latest"
install_cli_tool "context7-mcp"   "@upstash/context7-mcp@latest"

# --- Copy into app bundle ---
case "${OS_NAME}" in
  osx)
    DEST="../VSCode-darwin-${VSCODE_ARCH}/Resonance.app/Contents/Resources"
    ;;
  linux)
    DEST="../VSCode-linux-${VSCODE_ARCH}/resources"
    ;;
  windows)
    DEST="../VSCode-win32-${VSCODE_ARCH}/resources"
    ;;
esac

cp -r bundled-node "${DEST}/"
cp -r bundled-cli  "${DEST}/"

echo "Bundled CLI tools installed to ${DEST}"
```

---

### Task 2 — Wire into the build pipeline

**What:** Call `prepare_bundled_cli.sh` from `build.sh` after the VS Code build completes and before `prepare_assets.sh` runs.

**Where:** `resonance-ide/build.sh` — add one line after the platform-specific build step:

```bash
. ../prepare_bundled_cli.sh
```

**Effort:** 15 minutes.

---

### Task 3 — Update product.json MCP paths

**What:** Change the MCP server entries in `resonance-ide/product.json` to use the bundled binaries instead of `npx`.

**Where:** `resonance-ide/product.json` → `configurationDefaults.mcp.servers`

**Depends on:** Task 0 (path variable syntax confirmed).

**Effort:** 30 minutes.

---

### Task 4 — Update `dev-preview.sh` for local testing

**What:** For local development, either:
- (a) Run `prepare_bundled_cli.sh` once locally and symlink the result, or
- (b) Fall back to system `npx` in dev mode (current behavior)

This is optional — dev mode can use the user's own Node.js since developers will have it installed. But it would be nice for testing the bundled path resolution.

**Where:** `resonance/dev-preview.sh`

**Effort:** 30 minutes.

---

### Task 5 — Test on clean system

**What:** Verify end-to-end on a system without Node.js:
1. Build the app via CI
2. Install on a macOS machine with no Node.js
3. Open Resonance → use the AI assistant → trigger Playwright MCP
4. Confirm it works without any "npx not found" errors

**Effort:** 1–2 hours (mostly waiting for CI build).

---

## Size Impact

| Component | Size (approx) |
|---|---|
| Node.js binary (single platform) | ~45 MB |
| `@playwright/mcp` + deps | ~8 MB |
| `@upstash/context7-mcp` + deps | ~5 MB |
| **Total added to installer** | **~58 MB** |

Current installer is ~300 MB, so this is a ~20% increase. Acceptable for a zero-config experience.

---

## Risks & Open Questions

| # | Question | Impact | Mitigation |
|---|---|---|---|
| 1 | Does the Cline MCP config support path variables like `${execPath}`? | If not, we need runtime path resolution in `McpHub.ts` | Task 0 answers this |
| 2 | Windows: Node.js ships as `.zip` not `.tar.gz` | Different extraction logic | Add Windows-specific download path in script |
| 3 | Will `@playwright/mcp` try to download browser binaries at runtime? | Could fail without network / disk space | Set `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1` at install time; Playwright MCP uses Chrome DevTools Protocol to connect to existing browsers |
| 4 | Future CLI tools — how to add more? | Maintenance burden | Keep `prepare_bundled_cli.sh` as a simple list; adding a tool = one `install_cli_tool` call |
| 5 | Node.js security updates | Bundled binary could become outdated | Pin version in script; update when we update the build |

---

## Total Effort Estimate

| Task | Effort |
|---|---|
| Task 0 — Verify path variables | 1–2 h |
| Task 1 — `prepare_bundled_cli.sh` | 2–3 h |
| Task 2 — Wire into build | 15 min |
| Task 3 — Update product.json | 30 min |
| Task 4 — Dev-preview support | 30 min |
| Task 5 — E2E test | 1–2 h |
| **Total** | **~half a day** |

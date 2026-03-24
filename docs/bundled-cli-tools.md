# Bundled CLI Tools — Implementation Plan

## Goal

Ship a standalone Node.js runtime + pre-installed [Playwright CLI](https://github.com/microsoft/playwright-cli) inside the Resonance IDE app bundle so that **users need zero external dependencies** — no Node.js, no npm, no terminal setup.

---

## What is Playwright CLI?

Playwright CLI (`@playwright/cli`) is **not MCP**. It is a traditional CLI binary the AI calls via shell commands:

```bash
playwright-cli open https://example.com
playwright-cli click e1
playwright-cli screenshot
playwright-cli type "hello"
```

The AI agent uses it through the `execute_command` tool — the same way it runs `git`, `grep`, or any other terminal command. No persistent server, no protocol overhead.

**Why CLI over MCP for browser automation:**
- **Token-efficient** — does not force page DOM/accessibility tree into the LLM context
- **Command-based** — the AI reads the skill from `playwright-cli --help` directly
- **Stateful sessions** — browser stays open between commands within a task

---

## How the AI learns to use it

Playwright CLI ships with built-in "skills" — structured reference files for common tasks (request mocking, test generation, storage state, tracing, video recording, etc.). Installing skills makes them available to the agent automatically:

```bash
playwright-cli install --skills
```

This writes skill files into the workspace. GitHub Copilot and Claude Code both read them automatically.

---

## Current Problem

If the user has no Node.js installed, `playwright-cli` is unavailable. The AI cannot call it, and there is no fallback. The tool silently doesn't exist.

---

## Target State

Bundle Node.js + `playwright-cli` inside the app. The AI can always call `playwright-cli` regardless of what the user has installed.

```
# macOS
Resonance.app/Contents/Resources/
├── bundled-node/
│   └── bin/
│       ├── node              ← standalone Node.js 22.x binary
│       ├── npx
│       └── playwright-cli    ← launcher script (calls node + entry point)
├── bundled-cli/
│   └── playwright-cli/
│       ├── node_modules/
│       │   └── @playwright/cli/
│       └── package.json

# Linux
VSCode-linux-x64/resources/
├── bundled-node/...
├── bundled-cli/...

# Windows
VSCode-win32-x64/resources/
├── bundled-node/
│   ├── node.exe
│   └── playwright-cli.cmd    ← Windows launcher
├── bundled-cli/...
```

The Resonance extension uses the VS Code `EnvironmentVariableCollection` API to prepend `bundled-node/bin` to terminal PATH at runtime — non-persistent, auto-cleaned on deactivation.

---

## PATH Precedence

The bundled `playwright-cli` **wins** over a user-installed version. This is intentional — it guarantees the "it just works" contract. If a user has their own version and wants to override, they can do so explicitly via their shell config (`.zshrc` etc.) — that's an advanced user making a deliberate choice.

---

## Browser Requirement

Playwright CLI connects to existing Chromium-based browsers on the system via the DevTools Protocol. It does **not** manage or download its own browser binaries. This means:

- **macOS**: requires Chrome, Edge, or Brave (Safari is not supported)
- **Windows**: works out of the box — Edge (Chromium) ships with every Windows 10+
- **Linux**: requires Chrome or Chromium to be installed

If no supported browser is found, `playwright-cli open` shows a clear error message. The build script sets `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1` to prevent any attempt to download managed browsers.

---

## No Conflict with User's Node.js

The bundled Node.js lives in a private app directory. It does **not** touch the user's PATH globally, does not register with `nvm`/`fnm`/Homebrew, and does not share `node_modules` or caches. The `EnvironmentVariableCollection` only affects terminals within Resonance IDE. It is cleared automatically when the extension deactivates — nothing persists in user settings.

---

## Tasks

### Task 1 — Create `prepare_bundled_cli.sh`

**What:** New build script in `resonance-ide/` that:

1. **Downloads the correct Node.js binary** for the target platform/arch:
   - Source: `https://nodejs.org/dist/v22.21.1/node-v22.21.1-{platform}-{arch}.tar.gz`
   - Platforms: `darwin-arm64`, `darwin-x64`, `linux-x64`
   - Windows: `node-v22.21.1-win-x64.zip` (`.zip`, not `.tar.gz`)
   - Extracts `bin/`, `lib/` (needed for `npm`/`npx` to work)

2. **Installs `@playwright/cli`** at a pinned version into an isolated directory:

   ```bash
   mkdir -p bundled-cli/playwright-cli
   cd bundled-cli/playwright-cli
   ../../bundled-node/bin/npm init -y
   PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
     ../../bundled-node/bin/npm install @playwright/cli@0.1.1 --omit=dev
   ```

   > **Version pinning:** always use an exact version, never `@latest`. Update the pinned version explicitly when upgrading.

3. **Creates platform-specific launcher scripts** in `bundled-node/bin/`:

   **Unix (`playwright-cli`):**
   ```bash
   #!/usr/bin/env sh
   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
   exec "${SCRIPT_DIR}/node" \
     "${SCRIPT_DIR}/../../bundled-cli/playwright-cli/node_modules/@playwright/cli/playwright-cli.js" "$@"
   ```

   **Windows (`playwright-cli.cmd`):**
   ```cmd
   @echo off
   "%~dp0\node.exe" "%~dp0\..\..\bundled-cli\playwright-cli\node_modules\@playwright\cli\playwright-cli.js" %*
   ```

4. **Copies everything** into the platform-specific app bundle:
   - macOS: `VSCode-darwin-${VSCODE_ARCH}/Resonance.app/Contents/Resources/`
   - Linux: `VSCode-linux-${VSCODE_ARCH}/resources/`
   - Windows: `VSCode-win32-${VSCODE_ARCH}/resources/`

**Where:** New file `resonance-ide/prepare_bundled_cli.sh`

**Effort:** 2–3 hours.

**Script skeleton:**

```bash
#!/usr/bin/env bash
set -ex

NODE_VERSION="22.21.1"
PLAYWRIGHT_CLI_VERSION="0.1.1"

case "${OS_NAME}" in
  osx)     NODE_PLATFORM="darwin" ;;
  linux)   NODE_PLATFORM="linux"  ;;
  windows) NODE_PLATFORM="win"    ;;
esac

case "${VSCODE_ARCH}" in
  arm64) NODE_ARCH="arm64" ;;
  x64)   NODE_ARCH="x64"   ;;
esac

# --- Download Node.js ---
if [[ "${OS_NAME}" == "windows" ]]; then
  NODE_ARCHIVE="node-v${NODE_VERSION}-${NODE_PLATFORM}-${NODE_ARCH}.zip"
  NODE_URL="https://nodejs.org/dist/v${NODE_VERSION}/${NODE_ARCHIVE}"
  curl -fsSL "${NODE_URL}" -o node.zip
  unzip -q node.zip
  mv "node-v${NODE_VERSION}-${NODE_PLATFORM}-${NODE_ARCH}" bundled-node
  rm node.zip
else
  NODE_TARBALL="node-v${NODE_VERSION}-${NODE_PLATFORM}-${NODE_ARCH}.tar.gz"
  NODE_URL="https://nodejs.org/dist/v${NODE_VERSION}/${NODE_TARBALL}"
  mkdir -p bundled-node
  curl -fsSL "${NODE_URL}" | tar xz --strip-components=1 -C bundled-node
fi

# Strip docs, headers, man pages — keep only bin/ and lib/
find bundled-node -mindepth 1 -maxdepth 1 \
  ! -name bin ! -name lib -exec rm -rf {} +

# --- Install playwright-cli using the bundled npm ---
mkdir -p bundled-cli/playwright-cli
pushd bundled-cli/playwright-cli
../../bundled-node/bin/npm init -y --silent
PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
  ../../bundled-node/bin/npm install "@playwright/cli@${PLAYWRIGHT_CLI_VERSION}" \
  --omit=dev --silent
popd

# --- Verify the entry point exists ---
ENTRY_POINT="bundled-cli/playwright-cli/node_modules/@playwright/cli/playwright-cli.js"
if [[ ! -f "${ENTRY_POINT}" ]]; then
  # Fall back: check package.json "bin" field for the real path
  ENTRY_POINT=$(node -e "
    const p = require('./bundled-cli/playwright-cli/node_modules/@playwright/cli/package.json');
    const bin = typeof p.bin === 'string' ? p.bin : p.bin['playwright-cli'];
    console.log('bundled-cli/playwright-cli/node_modules/@playwright/cli/' + bin);
  ")
  if [[ ! -f "${ENTRY_POINT}" ]]; then
    echo "ERROR: Cannot find playwright-cli entry point" >&2
    exit 1
  fi
fi

# --- Create launcher wrappers ---
if [[ "${OS_NAME}" == "windows" ]]; then
  # Windows .cmd launcher
  ENTRY_WIN=$(echo "${ENTRY_POINT}" | sed 's|/|\\|g')
  cat > "bundled-node/playwright-cli.cmd" << WINEOF
@echo off
"%~dp0\\node.exe" "%~dp0\\..\\..\\${ENTRY_WIN}" %*
WINEOF
else
  # Unix shell launcher
  cat > "bundled-node/bin/playwright-cli" << EOF
#!/usr/bin/env sh
SCRIPT_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
exec "\${SCRIPT_DIR}/node" "\${SCRIPT_DIR}/../../${ENTRY_POINT}" "\$@"
EOF
  chmod +x "bundled-node/bin/playwright-cli"
fi

# --- Copy into app bundle ---
case "${OS_NAME}" in
  osx)     DEST="../VSCode-darwin-${VSCODE_ARCH}/Resonance.app/Contents/Resources" ;;
  linux)   DEST="../VSCode-linux-${VSCODE_ARCH}/resources" ;;
  windows) DEST="../VSCode-win32-${VSCODE_ARCH}/resources" ;;
esac

cp -r bundled-node "${DEST}/"
cp -r bundled-cli  "${DEST}/"

echo "Bundled playwright-cli v${PLAYWRIGHT_CLI_VERSION} installed to ${DEST}"
```

---

### Task 2 — Wire into the build pipeline

**What:** Call `prepare_bundled_cli.sh` from `build.sh` after the platform-specific build step, before `prepare_assets.sh`.

**Where:** `resonance-ide/build.sh` — add after the platform build completes:

```bash
. ../prepare_bundled_cli.sh
```

**Effort:** 15 minutes.

---

### Task 3 — Inject bundled bin into terminal PATH (extension patch)

**What:** When Resonance starts, the extension uses the VS Code `EnvironmentVariableCollection` API to prepend the bundled bin directory to `PATH` in all integrated terminals. This is:
- **Non-persistent** — only affects the current session, not stored in settings.json
- **Auto-cleaned** — removed when extension deactivates or app closes
- **Cross-platform** — the API handles path separators (`:` vs `;`) automatically

**Where:** `resonance-extension/src/extension.ts` — inside the `activate()` function.

**How:**

```typescript
import * as fs from 'fs'
import * as path from 'path'
import * as vscode from 'vscode'

function injectBundledBinToTerminalPath(context: vscode.ExtensionContext): void {
  // vscode.env.appRoot = .../Resonance.app/Contents/Resources/app (macOS)
  //                     .../resources/app (Linux/Windows)
  const resourcesDir = path.dirname(vscode.env.appRoot)
  const bundledBin = path.join(resourcesDir, 'bundled-node', 'bin')

  // Only inject if bundled binary exists (guards against dev mode)
  const nodeExe = process.platform === 'win32' ? 'node.exe' : 'node'
  if (!fs.existsSync(path.join(bundledBin, nodeExe))) {
    return
  }

  // EnvironmentVariableCollection: non-persistent, auto-cleaned on deactivation
  const envCollection = context.environmentVariableCollection
  envCollection.prepend('PATH', bundledBin + path.delimiter)
}
```

Call `injectBundledBinToTerminalPath(context)` early in `activate()`.

This approach:
- Uses `vscode.env.appRoot` instead of brittle `process.execPath` traversal
- Lets the VS Code API handle `:` (Unix) vs `;` (Windows) via `path.delimiter`
- Never writes to user settings — nothing to clean up on uninstall

**Effort:** 1–2 hours (code + patch export).

**Export patch:**
```bash
cd resonance-extension
git diff src/extension.ts > ../resonance-ide/cline-patches/00X-inject-bundled-bin-path.patch
```

---

### Task 4 — Install skills on first workspace open

**What:** Run `playwright-cli install --skills` automatically when the user opens a workspace for the first time so the AI has the full skill reference available immediately.

**Key design decisions:**
- **Trigger:** runs when a workspace folder is available (not at bare activation — skills need a target directory)
- **Per-workspace:** tracks installed state per workspace (via `workspaceState`), not globally — each workspace gets its own skills
- **Retry:** if install fails, the flag is not set; it retries on next workspace open
- **Non-blocking:** runs asynchronously, does not delay activation

**Where:** `resonance-extension/src/extension.ts` — after PATH injection.

```typescript
const SKILLS_INSTALLED_KEY = 'resonance.playwrightSkillsInstalled'

function installPlaywrightSkillsOnWorkspaceOpen(context: vscode.ExtensionContext): void {
  const resourcesDir = path.dirname(vscode.env.appRoot)
  const playwrightBin = path.join(
    resourcesDir, 'bundled-node', 'bin',
    process.platform === 'win32' ? 'playwright-cli.cmd' : 'playwright-cli'
  )

  if (!fs.existsSync(playwrightBin)) return

  function tryInstall(): void {
    if (context.workspaceState.get(SKILLS_INSTALLED_KEY)) return
    if (!vscode.workspace.workspaceFolders?.length) return

    const cwd = vscode.workspace.workspaceFolders[0].uri.fsPath
    const { execFile } = require('child_process')
    execFile(playwrightBin, ['install', '--skills'], { cwd }, (err: Error | null) => {
      if (!err) {
        context.workspaceState.update(SKILLS_INSTALLED_KEY, true)
      }
      // On failure: flag stays unset → retries on next workspace open
    })
  }

  // Try now if workspace is already open
  tryInstall()

  // Also try when workspace folders change (e.g. user opens a folder after launch)
  context.subscriptions.push(
    vscode.workspace.onDidChangeWorkspaceFolders(() => tryInstall())
  )
}
```

**Effort:** 1 hour.

---

### Task 5 — Test on clean system (macOS first)

**What:** Verify end-to-end on a macOS system without Node.js:

1. Build the app via CI (or local build)
2. Install on a macOS machine with Node.js removed / never installed
3. Confirm Chrome or Edge is available as a system browser
4. Open Resonance → open a terminal → run `playwright-cli --help`
5. Run `playwright-cli open https://example.com` → verify browser opens
6. Start an AI task: "Open https://example.com and take a screenshot using playwright-cli"
7. Confirm it works without any "command not found" errors
8. Close Resonance → verify no stale PATH entries in user settings

**Effort:** 1–2 hours (mostly waiting for build).

---

## Size Impact

| Component | Size (approx) |
|---|---|
| Node.js binary (single platform) | ~45 MB |
| `@playwright/cli@0.1.1` + deps | ~12 MB |
| **Total added to installer** | **~57 MB** |

Current installer is ~300 MB — this is a ~19% increase. Acceptable for a zero-config experience.

---

## Risks & Open Questions

| # | Question | Impact | Mitigation |
|---|---|---|---|
| 1 | `playwright-cli` entry point path: is it `playwright-cli.js` or something else? | Launcher script breaks | Build script auto-detects from `package.json` `bin` field; fails build if not found |
| 2 | No Chromium browser on user's machine (mainly Linux) | `playwright-cli open` fails with error | Clear error message from Playwright CLI itself; document browser requirement |
| 3 | Dev mode: `bundled-node/bin/` doesn't exist locally | PATH injection silently skips (`fs.existsSync` guard) | Dev mode uses system node — no regression |
| 4 | Node.js security updates | Bundled binary becomes outdated | Pin version in script; bump alongside app releases |
| 5 | Windows: launcher uses `.cmd`; PowerShell may not run it | Edge case | `.cmd` files work in both `cmd.exe` and PowerShell; VS Code terminal defaults to PowerShell on Windows but `.cmd` is still resolved |
| 6 | Future CLI tools to bundle | Build script grows | `prepare_bundled_cli.sh` is structured as a simple list; adding a tool = one `npm install` + one launcher |

---

## Decisions Made

| Decision | Rationale |
|---|---|
| Use `EnvironmentVariableCollection` not `terminal.integrated.env` settings | Non-persistent, auto-cleaned, no stale PATH. Extension-scoped by design. |
| Bundled version wins over user-installed | Guarantees zero-config contract. Advanced users can override via shell config. |
| Pin exact package versions, not `@latest` | Reproducible builds. Version bumps are explicit and reviewable. |
| Use `vscode.env.appRoot` for path resolution | Documented VS Code API, works across all extension host types. More reliable than `process.execPath` traversal. |
| Per-workspace skills install, not global | Skills write files into the workspace. Each workspace should get its own copy. |
| macOS-first, cross-platform second | Primary target audience. Windows/Linux support wired in but tested separately. |

---

## Total Effort Estimate

| Task | Effort |
|---|---|
| Task 1 — `prepare_bundled_cli.sh` | 2–3 h |
| Task 2 — Wire into build | 15 min |
| Task 3 — PATH injection in extension | 1–2 h |
| Task 4 — Skills install on workspace open | 1 h |
| Task 5 — E2E test (macOS) | 1–2 h |
| **Total (macOS)** | **~1 day** |
| Cross-platform hardening (Windows `.cmd`, Linux test) | +half a day |

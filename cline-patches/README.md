# Resonance Patches for Cline

Patches to rebrand and customize Cline as Resonance, applied on top of Cline v3.78.0.

## Base Version

Cline v3.78.0 (tag v3.78.0)

## Patches

### 001-system-prompt.patch (2 files)
Agent identity and memory system.

### 002-branding.patch (49 files)
All user-facing Cline -> Resonance branding updates.

### 003-commands.patch (4 files)
Resonance slash commands: /setup and /demo.

### 004-ui-customization.patch (19 files)
Compact task header, context ring, auto-approve in settings, navbar simplification, thinking indicator, and related UI behavior.

### 005-defaults-and-infra.patch (6 files)
Default settings and infrastructure fixes (codicon path, devtools script removal, sidebar focus).

### 006-e2e-tests.patch (1 file)
Branding assertion update in e2e tests.

### 007-tests-snapshot-update.patch (49 files)
Updated unit-test snapshots for system prompt integration tests to match Resonance prompt/rules output.

## Quick Start

```bash
# 1. Clone upstream base
git clone --depth 1 --branch v3.78.0 https://github.com/cline/cline.git resonance-extension
cd resonance-extension

# 2. Apply patches in order
git apply ../cline-patches/001-system-prompt.patch
git apply ../cline-patches/002-branding.patch
git apply ../cline-patches/003-commands.patch
git apply ../cline-patches/004-ui-customization.patch
git apply ../cline-patches/005-defaults-and-infra.patch
git apply ../cline-patches/006-e2e-tests.patch
git apply ../cline-patches/007-tests-snapshot-update.patch

# 3. Install and build
npm install
npx @vscode/vsce package
```

## With Commit History

```bash
git am ../cline-patches/001-system-prompt.patch
git am ../cline-patches/002-branding.patch
git am ../cline-patches/003-commands.patch
git am ../cline-patches/004-ui-customization.patch
git am ../cline-patches/005-defaults-and-infra.patch
git am ../cline-patches/006-e2e-tests.patch
git am ../cline-patches/007-tests-snapshot-update.patch
```

## Regenerating Patches

```bash
cd resonance-extension
# Ensure branch has exactly the 7 topic commits on top of v3.78.0
git format-patch v3.78.0..HEAD -o ../resonance-ide/cline-patches/
# Rename 0001-*.patch -> 001-system-prompt.patch, etc.
```

# Resonance Patches for Cline

This directory contains patches to rebrand Cline as **Resonance**, a project management assistant with persistent memory and state machine philosophy.

## Patches Overview

### 001-resonance-system.patch
**System Prompt & Identity**
- Changes agent identity from "Cline, software engineer" to "Resonance, experience assistant"
- Replaces coding-focused rules with Resonance's persistent memory system
- Implements State Machine philosophy with `.resonance/` directory structure
- Adds memory management rules (00_soul.md, 01_state.md, 02_memory.md)
- Introduces The Synch Rule (Micro vs Macro task management)
- Incremental Work Protocol — one tool use at a time with user confirmation

**Files modified:**
- `src/core/prompts/system-prompt/components/agent_role.ts`
- `src/core/prompts/system-prompt/components/rules.ts`

### 002-ui-branding.patch
**User Interface & Branding**
- Changes all user-facing "Cline" references to "Resonance"
- Updates package.json metadata (displayName, publisher, description, keywords)
- Fixes view container IDs (`claude-dev` → `resonance`) for sidebar activation
- Rewrites complete walkthrough for Resonance concepts
- Updates all command titles, menu items, and chat UI strings

**Files modified:**
- `package.json`
- `walkthrough/step1.md` through `step5.md`
- `webview-ui/src/components/chat/ChatRow.tsx`
- `webview-ui/src/components/settings/sections/AboutSection.tsx`
- `webview-ui/src/components/settings/sections/FeatureSettingsSection.tsx`

### 002-scroll-behavior-fix.patch
**Chat Scroll Behavior**
- Fixes scroll-to-bottom behavior in the chat view

**Files modified:**
- `webview-ui/src/components/chat/chat-view/hooks/useScrollBehavior.ts`

### 003-deep-branding.patch
**Deep Branding, Bug Fixes & UI Cleanup**
- Fixes extension activation crash: command prefix mismatch (`registry.ts`)
- Rebrands onboarding flow, startup tips, WhatsNew modal, Welcome view
- Fixes all remaining "Cline" strings across chat UI and settings

**Files modified:**
- `src/registry.ts`, `src/common.ts`, `src/shared/cline/banner.ts`
- Multiple `webview-ui/src/components/...` files

### 003-thinking-indicator.patch
**Thinking Indicator**
- Adds visual thinking indicator to the chat text area

**Files modified:**
- `webview-ui/src/components/chat/ChatTextArea.tsx`

### 004-resonance-defaults.patch
**Default Settings for Resonance**
- Disables checkpoints by default
- Enables "Edit project files" auto-approve by default

**Files modified:**
- `src/shared/storage/state-keys.ts`
- `webview-ui/src/context/ExtensionStateContext.tsx`
- `src/shared/AutoApprovalSettings.ts`

### 005-hide-cost-display.patch
**Hide Cost Bubbles**
- Removes cost chips from task list, history view, and active chat header

**Files modified:**
- `webview-ui/src/components/history/HistoryPreview.tsx`
- `webview-ui/src/components/history/HistoryViewItem.tsx`
- `webview-ui/src/components/chat/task-header/TaskHeader.tsx`

### 006-preflight-parallelization.patch
**Faster Request Preflight**
- Parallelizes rules/skills/tabs preflight via `Promise.all` — reduces time-to-first-token

**Files modified:**
- `src/core/task/index.ts`

## Quick Start

### Build Process

```bash
# 1. Clone Cline at pinned version
git clone --depth 1 --branch v3.57.1 https://github.com/cline/cline.git resonance-extension
cd resonance-extension

# 2. Apply patches in order
git apply ../cline-patches/001-resonance-system.patch
git apply ../cline-patches/002-ui-branding.patch
git apply ../cline-patches/002-scroll-behavior-fix.patch
git apply ../cline-patches/003-deep-branding.patch
git apply ../cline-patches/003-thinking-indicator.patch
git apply ../cline-patches/004-resonance-defaults.patch
git apply ../cline-patches/005-hide-cost-display.patch
git apply ../cline-patches/006-preflight-parallelization.patch

# 3. Install dependencies
npm install

# 4. Build the extension
npx @vscode/vsce package

# Result: resonance-3.57.1.vsix
```

### Installation

```bash
code --install-extension resonance-3.57.1.vsix
```

### Regenerating Patches
After editing files in `resonance-extension/`:

```bash
cd resonance-extension

git diff src/core/prompts/ > ../cline-patches/001-resonance-system.patch
git diff package.json walkthrough/ webview-ui/ > ../cline-patches/002-ui-branding.patch
# etc. — scope each patch to the files it owns
```

## What Changed

### Identity & Philosophy
| Before (Cline) | After (Resonance) |
|----------------|-------------------|
| Autonomous coding agent | Project management assistant |
| Software engineer persona | Experience assistant persona |
| File editing focus | State management focus |
| Coding-centric rules | Memory & knowledge management |

### System Prompt Changes

**Removed:**
- Coding-specific rules (project structure, type checking, linters)
- "Create new project" guidance
- Browser automation for web testing
- Development-focused tool usage

**Added:**
- **THE PRIME DIRECTIVE:** You are NOT a chat bot. You are a State Machine.
- **Persistent Memory System:** `.resonance/` directory (00_soul.md, 01_state.md, 02_memory.md)
- **The Synch Rule:** Micro-tasks in chat, Macro-state in 01_state.md
- **Knowledge Management:** docs/ for specs, 03_backlog.md for TODOs
- **Doc Frontmatter Protocol:** YAML frontmatter with `read_when:` conditions
- **State Machine Thinking:** Current state → Transitions → Goal state

**Kept:**
- Tool usage rules (file operations, terminal commands)
- Working directory constraints
- Communication style (direct, no "Great/Certainly")
- Environment details handling
- MCP integration

### Walkthrough Changes

**Old (Cline):**
1. Agentic Planning
2. Deep Codebase Intelligence
3. Best AI Models
4. MCP Tools
5. Full Visibility & Control

**New (Resonance):**
1. **State Machine, Not Chatbot** - Persistent memory in .resonance/
2. **Persistent Memory System** - 00_soul.md, 01_state.md, 02_memory.md
3. **The Synch Rule** - Micro vs Macro task management
4. **Knowledge Management** - docs/ and backlog organization
5. **You're in Control** - BYOK, transparency, review changes

### Metadata Changes

```json
{
  "name": "resonance",
  "displayName": "Resonance",
  "publisher": "resonance-team",
  "description": "Your project management assistant with persistent memory...",
  "repository": "https://github.com/resonance/resonance",
  "homepage": "https://resonance.app",
  "keywords": [
    "resonance", "project-management", "state-machine",
    "memory", "work-packages", "knowledge-management",
    "ai-assistant", "persistent-memory", "task-management"
  ]
}
```

## Resonance Memory System

### Directory Structure
```
.resonance/
├── 00_soul.md         # Project vision and North Star
├── 01_state.md        # Current work package, goals, next steps
├── 02_memory.md       # Immutable log of lessons learned
└── 03_backlog.md      # Quick TODOs and ideas

docs/
├── research/          # Research documents
├── assets/            # Project assets
└── strategy/          # Strategic planning docs
```

### Session Workflow
1. **On Session Start:** Read `.resonance/01_state.md`
2. **During Work:** Manage micro-tasks in chat
3. **At Milestones:** Update `01_state.md` with macro-state
4. **When Learning:** Log to `02_memory.md` with problem/solution/reference
5. **Quick Ideas:** Add to `03_backlog.md`

## Maintenance

### Updating to a newer Cline version

```bash
# 1. Clone the new version
git clone --depth 1 --branch vX.Y.Z https://github.com/cline/cline.git /tmp/cline-update
cd /tmp/cline-update

# 2. Check patches apply cleanly
git apply --check ../cline-patches/001-resonance-system.patch
# ... repeat for each patch

# 3. If conflicts occur, use --reject to apply partially, fix .rej files manually
git apply --reject ../cline-patches/001-resonance-system.patch

# 4. Once all patches apply, swap resonance-extension/ with the new clone
```

---

**Last Updated:** 2026-03-08

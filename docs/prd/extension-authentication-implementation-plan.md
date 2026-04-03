# Implementation Plan: Extension Authentication Requirement

## Goal
Implement a single extension-wide authentication policy so all protected Resonance extension functionality requires login, while normal VS Code behavior remains available without login.

## Prerequisites
- [x] High-level goal provided by user.
- [ ] Clean git worktree.

Current status:
- Goal is clear.
- Worktree is not clean in participating repos (`resonance-extension`, `resonance-ide`, and `vscode`), so implementation should be isolated and validated with scoped diffs.

## Existing Capabilities To Reuse

### Auth Lifecycle Already Implemented
- Auth request creation and browser launch are already implemented in `AuthService.createAuthRequest()`.
- Auth callback handling and authenticated state update already exist (`AuthService.handleAuthCallback()`, `Controller.handleAuthCallback()`).
- Startup session restore already exists (`AuthService.restoreRefreshTokenAndRetrieveAuthInfo()` called from controller initialization).

### Token and Refresh Management Already Implemented
- Token retrieval and refresh-on-expiry logic is already in place in `AuthService.getAuthToken()` and `ClineAuthProvider.retrieveClineAuthInfo()/refreshToken()`.
- Auth token prefixing and backend expectations are already standardized (`workos:` token handling).

### Backend Contract Already Implemented
- Auth endpoints exist and are consumed by extension:
  - `/api/v1/auth/authorize`
  - `/api/v1/auth/token`
  - `/api/v1/auth/refresh`
  - `/api/v1/users/me`
- Account and organization access APIs already use authenticated requests via `ClineAccountService`.

### Partial Guarding Already Implemented
- Cline provider already fails when no token is available (`CLINE_ACCOUNT_AUTH_ERROR_MESSAGE`).
- Some tools (for example web fetch/search handlers) already enforce account auth.
- Auth error classification is already present in error handling.

### Callback Transport Already Implemented
- Local callback server path is already implemented with `AuthHandler` and URI handling (`SharedUriHandler`) for OAuth completion.

## Gap Analysis (What Is Missing)
1. No single, explicit guard policy at extension boundary.
2. Guard checks are scattered and inconsistent by feature.
3. UI does not consistently show blocked state for all protected actions.
4. Test coverage for "unauthenticated cannot use extension" is incomplete.
5. Session validity requirement (2 weeks) is not documented as enforceable acceptance criteria at product level.

## Proposed Architecture

### Policy Definition
Introduce one policy: "protected extension capabilities require authenticated account session."

Protected includes:
- Task initiation/execution.
- Model/provider calls requiring account.
- Account-scoped APIs (balance, usage, org actions, remote config).
- Hosted tools that rely on account credentials.

Not protected:
- Native VS Code editor/workbench capabilities outside Resonance extension.

### Guard Strategy
Add a reusable guard utility in extension core (for example `AuthRequirementGuard`) with:
- `requireAuthenticated({ reason, action })` helper.
- Standard failure result shape + user-facing message contract.
- Optional auto-trigger to start login flow.

Integrate this guard at all entry points rather than only inside lower-level providers.

## Modules

### [NEW]
1. `src/core/auth/AuthRequirementGuard.ts`
- Central guard helper for protected entry points.
- Defines protected-action enums and default behaviors.

2. `src/core/auth/protected-actions.ts`
- Typed inventory of protected surfaces for auditability and testability.

3. `src/core/auth/__tests__/AuthRequirementGuard.test.ts`
- Unit tests for allow/deny behavior and message mapping.

### [MODIFY]
1. `src/core/controller/index.ts`
- Add guard checks before task and protected controller actions.
- Ensure blocked-state message updates are posted consistently to webview.

2. `src/core/task/index.ts`
- Add early auth precondition before task execution paths.

3. `src/core/api/providers/cline.ts`
- Keep provider-level fail-closed behavior, but align error signaling with shared guard contract.

4. `src/core/storage/remote-config/fetch.ts`
- Ensure all account/organization config fetches are guard-compliant.

5. `src/services/account/ClineAccountService.ts`
- Consolidate unauthorized handling and avoid duplicated fallback behavior.

6. `webview-ui/src/context/ExtensionStateContext.tsx`
- Add canonical auth-required state model for rendering blocked UI states.

7. `webview-ui/src/components/chat/ChatView.tsx`
- Block task input/submit when unauthenticated; show sign-in CTA.

8. `webview-ui/src/components/settings/ClineAccountInfoCard.tsx`
- Ensure sign-in/sign-out state is the primary gate explanation for protected features.

9. `src/extension.ts`
- Validate restore + auth-state synchronization events remain reliable across window lifecycle.

10. `src/shared/ClineAccount.ts`
- Keep shared auth-required messaging contract, avoid message drift across components.

## Effort Estimate

### Phase 1: Guard Foundation (1-2 days)
- Add shared guard utility.
- Build protected-action inventory.
- Add unit tests for guard logic.

### Phase 2: Entry-Point Enforcement (2-4 days)
- Wire guard into controller/task/provider/account surfaces.
- Normalize unauthorized behavior and error paths.

### Phase 3: UX Gating and Polish (1-2 days)
- Add blocked-state UX to chat and settings surfaces.
- Ensure CTA routes to existing login flow.

### Phase 4: Verification and Hardening (1-2 days)
- Integration tests for startup restore, expiry, and sign-out.
- Manual walkthrough and regression checks.

Total estimated effort: 5-10 engineering days.

## Verification Plan

### Automated
1. `cd resonance-extension`
2. `npm run check-types`
3. `npm run lint`
4. `npm run test`

Required test scenarios:
1. Logged out user attempts to start task -> blocked + sign-in prompt.
2. Logged out user attempts protected tool -> blocked.
3. Successful login unlocks blocked actions without restart.
4. Expired token refresh succeeds -> session stays active.
5. Expired token refresh fails -> session transitions to blocked state.
6. Sign-out returns all protected surfaces to blocked state.

### Manual
1. Launch dev preview.
2. Verify normal VS Code editor actions work while logged out.
3. Verify Resonance extension protected surfaces are blocked pre-login.
4. Complete login and verify all protected flows unlock.
5. Simulate expired token and verify fallback behavior.

## Risks and Mitigations
1. Risk: Missing one protected entry point.
- Mitigation: Use typed protected-surface inventory and explicit checklist test coverage.

2. Risk: Inconsistent UX between chat/settings/other panels.
- Mitigation: Introduce shared blocked-state message and CTA component pattern.

3. Risk: Refresh edge cases causing user confusion.
- Mitigation: Distinguish transient network failures vs invalid token failures in UI messaging.

## Handoff
Plan ready for execution.
Recommended next command flow: run build/verification after implementation through the standard extension test pipeline.

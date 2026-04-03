# Launch PRD: Extension-Wide Login Requirement

## Headline
Require sign-in before any Resonance extension capability can be used, while preserving normal VS Code editor functionality.

## Problem
The extension currently has account authentication primitives but does not uniformly enforce authentication across all user entry points.

Current impact:
- Some features already fail closed when no token is present, but gating is inconsistent.
- Users can still access parts of the extension UX before sign-in.
- Product intent (protected application usage) is not represented as a single, testable policy.

Result: authorization behavior is fragmented, difficult to reason about, and not aligned with a strict "login required" experience.

## Solution
Introduce one explicit product policy: any Resonance extension action that creates, runs, or retrieves protected data requires an authenticated user session.

Policy boundaries:
- VS Code core functionality remains available without login.
- Resonance extension surfaces are visible, but blocked with clear sign-in CTAs until authenticated.
- Backend remains the source of truth for access control.

## User Story
As a Resonance user,
I want a single predictable login requirement for extension capabilities,
so account protection and usage access are consistent across chat, tools, and account-scoped features.

## Scope
### In Scope
- Extension-wide auth guard policy and shared guard utility.
- UI blocked-state behavior and sign-in call to action.
- Guard integration for task creation/execution, web tools, remote config, account APIs, and any protected extension actions.
- Session behavior target: 14-day login validity through refresh-token policy.
- Verification plan and automated tests for logged-out and expired-session behavior.

### Out of Scope
- Locking the full VS Code workbench shell behind login.
- Replacing upstream auth provider architecture.
- Non-extension entitlement changes outside account/auth pathways.

## Functional Requirements
1. Unauthenticated users cannot run Resonance extension protected actions.
2. Protected actions present a consistent "sign in required" state and route to existing login flow.
3. Successful login immediately unlocks extension functionality without restart.
4. Session restore is attempted at startup and after window focus changes where relevant.
5. Expired/invalid sessions degrade gracefully to blocked state and prompt re-authentication.

## Non-Functional Requirements
- Security: fail closed on missing/expired auth token.
- UX: clear blocked-state guidance, no dead-end controls.
- Performance: no heavy auth polling loops; rely on existing refresh and event-driven updates.
- Maintainability: single guard abstraction instead of duplicated auth checks.

## Security and Session Model
- Access token: short lived.
- Refresh token: sliding validity up to 14 days inactivity.
- Backend validates all protected APIs regardless of client state.
- Client treats any auth failure as non-authorized until refresh/login succeeds.

## Risks
1. Regression risk from incomplete guard coverage across extension entry points.
2. UX friction if too many controls appear clickable but blocked.
3. Token refresh edge cases causing transient false-logout states.

## Risk Mitigations
1. Build explicit protected-surface inventory and test matrix.
2. Centralize guard checks and blocked-state component patterns.
3. Add integration tests for refresh, invalid token, and startup restore paths.

## Success Metrics
- 100% of defined protected extension entry points require authentication.
- No backend protected endpoint callable without valid session.
- Reduced auth-related support issues caused by inconsistent gating.

## Open Questions
1. Should read-only local extension screens (for example onboarding copy) remain visible pre-login?
2. Should first-run onboarding happen before login prompt or after login only?
3. Should organization/account selection be required before task execution when multi-org is present?

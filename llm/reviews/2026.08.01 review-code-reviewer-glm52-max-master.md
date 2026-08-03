# Code Review: spec-055-phase-r (master)

Model: GLM-5.2 Thinking (max) · Date: 2026-08-01 · Scope: runtime account-invalidation recovery

## Summary

Phase R changes reviewed across 8 files (4 parallel subagents: Security, Business Logic, Architecture, Standards). Web-parity intent is sound — central 401 interceptor + socket `auth_error` delegation mirrors `auth-session-revoked.ts`. No critical/security-blocker issues. **4 HIGH** findings center on concurrency hygiene (re-entry guard window, Live Activity leak on cold-start wipe, weak test of the guard, unlocked handler var). **5 MEDIUM** are module hygiene / parity gaps. Skipped: Performance (no hot path / DB / loops touched).

Areas reviewed: Security, Business Logic, Architecture, Standards.
Areas skipped: Performance — change touches auth-coordination paths, not data loops / queries / allocations; one-shot wipe has no perf surface.

## Findings (sorted by priority)

### High

1. **[Business Logic / Security]** Re-entry guard does not span the awaited seed exchange in `handleDeviceTokenInvalid`
   - Impact: A burst of REST 401s (e.g. parallel recipe fetches after token revocation) enters `handleDeviceTokenInvalid` N times. The `defer { isHandlingAccountInvalidation = false }` in `handleAccountDeleted` runs after wipe; but `handleDeviceTokenInvalid` only checks the guard at entry and again suspends at `await exchangeSeedForTokenRecoveryProvider(seed)`. Result: N parallel seed exchanges hit the server, N `applySession` calls race on `@MainActor` state. FR-R5 invariant ("single teardown under burst") is violated.
   - Recommendation: Set the guard at the very top of `handleDeviceTokenInvalid`, release in `defer` at the very end. The internal call to `handleAccountDeleted(reason: .restInvalidation)` already short-circuits via the same guard.

2. **[Business Logic / Architecture]** `endAll()` (Live Activity teardown) lives only in `AppContainer.stopForLogout` — cold-start `staleSession` wipe leaks Live Activities
   - Impact: `performStaleSessionHealthCheck()` → `wipeLocalSession(reason: .staleSession)` flips `isAuthenticated = false` but does **not** call `stopForLogout` (that path is wired only via `ContentView.onChange`, which does not fire during bootstrap before the view is mounted). A deleted user's recipe timer Live Activities stay on the Lock Screen until the next manual clear.
   - Recommendation: Move `timerLiveActivityCoordinator.endAll()` into `wipeLocalSession` itself (it is already `@MainActor`-isolated and idempotent), so every wipe path ends Live Activities regardless of who triggered it.

3. **[Business Logic]** `test_double_signal_single_wipe` is sequential, not concurrent — does not exercise FR-R5
   - Impact: The test `await`s the first call to completion, then the second. The re-entry guard is never actually contested. A regression that breaks the guard would still pass.
   - Recommendation: Rewrite using `async let` / `Task` racing so both calls overlap the wipe suspension point. Assert state only after both complete.

4. **[Security / Architecture]** `APIClient.unauthorizedHandler` is `public var` on a `@unchecked Sendable` singleton, no lock
   - Impact: The "set once from `AppContainer.init`" contract is documented in a comment but not enforced. A test reassigning the handler concurrently with a 401 in flight, or a future module writing it, produces a data race.
   - Recommendation: Wrap reads/writes in the existing `authLock` (`OSAllocatedUnfairLock`) on `APIClient`. Single-line change, matches the pattern already used for `authToken` / `userId` on the same class.

### Medium

5. **[Security]** `message.lowercased().contains("not found")` is over-broad
   - Impact: Any 4xx/5xx server response containing the substring `"not found"` (e.g. `"Recipe not found"`, `"Timer not found"`) during a seed-exchange 401 triggers a full silent account wipe. DoS surface for future server-side message changes.
   - Recommendation: Tighten to `statusCode == 404` OR (`statusCode` in `401...404` AND exact case-insensitive match on `"user not found"`). Spec FR-R2 permits the substring, but tighten it to a specific phrase.

6. **[Architecture]** `RecipeSnapshotStore.clear()` is called, `ShoppingListSnapshotStore.clear()` is not
   - Impact: Shopping-list App Intents continue to resolve a deleted user's shopping items after wipe. Spec R6 lists "App Intents cannot resolve recipe entities for a user that no longer exists" — same reasoning applies to shopping items.
   - Recommendation: Add `ShoppingListSnapshotStore.clear()` to `wipeLocalSession`.

7. **[Business Logic]** `SessionWipeReason.deviceTokenInvalidRecovery404` is logged but never passed to `wipeLocalSession`
   - Impact: Misleading audit trail — the log line in `handleDeviceTokenInvalid` reports `wipe_reason: deviceTokenInvalidRecovery404`, but the actual wipe runs with `accountDeletedRest` (inside `handleAccountDeleted(.restInvalidation)`).
   - Recommendation: Either thread the more specific reason into `handleAccountDeleted`, or drop the enum case and the extra log field.

8. **[Standards]** `SessionWipeReason.logout` has no callers (dead code)
   - Impact: Dead enum case, noise.
   - Recommendation: Remove.

9. **[Architecture]** `exchangeSeedForTokenRecoveryProvider` default references `AuthService.shared` from inside an instance method
   - Impact: Subtle coupling — the default impl hops to the singleton instead of `self`. Tests that construct a standalone `AuthService` and forget to override the provider get singleton state bleed.
   - Recommendation: Mark the default closure `@Sendable`-clean and have it call a static helper that takes the seed and returns the outcome, with no `AuthService.shared` reference. Or inject via `init`.

### Low (deferred — noted, not fixed in this PR)

- `Task { @MainActor in … }.value` double-wrapping in `AppContainer.init` handler wiring — functionally correct, slightly noisy.
- Comment polish (British "synchronise" vs project style; dangling comment block at end of `wipeLocalSession`).
- `notifyUnauthorizedIfNeeded` is `public` but only the main app should call it — could be `internal`.
- Seed-exchange path re-fires `notifyUnauthorizedIfNeeded` on its own 401 (re-entry guard absorbs it, but generates a redundant audit event).

## Recommendation

**Changes Requested** — address the 4 HIGH findings before merge. MEDIUM #5, #6, #8, #9 are cheap enough to fold in; #7 is a logging-only change. With HIGH fixes applied, the change is approved.

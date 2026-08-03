# Code Review: master (spec 058 Live Activity Push)

## Summary

Native client for Live Activity push updates (register/unregister ActivityKit tokens, `pushType: .token`, background APNs ownership) is directionally solid: composition-root wiring, logout cache wipe on the main path, entitlements split, and registrar unit tests cover HTTP dedup/rotation.

**Risk: high** — one correctness hole can leave Lock Screen cards stuck after self-resume while backgrounded; foreground ordering does not fully close the APNs-vs-local race the change set aims to fix. Test coverage does not protect those paths.

**Areas reviewed:** Security, Business Logic, Architecture, Standards  
**Skipped:** Performance — no hot-path/query/allocation focus in this delta beyond incidental UserDefaults scans.

**Reviewers:** [Security](c206479a-d229-403a-b000-6d45e98d380b) (clean), [Business Logic](1df360fd-9c79-4ea2-8267-e49e7a51736e), [Architecture](1e94b577-aa37-46fa-9aec-78a9f74dab1f), [Standards](7a76d404-9391-46f9-a7a8-d4f5df3fa8ab).

**Out of scope in working tree:** `AppTypography.swift` / `AccountView.swift` (unrelated), server twin in `recipe-scaler-web`.

## Findings (sorted by priority)

### Critical

1. **[Business Logic]** Background skip of `.running` local updates also blocks **self-driven resume** (Lock Screen / App Intent) while `applicationState != .active`. Spec R7 / US5 exclude the source device from APNs, so nothing else repairs the card.
   - **Where:** `TimerLiveActivityCoordinator.sync` (~L137–171); call path `ResumeRecipeTimerIntent` → drain → `TimerManager.resumeTimer` → `syncLiveActivity`.
   - **Impact:** Pause from LA still works (`.paused` allowed). Resume from Lock Screen updates timer + server in memory but leaves the Live Activity paused until a later foreground sync.
   - **Recommendation:** Apply the background `.running` skip only to remote/reconcile/progress paths — not to explicit local resume / addTime / user-driven sync.

### High

2. **[Business Logic]** Foreground `loadActiveTimersFromServer` before reminders does not stop stale local `.running` from winning vs APNs.
   - **Where:** `ContentView` foreground Task; `TimerManager.syncLiveActivityProgress` runs as soon as `applicationState == .active`; `loadActiveTimersFromServer` can no-op via `minLoadInterval` / `isLoadingTimers`.
   - **Impact:** Watch/web pause applied by APNs can be overwritten with stale in-memory running state on return to the app — the race 058 tried to close.
   - **Recommendation:** Suppress local LA `.running` updates until foreground server load finishes (or fails); force load on foreground (bypass `minLoadInterval`); then reconcile.

3. **[Business Logic / Architecture]** Plan positive invariants for APNs ownership and token lifecycle are largely untested; observation/epoch/backoff has no injectable seam.
   - **Where:** `TimerLiveActivityCoordinatorPushTokenTests` only asserts `unregister` on `end`; `startObservingPushToken` is private over `activity.pushTokenUpdates`.
   - **Impact:** Findings 1–2 and epoch-invalidation races can ship green.
   - **Recommendation:** Inject `applicationState` / clock / token-stream factory; cover pause-allowed-in-background, resume-allowed-for-user-sync, progress skipped when inactive, epoch → unregister-after-late-register, foreground gate vs progress ticks.

4. **[Architecture]** Token-cache wipe ownership is split and incomplete vs the claimed `FeatureAdoptionStore` mirror.
   - **Where:** `AppContainer.stopForLogout` does `endAll` + `clearAllCachedTokens`; `AuthService.wipeLocalSession` / logout fire-and-forget `endAll` without `clearAllCachedTokens`; `ContentView` → `stopForLogout` is `#if !targetEnvironment(simulator)`.
   - **Impact:** Paths that skip `stopForLogout` leave `liveActivityPushToken.*` keys; can skip legacy migration via `hasCachedToken` and leak prior-user cache across account switch.
   - **Recommendation:** `TimerLiveActivityCoordinator.clearForLogout()` = `endAll()` + `pushRegistrar.clearAllCachedTokens()`; call from every wipe path that clears feature adoption / ends activities.

5. **[Standards]** Missing Spec Kit `tasks.md` for `specs/058-live-activity-push/`.
   - **Impact:** Plan-driven workflow (`spec` → `plan` → `tasks` → execute) has no checklist for iOS done vs residual (e.g. deferred `quickstart.md`).
   - **Recommendation:** Add `tasks.md` from the plan and mark done/remaining before merge.

### Medium

6. **[Standards]** Unrelated `project.pbxproj` reordering mixed with real 058 file adds.
   - **Impact:** Merge-conflict noise; obscures feature delta.
   - **Recommendation:** Keep only new Live Activity Push sources/tests entries; restore unrelated order.

7. **[Standards]** Register tests under-claim the plan POST invariant (`timer_id` + `token` + `device_id` body).
   - **Impact:** Wrong/missing JSON body still passes; DELETE tests already assert query params.
   - **Recommendation:** Decode POST body in the URLProtocol handler and assert fields against fixtures.

8. **[Architecture]** (Related to #3) Push-token observation lacks a test seam beyond `LiveActivityPushRegistering`.
   - **Recommendation:** Token-stream factory or `PushTokenObserving` collaborator.

### Low

9. **[Standards]** `liveActivityPushRegistrar` sits above `// MARK: - Networked services` in `AppContainer` despite being an HTTP client like `pushRegistration`.
   - **Recommendation:** Move under Networked services (preserve init order that wires the coordinator).

## Security

Nothing material: token logs truncated to prefix; register/unregister via `APIClient` auth; DELETE query encoding safe; Debug/Release `aps-environment` correctly split. Cross-user wipe **gaps** are tracked under Architecture (#4), not as a separate auth bypass.

## Recommendation

**Changes Requested**

Block merge until Critical #1 is fixed (or explicitly accepted with a documented US5 exception). Prefer also fixing High #2 and consolidating logout wipe (#4). Expand tests (#3/#7) and add `tasks.md` (#5) before calling native 058 done.

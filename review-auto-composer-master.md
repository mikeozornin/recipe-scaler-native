# Code Review: master

**Date:** 2026-08-04  
**Reviewers:** Security ([848a001d](848a001d-a1ba-4c96-8d4e-608e169a3a8d)), Business Logic ([dc7eab29](dc7eab29-5de9-47e7-8751-3f6266ae1211)), Architecture ([b1eba1ed](b1eba1ed-fda2-4e29-8284-8dba531615ab)), Performance (coordinator — rate limit blocked the dedicated agent)

**Scope:** Uncommitted spec 030 Phase B (widget push + silent refresh + Provider fetch) + crit/high follow-ups from the prior `review-auto-composer-master` pass. Sibling web: `apns-service.ts`, `timer-sync-service.ts`.

## Summary

Prior crit/high (#1–#7) are closed. Business Logic and Architecture approve with zero ≥80 findings. Security found one new critical (unregister-after-wipe) — **fixed in this session**. High (`SharedDeviceId` rotation) — **accepted as install-scoped** (Watch same-account linking). Performance (coordinator): TTL/pending gates correctly short-circuit 1 Hz reloads before HTTP; single-flight + 8s timeout are sound; widget vs silent fan-out does not dual-send; debounce Set is bounded and cleared on flush. One regression was restored during this review (`clearPendingLocalMutation` in `TimerManager.persistTimerSnapshot`).

**Areas reviewed:** Security, Business Logic, Architecture, Performance.  
**Skipped:** none of the five planned areas (Performance done by coordinator after rate limit).

**Verdict: Approved.**

## Findings (sorted by priority)

### Critical

_(none open)_

1. ~~**[security]** Widget push unregister DELETE on logout sent without auth~~ — **FIXED**
   - Was: `AuthService.wipeLocalSession` cleared `SharedAuthStore` before deferred `widgetPushRegistrar.unregister()` → DELETE 401 → orphan `widget_push_tokens` row → cross-account APNs wake.
   - Fix: capture bearer/userId before wipe; reconfigure `APIClient.shared` inside the Task before unregister. `WidgetPushTokenClient.unregister` returns `.unauthorized` on 401; registrar logs via `AppLog.error`.

### High

_(none open)_

1. ~~**[security]** `SharedDeviceId` never rotates on logout~~ — **ACCEPTED (product)**
   - Decision 2026-08-04: keep install-scoped `device_id` so Watch auto-links to the same account. Rely on authenticated unregister (critical #1 fix). No code change.

### Medium

_(none open from ≥80 confidence reviews)_

### Low / informational

1. **[business-logic]** Intent `markPendingLocal` ordering — **hardened** to `markPendingLocal` → `applySnapshot` → `reloadWidget` on all paths.
2. **[security]** Unregister 401 observability — **fixed** via `UnregisterOutcome.unauthorized` + AppLog.
3. **[performance]** 1 Hz `persistTimerSnapshot` + `reloadTimelines` while any timer is running — by design for overdue-phase progression; network is gated. Acceptable; watch battery if Host+Widget churn becomes measurable.
4. **[architecture]** `registerCachedIfNeeded` / `.pushHandler` remain unwired pending future dual-target — intentional per spec 030 v2.

## Performance (coordinator)

| Focus | Verdict |
|-------|---------|
| 1 Hz reload + network | **OK** — `shouldFetch` pending+TTL short-circuits before HTTP (`TimerWidgetProvider.swift:103-108`). `getSnapshot` App Group only. |
| Single-flight | **OK** — actor coalesces; `inFlight` cleared after await; 8s `TaskGroup` timeout cancels losers. |
| App Group IPC | **OK** — `UserDefaults` suite read/decode; no FileCoordinator. Cheap enough for timeline reloads. |
| `clearPendingLocalMutation` | **Restored** — was missing from `persistTimerSnapshot`; now clears after durable save so the 15s gate does not linger after Manager drain. |
| APNs exclude SQL | **OK** — empty exclude = no filter; single = `<>`; multi = `NOT (device_id = ANY($2::text[]))`. Index on `(user_id)`; UNIQUE `(user_id, device_id)`. Exclude sets are tiny (devices per user). |
| Debounce Set | **OK** — per-user Map entry deleted on flush; Set only holds device ids in the 1s window. |
| Widget vs silent | **OK** — silent skips devices that already have a widget token (`apns-service.ts` silent fan-out). |
| Silent refresh storm | **OK** — one GET + one `reloadTimelines(ofKind:)`; pending gate blocks overwrite during Intent window. |

No critical/high performance findings.

## Fixes landed during this review session

1. Silent path honors `pendingLocal` + `TimerWidgetNetworkRefresh.apply` (`WidgetSilentPushHandler`).
2. Authenticated wipe-path unregister (`AuthService.wipeLocalSession`).
3. `UnregisterOutcome` + 401 logging (`WidgetPushTokenClient` / `WidgetPushRegistrar`).
4. Intent `markPendingLocal` before snapshot write (all paths).
5. Restored `clearPendingLocalMutation` in `TimerManager.persistTimerSnapshot`.
6. `DeepLinkRouter` missing `import RecipeScalerCore` (blocked builds).

## Recommendation

**Approved** — product accepted install-scoped `SharedDeviceId` (Watch same-account linking). Remaining review findings from this pass are closed or fixed.

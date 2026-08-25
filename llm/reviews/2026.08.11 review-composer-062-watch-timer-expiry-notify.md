# Code Review: 062-watch-timer-expiry-notify

**Branch**: master (uncommitted)  
**Reviewers**: Business Logic, Architecture, Standards (parallel `code-reviewer`)  
**Skipped**: Performance (no DB/hot-path); Security as standalone (prefs/local notifications only — folded into BL)

## Summary

Feature shape is sound (Planner in Core + Scheduler actor + Prefs + ViewModel wiring).  
Business logic has **two critical** races/invariants and **two high** gaps that can drop or mis-fire expiry notifications. Architecture/standards add Important items (UIKit import, stale a11y hint, planner folder).

## Findings (sorted by priority)

### Critical

1. **[Business Logic]** Grace window applied as *desired* cancels already-scheduled notifications  
   - Impact: Refresh/reconcile in the last 5s before `endDate` removes a correctly planned pending request → silent miss of background expiry (violates data-model I5 / SC-001).  
   - Recommendation: Split keep (active, future) vs add (active, future + grace). Never remove solely because grace started.

2. **[Business Logic]** `cancel` / `cancelAll` do not invalidate in-flight `reconcile`  
   - Impact: After `await fetchPending`, pause/delete/logout can clear pending; stale reconcile re-`add`s → notification after pause/delete/logout (FR-009).  
   - Recommendation: Bump `reconcileGeneration` inside `cancel`/`cancelAll`; re-check before each `add`.

### High

3. **[Business Logic / Standards]** `refresh()` does not clear pending when state becomes `.empty`  
   - Impact: Remote delete of last timer leaves orphan `watch-timer-*` that still fire.  
   - Recommendation: On `.empty` call `cancelAll()` or `reconcile(timers: [])`.

4. **[Business Logic / Architecture]** `reconcileDiff` compares timer IDs only, ignores `endDate`  
   - Impact: Remote resume / `endDate` drift keeps old trigger → wrong fire time (FR-004). Local pause→resume OK only because pause cancels first.  
   - Recommendation: Diff on `(timerId, fireDate)` vs desired `endDate`; remove+re-add on mismatch.

### Medium / Important (not auto-fixed unless trivial)

5. **[Standards]** `import UIKit` in watch `WatchNotificationDelegate` — unused; drop it.  
6. **[Standards]** `watch.timer.settings.hint` still “Reserved for future features”.  
7. **[Architecture]** Planner under `RecipeScalerCore/Networking/` — wrong folder (pure timer logic). Move later to `Timers/` / `Notifications/`.

## Recommendation

**Changes Requested** — Critical + High fixed in same session (see below). Remaining Important (planner folder) deferred.

## Fixes applied (Critical + High + cheap Standards)

| # | Finding | Fix |
|---|---------|-----|
| 1 | Grace cancels pending | `keepEndDates` (no grace) vs `addEndDates` (grace); reconcile keeps pending inside grace |
| 2 | cancel vs reconcile race | `reconcileGeneration &+= 1` in `cancel` / `cancelAll` |
| 3 | `.empty` orphans | `refresh()` → `.empty` calls `cancelAll()` |
| 4 | endDate drift ignored | `PendingEntry.fireDate` + remove+re-add when \|fire−desired\| > 1s |
| 5 | UIKit import | removed from `WatchNotificationDelegate` |
| 6 | Stale settings hint | en/ru → “Open settings” / «Открыть настройки» |

Verify: `bash scripts/verify-watch-timer-expiry-notify.sh` → exit 0.

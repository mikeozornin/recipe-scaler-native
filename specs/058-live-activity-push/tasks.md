# Tasks: Live Activity Push Updates

**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

> Native client checklist. Server twin lives in `recipe-scaler-web/specs/058-live-activity-push`.

---

## Шаг 3 — iOS: Activity push token lifecycle

- [X] T001. `Activity.request(..., pushType: .token)` in `TimerLiveActivityCoordinator`.
- [X] T002. Observe `pushTokenUpdates`; POST via `LiveActivityPushRegistrar`.
- [X] T003. Unregister (DELETE) on `end` / `endAll` / activity dismissed.
- [X] T004. Wire registrar in `AppContainer`; no `.shared` on registrar.
- [X] T005. Entitlements: `aps-environment` production / development.
- [X] T006. Legacy migration: recreate pre-058 activities that never emit tokens.
- [X] T007. Unit tests: registrar POST/DELETE/dedup/rotation; coordinator unregister.

## Шаг 3b — APNs ownership vs local update races (review high+)

- [X] T008. `LiveActivitySyncPolicy` — background `.running` skip only for progress/reconcile; `.userAction` always updates (Lock Screen resume).
- [X] T009. Foreground gate: `beginForegroundRemoteRefresh` + `loadActiveTimersFromServer(force:)` + `endForegroundRemoteRefresh` before progress ticks.
- [X] T010. `clearForLogout()` = `endAll` + `clearAllCachedTokens`; call from `stopForLogout` and `wipeLocalSession`.
- [X] T011. Unit tests for skip policy, progress gate, `clearForLogout`, POST body fields.

## Шаг 1–2 / 5 — Server (web repo)

- [ ] T012. DB `liveactivity_tokens` + POST/DELETE routes.
- [ ] T013. APNs liveactivity send + TimerSync fan-out (exclude source device).
- [ ] T014. Account deletion wipe of `liveactivity_tokens`.

## Шаг 4 — Device QA

- [ ] T015. Create `quickstart.md` and run SC-001…SC-006 (iPhone + Watch / web pause).

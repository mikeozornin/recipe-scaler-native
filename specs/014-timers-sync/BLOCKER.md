# 014 Timers sync — blocker (2026-06-02)

## Status

**Blocked** for full cross-device + APNs parity in this slice.

## What ships

- `MobileTimerPanel` — Phase 1 **local** `TimerManager` timers above tab bar (read-only display).
- Local notifications unchanged from Phase 1.

## What is missing

| Requirement | Blocker |
|-------------|---------|
| FR-TMR-002 Socket timer events | Native client has no `timer_event` / `POST /api/v1/timers/sync` integration; `TimerManager` uses SwiftData locally only. |
| US2 Cross-device ≤3s | Requires server timer entity sync + web `TimerPanel` contract wired on iOS. |
| US3 APNs for timers >30 min | No iOS device token registration endpoint wired in app; PRD push rules assume web push + optional APNs endpoint TBD. |

## Unblock path

1. Add `TimerSyncService` consuming `POST /api/v1/timers/sync` and socket broadcasts per `llm/API.md` § Timer Sync API.
2. Register APNs token on auth (endpoint from `docs/PRD.md` when confirmed).
3. Map description timer nodes → synced timer ids (depends on **006** description editor read path).

## Verifier

`scripts/verify-timers-sync.sh` — static check for `MobileTimerPanel` + BLOCKER doc; no cross-device screenshot until unblocked.
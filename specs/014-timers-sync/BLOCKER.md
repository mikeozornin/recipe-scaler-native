# 014 Timers sync — статус (2026-06-04)

## Status

**Фаза «таймеры» (без push)** — реализована в коде; спек **не закрыт** до ручной кросс-девайс проверки.

**Push по таймерам** — **не** в этой фазе; отдельная фича «пуши».

## What ships (код)

- `TimerSyncService` — `GET /api/v1/timers/active`, `POST /api/v1/timers/sync`, Socket.IO `timer_event`, persisted pending queue.
- `TimerManager` + SwiftData; `configure(modelContext:)`; события create/start/pause/resume/delete → sync.
- `MobileTimerPanel` — над tab bar (`AppShellView.safeAreaInset`); collapse, pause/resume, delete, overdue UI.
- Старт из описания — tap timer node → `DescriptionTimerStartPopover` → `TimerManager.createAndStartTimer` (`YDocRecipeDetailView`).
- Локальное UN при completion (Phase 1) — не server push.
- Verifier: `scripts/verify-timers-sync.sh` (static + simulator screenshot).

## What is missing (закрытие спека)

| Requirement | Gap |
|-------------|-----|
| SC-001 Start iOS → web panel ≤3 с | Нет зафиксированного прогона iOS + web на одном `userId` |
| SC-002 Pause/resume/delete parity vs web | Код на iOS есть; side-by-side с mobile web не задокументирован |

## Out of scope here → фаза «пуши»

| Requirement | Where |
|-------------|--------|
| US3 APNs / server push for timers >30 min | Push feature |
| `POST /api/push/schedule` / `cancel` for timers | Push feature |
| Web Push parity on iOS | Push feature |

## Unblock path (закрытие 014)

1. Ручной quickstart: старт таймера на iOS → виден на веб `TimerPanel` ≤3 с (Wi‑Fi).
2. Pause/resume/delete на iOS → то же состояние на веб ≤3 с.
3. Обновить таблицу аудита в `spec.md` → статус ✅; архивировать этот файл или оставить только ссылку на quickstart.

## История

- 2026-06-02: blocker — только локальная панель.
- 2026-06-04: `TimerSyncService`, panel controls, description tap (Grok sessions `019e91fd`, `019e926f`).
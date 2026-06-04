# Спецификация: синхронизация таймеров

**Ветка**: `014-timers-sync`  
**Дата**: 2026-06-02  
**Статус**: ✅ Done (2026-06-04) — sync, панель, описание, pause/resume/delete. Push → [023-push-notifications](../023-push-notifications/spec.md)
**Зависимости**: `006` (timer nodes в описании), Phase 1 `TimerManager`  
**Этален**: PRD § Timers, `llm/ARCHITECTURE.md`, mobile `TimerPanel`  
**Не в этом спеке**: push-уведомления (APNs, `/api/push/schedule`) — **[023-push-notifications](../023-push-notifications/spec.md)**

## Аудит реализации (2026-06-04) — закрыто

| Требование | Статус |
|------------|--------|
| FR-TMR-001…003 | ✅ |
| US1 start from description | ✅ |
| US2 cross-device | ✅ (код + `TimerSyncService`; продуктовый sign-off) |
| US3 background push | ➡️ [023-push-notifications](../023-push-notifications/spec.md) |
| US4 pause/resume parity | ✅ |

Код: `TimerSyncService`, `MobileTimerPanel`, `DescriptionTimerStartPopover`, `scripts/verify-timers-sync.sh`, `screenshots/timers-panel-20260604-*.png`.

## Контекст

Phase 1: **локальные** таймеры + локальное UN при completion (не server push).

Веб: таймеры в описании sync между устройствами. Server/Web Push для длинных таймеров — **контракт пушей**, реализуется в фазе «пуши» на iOS (другие правила/транспорт, чем веб).

## Цель

Кросс-девайс **состояние** активных таймеров (Socket + HTTP sync) и паритет mobile `TimerPanel` + старт из описания (read-only tap).

## Пользовательские сценарии

### US1 — Start from description (P1)

**Когда** tap timer node (read или edit view), **тогда** создаётся synced timer entity (формат — из ARCHITECTURE) + локальный countdown.

### US2 — Cross-device (P2)

**Когда** таймер запущен на iOS, **тогда** веб `TimerPanel` показывает его ≤ 3 с (Wi‑Fi).

### US4 — Pause / resume (P2)

Паритет pause/resume с веб `TimerPanel` — ✅.

> **US3 (push в фоне)** перенесён в [023-push-notifications](../023-push-notifications/spec.md).

## Требования

### FR-TMR-001

Не ломать существующие локальные таймеры Phase 1; миграция state optional.

### FR-TMR-002

Socket events для timer — из ARCHITECTURE (добавить в `contracts/timers-sync.md` при research).

### FR-TMR-003

Mobile panel: компактный список активных таймеров над tab bar (как `TimerPanel variant="mobile"`).

## Вне scope

- **Push о таймерах** — [023-push-notifications](../023-push-notifications/spec.md)
- Редактирование timer-нод в описании (rename/unlink) — до 018 / edit mode
- Изобретение новых server push rules
- Apple Watch

## Критерии успеха

- **SC-001**: Start iOS → visible web timer panel (sync ≤3 с).
- **SC-002**: Pause/resume/delete и overdue UI как на веб mobile panel.
- **SC-push** — см. [023-push-notifications](../023-push-notifications/spec.md)

## Артефакты

- `BLOCKER.md` — архив: фича закрыта 2026-06-04
- Push-контракт таймеров: `../023-push-notifications/contracts/timer-push-schedule.md`
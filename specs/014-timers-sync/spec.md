# Спецификация: синхронизация таймеров

**Ветка**: `014-timers-sync`  
**Дата**: 2026-06-02  
**Статус**: 🟡 Реализовано в коде (аудит 2026-06-04) — sync + панель + старт из описания + pause/resume/delete. Остаётся ручная кросс-девайс проверка SC-001/SC-002; push — фича «пуши». См. [BLOCKER.md](./BLOCKER.md)
**Зависимости**: `006` (timer nodes в описании), Phase 1 `TimerManager`  
**Этален**: PRD § Timers, `llm/ARCHITECTURE.md`, mobile `TimerPanel`  
**Не в этом спеке**: push-уведомления о таймерах (APNs, server schedule) — **отдельная фича «пуши»**, не фаза «таймеры».

## Аудит реализации (2026-06-04)

Отгружено в коде (сессии Grok 2026-06-04: timer sync, mobile panel, description tap):

- `TimerSyncService` — `GET /api/v1/timers/active`, `POST /api/v1/timers/sync`, очередь событий, Socket.IO `timer_event` через `YjsSyncService`
- `TimerManager` ↔ sync: create/start/pause/resume/delete эмитят события на сервер
- `MobileTimerPanel` — collapse/expand, pause/resume, delete, overdue/progress (паритет mobile web)
- Старт из описания — tap timer-ноды → `DescriptionTimerStartPopover` → `createAndStartTimer` (`YDocRecipeDetailView`, `RecipeDescriptionInlineTextView`)
- Скриншоты симулятора: `screenshots/timers-panel-20260604-*.png`
- `scripts/verify-timers-sync.sh` — статические проверки + screenshot панели

| Требование | Статус |
|------------|--------|
| FR-TMR-003 mobile panel | ✅ |
| US1 start from description | ✅ (read-only tap + popover; rename/unlink — 018) |
| US2 cross-device ≤3 с | 🟡 код есть; **ручная** проверка iOS ↔ web не зафиксирована |
| US3 APNs >30 min | ➡️ фича «пуши», не 014 |
| US4 pause/resume parity | ✅ в `MobileTimerPanel` / `TimerManager` |

Остаток — ручной SC-001/SC-002 в `BLOCKER.md`. Push — фича «пуши».

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

### US3 — Background / push (P2) — **фича «пуши»**

Перенесено из scope 014. **Когда** app в фоне и нужны напоминания о таймере, **тогда** push-фича (APNs и т.д.) — не блокирует закрытие «таймеров».

### US4 — Pause / resume (P2)

Паритет pause/resume с веб `TimerPanel`. Правила push при resume (≤120s без reminder) — в фиче «пуши».

## Требования

### FR-TMR-001

Не ломать существующие локальные таймеры Phase 1; миграция state optional.

### FR-TMR-002

Socket events для timer — из ARCHITECTURE (добавить в `contracts/timers-sync.md` при research).

### FR-TMR-003

Mobile panel: компактный список активных таймеров над tab bar (как `TimerPanel variant="mobile"`).

## Вне scope

- **Все push о таймерах** (APNs, `/api/push/schedule`, reminder, Web Push parity) — фаза «пуши»
- Редактирование timer-нод в описании (rename/unlink) — до 018 / edit mode
- Изобретение новых server push rules
- Apple Watch

## Критерии успеха

- **SC-001**: Start iOS → visible web timer panel (sync ≤3 с).
- **SC-002**: Pause/resume/delete и overdue UI как на веб mobile panel.
- **SC-push** (отдельная фича): completion/reminder в фоне через push-стек.

## Артефакты

- `contracts/timers-sync.md`
- `research.md` — APNs endpoint, payload
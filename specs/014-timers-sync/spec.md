# Спецификация: синхронизация таймеров и push

**Ветка**: `014-timers-sync`  
**Дата**: 2026-06-02  
**Статус**: Draft  
**Зависимости**: `006` (timer nodes в описании), Phase 1 `TimerManager`  
**Этален**: PRD § Timers, `llm/ARCHITECTURE.md`, mobile `TimerPanel`

## Контекст

Phase 1: **локальные** таймеры + local notifications.

Веб: таймеры в описании sync между устройствами; server push для длинных таймеров (>30 min: reminder 2 min before + completion; `resume_timer` rules).

## Цель

Кросс-девайс состояние активных таймеров + APNs там, где веб использует Web Push (без изменения server contract — клиент регистрирует token).

## Пользовательские сценарии

### US1 — Start from description (P1)

**Когда** tap timer node (read или edit view), **тогда** создаётся synced timer entity (формат — из ARCHITECTURE) + локальный countdown.

### US2 — Cross-device (P2)

**Когда** таймер запущен на iOS, **тогда** веб `TimerPanel` показывает его ≤ 3 с (Wi‑Fi).

### US3 — Background / push (P2)

**Когда** app в фоне и timer > 30 min, **тогда** APNs по правилам PRD (если сервер поддерживает iOS token — endpoint TBD в `docs/PRD.md`).

### US4 — Pause / resume (P2)

Паритет `resume_timer` без reminder если ≤120s left.

## Требования

### FR-TMR-001

Не ломать существующие локальные таймеры Phase 1; миграция state optional.

### FR-TMR-002

Socket events для timer — из ARCHITECTURE (добавить в `contracts/timers-sync.md` при research).

### FR-TMR-003

Mobile panel: компактный список активных таймеров над tab bar (как `TimerPanel variant="mobile"`).

## Вне scope

- Изобретение новых server push rules
- Apple Watch

## Критерии успеха

- **SC-001**: Start iOS → visible web timer panel.
- **SC-002**: Complete в фоне → local notification (минимум); APNs если token зарегистрирован.

## Артефакты

- `contracts/timers-sync.md`
- `research.md` — APNs endpoint, payload
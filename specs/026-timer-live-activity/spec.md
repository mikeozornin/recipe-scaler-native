# Спецификация: Live Activity для кулинарных таймеров

**Ветка**: `026-timer-live-activity`  
**Дата**: 2026-06-12  
**Статус**: 🟡 В работе (~90% кода, аудит 2026-06-15) — device QA pause/resume pending  
**Зависимости**: [014-timers-sync](../014-timers-sync/spec.md) (DONE)

## Цель

Показывать активный таймер на Lock Screen через ActivityKit: обратный отсчёт, название шага, контекст рецепта, pause/resume с карточки.

## Решения v1

- **Одна Live Activity на каждый активный таймер** (осознанное отклонение от HIG «одна activity с ротацией»).
- **Только Lock Screen UI**; Dynamic Island — минимальный системный stub (требование платформы).
- **Системные цвета**: `Color.primary` / `.orange` / `.red` — без hex из Figma.
- **Системный фон** activity — без кастомного `#1a1a1a`.
- **Progress bar** edge-to-edge (8 pt overlay), контент с margin **14 pt**.
- Countdown через `Text(timerInterval:countsDown:)` — без push.

## Состояния UI

| Состояние | Accent | Кнопка | Progress | Условие |
|-----------|--------|--------|----------|---------|
| normal | `.primary` | pause | partial, `.primary` | running/paused, remaining ≥ 10% duration |
| soon | `.orange` | pause/play, `.primary` | partial, `.orange` | remaining < duration/10 |
| exceeded | `.red` | скрыта | full, `.red` | remaining < 0 |

Нижний ряд (превью + название рецепта): `.primary`, скрыт без `recipeId`.

## Lifecycle

- `start` / `resume` / `createAndStart` → `Activity.request`
- `pause` → update `ContentState.phase = .paused`
- zero reached → `phase = .exceeded`; dismiss через ~30 мин
- `delete` / `reset` → `Activity.end` immediate
- cold start → reconcile `Activity.activities` с `TimerManager.timers`

## Интерактивность

- Pause/resume: `LiveActivityIntent` → App Group queue → `TimerManager`
- Tap по карточке: `recipe-scaler://recipe/{recipeId}` (если есть recipe)

## Вне scope v1

- Push-обновления activity (spec 023)
- Toggle в Account
- Кастомный Dynamic Island expanded
- CarPlay / watchOS layouts

## Критерии успеха

- Running-таймер → Live Activity на Lock Screen с живым countdown
- Pause/resume с карточки синхронизирует `TimerManager`
- Delete убирает карточку
- Сборка `RecipeScalerNative` + extension без ошибок

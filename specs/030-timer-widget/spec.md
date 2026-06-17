# Спецификация: Home Widget — TimerWidget

**Ветка**: `030-timer-widget`
**Дата**: 2026-06-17
**Статус**: 🟡 В работе
**Зависимости**: [014-timers-sync](../014-timers-sync/spec.md) (DONE), [026-timer-live-activity](../026-timer-live-activity/spec.md) (in progress — переиспользуем `TimerLiveActivityAccent` и `TimerLiveActivityPalette`)

## Цель

Показывать активные таймеры на Home Screen и Lock Screen через **WidgetKit** (`StaticConfiguration`), с живым отсчётом через `Text(timerInterval:)` — без push, без сервера. На Home Screen — grid 2×2 до 4 таймеров; на Lock Screen / StandBy — accessory families (circular / rectangular / inline).

## Источники макетов

Figma `rVzFwMDS5SECfIq4HRLHya`:
- `107:207` — Timer light (Home Screen `systemSmall`)
- `107:266` — Timer dark (те же переменные)
- `107:332` — Timer monochrome (Lock Screen / StandBy accessory)

## Решения v1

- **Только TimerWidget** в этой итерации. ShoppingListWidget — отдельная итерация (spec 031 или продолжение).
- **Read-only**: `StaticConfiguration`, без интерактива. Тап → deep link в app.
- **Все плейсменты**: `systemSmall` (169×169) + `accessoryCircular` + `accessoryRectangular` + `accessoryInline`.
- **Живой отсчёт** через `Text(timerInterval:)` — система сама обновляет без rebuild.
- **Унифицированный цвет** для всех элементов таймера (кольцо/прогресс/цифры/название) в зависимости от состояния.
- **Semantic colors**: `secondarySystemBackground` для фона, `.label` для текста; accessory — `.label` + `.widgetAccentable()`.
- **Шрифты проекта** (без добавления новых): Martian Mono Lt (`AppFonts.mono`), Martian Grotesk Lt (`AppFonts.sans`).
- **Новый target** `HomeWidgetExtension` (не сливать с `TimerLiveActivityExtension`).

## Унифицированный цвет (правило дизайнера)

| Состояние | Цвет всех элементов | Условие |
|-----------|---------------------|---------|
| `normal` | `labels/primary` (semantic `.label`) | remaining ≥ 10% duration |
| `soon` | `accents/orange` → системная `.orange` | remaining < duration/10 |
| `exceeded` | `accents/red` → `Color(red: 0.98, green: 0.153, blue: 0.188)` | remaining < 0 |

**Исключения** (всегда монохром `labels/primary`):
- Empty state «Таймеров нет»
- Accessory families (Lock Screen / StandBy) — без цветных акцентов (vibrancy бы их сломал)

## Семейства виджетов

| Family | Размер | Layout |
|--------|--------|--------|
| `systemSmall` | 169×169 | Grid 2×2, состояния 0/1/2/3/4 |
| `accessoryCircular` | ~52×52 | Ring + одна цифра (минуты) |
| `accessoryRectangular` | ~160×72 | Name + `Text(timerInterval:)` |
| `accessoryInline` | 1 строка | `Text(timerInterval:) — name` |

## Состояния `systemSmall`

| Таймеров | Layout |
|----------|--------|
| 0 | Empty: «Таймеров нет» центрировано |
| 1 | 1 кольцо (62pt) + 2 строки с названием рецепта |
| 2 | 2 row: прогресс-бар (linear) + имя + время справа |
| 3 | Grid 2×2, занято 3 ячейки, 4-я пустая |
| 4 | Grid 2×2, занято 4 ячейки |

> Больше 4 активных таймеров → топ-4 по приоритету (ближайший к концу → превышенный → остальные).

## Deep links

- `recipe-scaler://home` (TimerWidget) → открывает main app на дефолтной вкладке `.recipes` (вкладки `/timers` нет).
- `recipe-scaler://shopping` (для будущего ShoppingListWidget).

## Timeline policy

- **Backgrounding** app → `WidgetCenter.shared.reloadAllTimelines()`.
- **Мутация таймера** в `TimerManager` → reload kind `TimerWidget` с debounce 200мс.
- **Fallback** в Provider: `.atEnd(after: now + 15min)`.

## Вне scope v1

- Интерактивные виджеты (toggle pause из виджета) — следующий spec.
- Recipe/pinned-recipes widget — отдельный spec.
- ShoppingListWidget — отдельная итерация.
- Push-обновления виджета (APNs) — после платного аккаунта.
- Платный аккаунт / TestFlight / App Store — отдельно.

## Критерии успеха

- Запущенный таймер → виджет на Home Screen с живым countdown.
- Empty state когда нет активных таймеров.
- Pause/delete из app → виджет обновляется.
- Сборка `RecipeScalerNative` + `HomeWidgetExtension` без ошибок на симуляторе.
- Все три accessory families рендерятся корректно (Lock Screen + StandBy).
- Dark/light режимы адаптивны.

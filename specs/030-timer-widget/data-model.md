# Контракт данных: TimerWidget

**Spec**: [030-timer-widget](./spec.md)
**Дата**: 2026-06-17

## Обзор

Виджет читает данные из App Group `UserDefaults` через новый `TimerSnapshotStore`. Источник правды — SwiftData (`RecipeTimer`) внутри main app; main app зеркалирует упрощённый snapshot в App Group при каждой мутации таймера.

## Хранилище

| Параметр | Значение |
|---|---|
| App Group | `group.ru.recipescaler.RecipeScaler` |
| UserDefaults key | `widgets.timerSnapshot` |
| Формат | JSON (Codable) |
| Обновляется | main app в `TimerManager.persist/mutate` |
| Читается | `HomeWidgetExtension` в `TimerWidgetProvider.getTimeline` |

## Типы

### `TimerSnapshot`

```swift
struct TimerSnapshot: Codable, Hashable, Sendable {
    let id: String
    let name: String
    let recipeId: String?
    let recipeName: String?
    /// End date for running timer (used by `Text(timerInterval:)` live countdown).
    /// Nil when paused (use `pausedRemainingSeconds`).
    let endDate: Date?
    /// Remaining seconds captured at pause moment.
    let pausedRemainingSeconds: Int?
    let phase: TimerSnapshotPhase
    /// Original full duration in seconds. Used for accent (`soon` < 10%) and progress fraction.
    let totalDurationSeconds: TimeInterval
}

enum TimerSnapshotPhase: String, Codable, Hashable, Sendable {
    case running
    case paused
    case exceeded
}
```

### `TimerSnapshotDocument`

Контейнер верхнего уровня, сериализуемый в App Group:

```swift
struct TimerSnapshotDocument: Codable, Hashable, Sendable {
    let timers: [TimerSnapshot]
    let generatedAt: Date

    static let empty = TimerSnapshotDocument(timers: [], generatedAt: .distantPast)
}
```

## Mapping SwiftData → Snapshot

`TimerSnapshot` строится из `RecipeTimer` (см. `RecipeScalerNative/Models/RecipeTimer.swift`):

| `RecipeTimer` поле | → `TimerSnapshot` поле | Правила |
|---|---|---|
| `id` | `id` | как есть |
| `name` | `name` | как есть (уже trimmed в `RecipeTimer.init`) |
| `recipeId` | `recipeId` | как есть (nil если без recipe) |
| `recipeDisplayName` | `recipeName` | как есть |
| `endTime` | `endDate` | только если `isRunning == true` и `!hasCompleted` |
| `remainingTime` | `pausedRemainingSeconds` | только если `isPaused == true`, как `Int` |
| (computed) | `phase` | `.running` если `isRunning`; `.paused` если `isPaused`; `.exceeded` если `hasCompleted` или `remainingSeconds < 0` |
| `duration` | `totalDurationSeconds` | как есть |

### Фильтрация

В snapshot попадают **только** таймеры, где `!hasCompleted` И (`isRunning` ИЛИ `isPaused`). Завершённые/остановленные — исключаются (виджет их не показывает).

### Сортировка

Топ-4 по тому же правилу, что `TimerUtils.sortTimers` (`RecipeScalerNative/Utils/TimerUtils.swift:43-48`): running-first, потом по возрастанию remaining. В snapshot-документ попадает максимум 4 элемента — больше виджет всё равно не покажет.

## `WidgetTimerAccent`

Виджет-специфичный accent enum (не зависит от `TimerLiveActivityAccent`, чтобы не тащить UIKit-зависимости в snapshot-стор):

```swift
enum WidgetTimerAccent {
    case normal
    case soon
    case exceeded

    /// Цвет, применяемый ко всем элементам таймера (ring/progress/time/recipe text).
    var color: Color {
        switch self {
        case .normal:   return Color(.label)
        case .soon:     return Color(.orange)
        case .exceeded: return Color(red: 0.98, green: 0.153, blue: 0.188)
        }
    }

    static func resolve(
        phase: TimerSnapshotPhase,
        remainingSeconds: Int,
        totalDuration: TimeInterval
    ) -> Self {
        switch phase {
        case .exceeded: return .exceeded
        case .paused, .running:
            if remainingSeconds < 0 { return .exceeded }
            if totalDuration > 0, remainingSeconds < Int(totalDuration) / 10 { return .soon }
            return .normal
        }
    }
}
```

Логика идентична `TimerLiveActivityAccent.resolve` (`RecipeScalerNative/LiveActivity/TimerLiveActivityAccent.swift:21-25`), чтобы сохранялся визуальный паритет между Live Activity и виджетом.

## `remainingSeconds` derivation в виджете

Виджет не хранит current time; вычисляет `remainingSeconds` на лету в Provider'е:

```swift
func remainingSeconds(now: Date) -> Int {
    switch phase {
    case .running:
        guard let endDate else { return Int(totalDurationSeconds) }
        return Int(endDate.timeIntervalSince(now).rounded())
    case .paused:
        return pausedRemainingSeconds ?? 0
    case .exceeded:
        guard let endDate else { return 0 }
        return Int(endDate.timeIntervalSince(now).rounded()) // отрицательное
    }
}
```

## Empty state

`TimerSnapshotDocument.empty` (пустой массив `timers`) → виджет показывает localized «Таймеров нет».

## Локализация

Новые ключи в `RecipeScalerNative/Resources/Localizable.xcstrings` (target membership: main app + HomeWidgetExtension):

| Key | ru | en |
|---|---|---|
| `widgets.timer.empty` | Таймеров нет | No active timers |
| `widgets.timer.name` | Recipe Scaler | Recipe Scaler |
| `widgets.timer.description` | Активные таймеры | Active cooking timers |

## Совместимость / версия

- **Версия снапшота**: v1 (без отдельного поля version — JSON shape сам себя версифицирует). При будущих изменениях добавить `version: Int` в `TimerSnapshotDocument`.
- **Backward compat**: при неудачном decode возвращаем `.empty` (как `ShoppingListSnapshotStore.load()`, см. `RecipeScalerNative/AppIntents/ShoppingListSnapshotStore.swift:23-28`).

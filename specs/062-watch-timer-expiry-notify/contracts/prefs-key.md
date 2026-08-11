# Contract: Prefs Key

**Спека**: [spec.md](./spec.md) | **План**: [plan.md](./plan.md)

## Key

```text
watchExpiryNotificationsEnabled
```

## Storage

- `UserDefaults.standard` (watch-local, **не** App Group).
- Не синхронизируется через iCloud (`NSUbiquitousKeyValueStore` не используется).
- Не шарится с iPhone — это watch-only UI-настройка.

## Type

`Bool`.

## Default

`true` (фича работает «из коробки» для новых пользователей и после первого запуска после install).

Default регистрируется через `UserDefaults.standard.register(defaults: ["watchExpiryNotificationsEnabled": true])` в `RecipeScalerNativeWatchApp.init()`.

## Owner

`WatchExpiryNotificationsPrefs` — единственный тип, который читает/пишет этот ключ. Никакой другой код не обращается к `UserDefaults` по этой строке.

## Migration

Нет предыдущей версии ключа. При первом запуске после update — `register(defaults:)` обеспечивает `true`, даже если ключа не было.

## Notification

`WatchExpiryNotificationsPrefs.didChangeNotification` (`Notification.Name`) постится синхронно при `setEnabled(_:)`. `userInfo = ["isEnabled": value]`. Подписчик — `TimerListViewModel` (вызовет `cancelAll` если OFF).

## Test accessors

В unit-тестах `WatchExpiryNotificationsPrefs` мокается через injection в scheduler (см. `WatchExpiryNotificationSchedulerTests`). Direct UserDefaults access только через `WatchExpiryNotificationsPrefs`, никаких raw-чтений в app коде.

# Contract: Notification Identifiers

**Спека**: [spec.md](./spec.md) | **План**: [plan.md](./plan.md)

## Identifier format

```
watch-timer-<timerId>-complete
```

- `watch-timer-` — fixed prefix (буквальный литерал, см. `WatchExpiryNotificationScheduler.identifierPrefix`).
- `<timerId>` — `WatchTimer.id` (uuid string, как приходит с сервера в `ServerActiveTimer.timerId`).
- `-complete` — fixed suffix.

## Owner

`WatchExpiryNotificationScheduler` — **единственный** writer этого identifier-пространства в `UNUserNotificationCenter`.

## Collision policy

iPhone `TimerManager` планирует notifications с identifier `<timerId>-complete` (без `watch-` prefix). Это разные namespace, конфликт исключён на строковом уровне.

## Parsers

- `identifier(for timerId: String) -> String` — собирает identifier из timerId.
- `timerId(from identifier: String) -> String?` — reverse-парсинг; возвращает `nil` если prefix/suffix не совпадают. Используется при обработке delivered notifications и в unit-тестах.

## Lifecycle

| Событие | Что происходит с identifier |
|---------|----------------------------|
| Timer появился в `loaded` состоянии | `reconcile` планирует request с этим identifier (если endDate > now + grace) |
| Timer paused (optimisticToggle) | `cancel(timerId:)` → `removePendingNotificationRequests(withIdentifiers:)` |
| Timer deleted (optimisticRemove) | `cancel(timerId:)` |
| Logout / userId = nil | `cancelAll()` → remove all `watch-timer-*` |
| Prefs toggle OFF | `cancelAll()` + блокировка будущих `reconcile` |
| Серверный push `timer_completed` (P2, future) | Push-handler вызовет `cancel(timerId:)` |
| App cold launch с orphan pending (timerId больше не активен) | Первый `reconcile` удалит orphan через diff |

## Regex (для verify-скриптов)

```
^watch-timer-.+-complete$
```

## Test fixture

В unit-тестах используются литералы:

- `timerId = "test-timer-1"` → identifier = `"watch-timer-test-timer-1-complete"`
- `timerId = "abc"` → identifier = `"watch-timer-abc-complete"`
- malformed: `"foo"`, `"watch-timer-no-suffix"`, `"random-id"` → парсер вернёт `nil`.

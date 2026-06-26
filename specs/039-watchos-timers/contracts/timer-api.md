# Контракт: watchOS Timer API

HTTP-контракт между watchOS app и `recipe-scaler.ru`. Полностью parity с `TimerSyncService.swift` (main app, см. `/Users/mike/work/git-repos/projects/recipe-scaler/recipe-scaler-native/RecipeScalerNative/Services/TimerSyncService.swift`).

## Аутентификация

Все запросы идут с header'ом:

```
x-user-id: <userId>
```

`userId` приходит с iPhone через `WatchConnectivity.transferUserInfo` и хранится в watch-local Keychain (`WatchCredentialsStore`).

## GET /api/v1/timers/active

Получить список активных таймеров пользователя.

### Response

```json
{
  "success": true,
  "data": {
    "timers": [
      {
        "timerId": "timer_1719406800000_abc123def",
        "name": "до золотой корочки",
        "duration": 2700,
        "endTime": 1719409500000,
        "isPaused": false,
        "pausedDuration": null,
        "createdAt": 1719406800000,
        "lastUpdated": 1719406800000,
        "startedAt": 1719406800000,
        "pausedAt": null,
        "recipeId": "recipe-uuid"
      }
    ]
  }
}
```

### Типы

- `endTime: Int64?` — Unix epoch ms, `null` если paused.
- `pausedDuration: Int?` — **на сервере**: накопленное время на паузе (секунды), не remaining. Remaining на клиенте: `endTime - (pausedAt ?? lastUpdated)` пока `isPaused`.
- `duration: Int` — total duration seconds.
- `lastUpdated: Int64` — Unix epoch ms, для LWW conflict resolution.

### Декодер

`ServerActiveTimer` (после Core refactor — `RecipeScalerCore/Networking/ServerActiveTimer.swift`):

```swift
public struct ServerActiveTimer: Decodable, Sendable {
    public let timerId: String
    public let name: String
    public let duration: Int
    public let endTime: Int64?
    public let isPaused: Bool
    public let pausedDuration: Int?
    public let createdAt: Int64
    public let lastUpdated: Int64
    public let startedAt: Int64?
    public let pausedAt: Int64?
    public let recipeId: String?
}
```

### Edge cases

| Состояние | Признаки |
|---|---|
| Running | `isPaused == false && endTime != nil` |
| Paused | `isPaused == true`; remaining = `endTime - (pausedAt ?? lastUpdated)` (сек); `pausedDuration` — не remaining |
| Exceeded | вычисляется на клиенте: running && `endTime < now` |

## POST /api/v1/timers/sync

Отправить пакет событий с часов. Body parity с `TimerSyncService.sendSyncRequest`.

### Request body

```json
{
  "deviceId": "watch-uuid",
  "events": [
    {
      "timestamp": 1719406800000,
      "type": "timer_paused",
      "timerId": "timer_xxx",
      "data": {
        "type": "timer_paused",
        "timerId": "timer_xxx",
        "remaining": 1234
      }
    }
  ],
  "lastSyncTimestamp": 1719406700000
}
```

### Event types (только для watch v1)

| Type | Payload | Когда |
|------|---------|-------|
| `timer_paused` | `{type, timerId, remaining: Int}` (seconds) | swipe pause на часах |
| `timer_resumed` | `{type, timerId}` | swipe resume на часах |
| `timer_deleted` | `{type, timerId}` | swipe delete на часах |

**Критично**: поле называется `data`, не `payload` (parity с `TimerSyncService.syncPendingEvents` и Zod-схемой сервера). `timer_paused` должен включать `remaining` — iPhone читает `data.remaining` из WebSocket. Remaining = текущее `endTime - now` на момент pause.

### Response

```json
{
  "success": true,
  "data": {
    "syncedEvents": ["evt_<uuid>"]
  }
}
```

### Optimistic UI strategy

1. Watch меняет локальное состояние мгновенно (optimistic).
2. POST `/sync` в фоне.
3. При ошибке (network/4xx/5xx) — revert + показываем inline error (в v1 — `ErrorStateView`).
4. После успешного POST (или через 500ms в фоне) — `refresh()` через `GET /active` для консистентности с сервером и iPhone.

### Device ID

```swift
// На watch — отдельный UUID, не коллидирует с iPhone.
// Хранится в UserDefaults.standard (на watch это watch-local).
static func storedDeviceId() -> String {
    if let existing = UserDefaults.standard.string(forKey: "deviceId"), !existing.isEmpty {
        return existing
    }
    let newId = UUID().uuidString
    UserDefaults.standard.set(newId, forKey: "deviceId")
    return newId
}
```

## Offline behavior

- При отсутствии сети watch не блокирует UI — optimistic mutation остаётся локальной.
- В v1 **нет** persistent event queue на часах (как в main app). Если пользователь закрыл app до успешного POST — событие теряется, но сервер уже мог получить partial.
- Это **задокументированный trade-off** v1. Persistent queue — follow-up.

## Out of scope

- `timer_created` с часов (нет UI создания).
- `timer_started` с часов (часы только pause/resume/delete).
- WebSocket подписка на часах (refresh polling в v1).
- `/api/push/apns-register` с `platform=watch` — не делаем в v1.

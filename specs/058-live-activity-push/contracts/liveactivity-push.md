# Контракт: Live Activity APNs push

**Спека**: [../spec.md](../spec.md)
**Платформы**: iOS ActivityKit ↔ APNs ↔ `recipe-scaler-web` server
**Дата**: 2026-08-03

Зеркало: `recipe-scaler-web/specs/058-live-activity-push/contracts/liveactivity-push.md`
(содержимое должно совпадать).

## HTTP: регистрация token

### POST `/api/push/apns-register-liveactivity`

```json
{
  "timer_id": "timer_<uuid>",
  "token": "<hex activity push token>",
  "device_id": "<same as TimerSyncService deviceId>"
}
```

Auth: как `/api/push/apns-register` (`requireUserId`).

Response: `{ "success": true }`

### DELETE `/api/push/apns-register-liveactivity?timer_id=…&device_id=…`

Response: `{ "success": true }` (idempotent)

## APNs: update / end

### Headers

| Header | Value |
|--------|-------|
| `apns-push-type` | `liveactivity` |
| `apns-topic` | `ru.recipescaler.RecipeScaler.push-type.liveactivity` |
| `apns-priority` | `10` (immediate) или `5` |
| `authorization` | `bearer <JWT>` |

Topic = **main app Bundle ID** + `.push-type.liveactivity`. **Без** имени
`RecipeTimerActivityAttributes` в topic (WWDC23 / Apple Docs).

### Payload `event: update`

```json
{
  "aps": {
    "timestamp": 1730000000,
    "event": "update",
    "content-state": {
      "phase": "paused",
      "endDate": null,
      "pausedRemainingSeconds": 600,
      "startedAt": 1730000000.0,
      "totalDuration": 1200.0,
      "recipeName": "Борщ",
      "recipeThumbnailName": null,
      "syncedAt": 1730000000.0
    },
    "stale-date": 1730000060
  }
}
```

### Payload `event: end`

```json
{
  "aps": {
    "timestamp": 1730000000,
    "event": "end",
    "content-state": {
      "phase": "paused",
      "endDate": null,
      "pausedRemainingSeconds": 0,
      "startedAt": 1730000000.0,
      "totalDuration": 1200.0,
      "recipeName": null,
      "recipeThumbnailName": null,
      "syncedAt": 1730000000.0
    },
    "dismiss-date": 1730000000
  }
}
```

## ContentState ↔ Swift Codable parity

Источник истины: `RecipeTimerActivityAttributes.ContentState` в
`RecipeScalerNative/LiveActivity/RecipeTimerActivityAttributes.swift`.

| JSON key | Swift type | Notes |
|----------|------------|-------|
| `phase` | `TimerActivityPhase` raw string | `running` \| `paused` \| `exceeded` |
| `endDate` | `Date?` | **Seconds since Apple reference date (2001-01-01)** — default `JSONDecoder` / ActivityKit push. NOT Unix 1970. |
| `pausedRemainingSeconds` | `Int` | |
| `startedAt` | `Date` | Seconds since Apple reference date (2001) |
| `totalDuration` | `TimeInterval` / `Double` | seconds |
| `recipeName` | `String?` | from collection Y.Doc; may be null |
| `recipeThumbnailName` | `String?` | always null in v1 push |
| `syncedAt` | `Date` | Seconds since Apple reference date (2001); bump every push |

**Важно:** WWDC23 — content-state декодируется `JSONDecoder` с **default** strategies.
Swift `Date` Codable = `timeIntervalSinceReferenceDate` (2001-01-01), **не** Unix 1970.
Сервер обязан слать `endDate` / `startedAt` / `syncedAt` как `unixSeconds - 978307200`.
Иначе Lock Screen показывает ~`271752:xx:xx`.

`timestamp` / `stale-date` / `dismiss-date` в `aps` — Unix seconds (1970).
`timestamp` должен быть уникальным и монотонным для данной activity на каждый push.

## Mapping: ActiveTimer → content-state

| ActiveTimer field | content-state |
|-------------------|---------------|
| `isPaused == true` | `phase: "paused"`, `endDate: null`, `pausedRemainingSeconds: remainingAtPause ?? max(0, duration - pausedDuration)` |
| `isPaused == false` && `endTime > now` | `phase: "running"`, `endDate: endTime/1000`, `pausedRemainingSeconds: 0` |
| `isPaused == false` && `endTime <= now` | `phase: "exceeded"`, `endDate: endTime/1000` |
| `startedAt` | `startedAt` (ms→sec) или `createdAt` fallback |
| `duration` | `totalDuration` |
| `recipeId` → collection name | `recipeName` (best-effort) |

Event selection:

| Sync event | APNs `event` (v1) |
|------------|--------------|
| `timer_paused`, `timer_resumed`, `timer_started`, `timer_updated` | `update` (если activity token уже есть) |
| `timer_deleted` | `end` (+ `dismiss-date: now`) |

**v2** (`timer_started` без activity на target, iOS 18+): `event=start` — см. секцию ниже.
На iOS 17 remote start недоступен → только foreground reconcile.

## Fan-out rules

1. После `realtime.emitToUser('timer_event', …)` в `TimerSyncService.syncTimerEvents`.
2. Exclude `deviceId` источника.
3. Debounce 1s per `(userId, timerId)` — последний state wins.
4. `ApnsService.isConfigured === false` → no-op.
5. APNs `BadDeviceToken` / `Unregistered` → DELETE row from `liveactivity_tokens`
   (parity with alert push cleanup).

## iOS registration lifecycle

1. `Activity.request(..., pushType: .token)`
2. `for await tokenData in activity.pushTokenUpdates` (или `pushTokenStream`)
3. hex-encode → POST register
4. On `Activity.end` / local delete → DELETE unregister
5. Token rotation → POST again (UPSERT)

## v2 — APNs `event: start` (iOS 18+)

Создать Live Activity, когда таймер стартовал с web/Watch, а iPhone app не запущен.
Требует **push-to-start** token (не только per-activity token из v1) — детали регистрации
зафиксировать при реализации; topic/headers те же, что у `update`/`end`.

### Payload (набросок)

```json
{
  "aps": {
    "timestamp": 1730000000,
    "event": "start",
    "attributes-type": "RecipeTimerActivityAttributes",
    "attributes": {
      "timerId": "timer_<uuid>",
      "timerName": "Кипячение"
    },
    "content-state": {
      "phase": "running",
      "endDate": 1730001200.0,
      "pausedRemainingSeconds": 0,
      "startedAt": 1730000000.0,
      "totalDuration": 1200.0,
      "recipeName": null,
      "recipeThumbnailName": null,
      "syncedAt": 1730000000.0
    },
    "stale-date": 1730000060
  }
}
```

| Поле | Notes |
|------|-------|
| `attributes-type` | Имя Swift `ActivityAttributes` type |
| `attributes` | Статическая часть LA; ключи = Codable `RecipeTimerActivityAttributes` (не ContentState) |
| `content-state` | Тот же parity, что для `update` (даты — Apple reference 2001) |

**iOS 17**: не слать `start`; LA появится после foreground `reconcile`.
**Виджет silent push** — не этот контракт; см. **030-timer-widget v2**.

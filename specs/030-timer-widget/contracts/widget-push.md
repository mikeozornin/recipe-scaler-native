# Контракт: WidgetKit APNs push (TimerWidget)

**Спека**: [../spec.md](../spec.md)
**Платформы**: iOS WidgetKit ↔ APNs ↔ `recipe-scaler-web` server
**Дата**: 2026-08-04
**Зависимости**: [023-push-notifications](../../023-push-notifications/spec.md) (device APNs), [058-live-activity-push](../../058-live-activity-push/contracts/liveactivity-push.md) (LA — **не** смешивать topic/tokens)

Зеркало: `recipe-scaler-web/specs/030-timer-widget/contracts/widget-push.md`
(содержимое должно совпадать).

## Отличие от Live Activity push (058)

| | Widget push (030 v2) | Live Activity push (058) |
|--|----------------------|---------------------------|
| `apns-push-type` | `widgets` | `liveactivity` |
| Topic | `…push-type.widgets` | `…push-type.liveactivity` |
| Token scope | **device-level** | **per (device, timer)** |
| Body | `content-changed: true` | `event` + `content-state` |
| Эффект | WidgetKit перезагружает timelines | iOS обновляет Activity UI |

## HTTP: регистрация token

### POST `/api/push/apns-register-widget`

```json
{
  "token": "<hex widget push token>",
  "device_id": "<same as TimerSyncService / SharedAuthStore device id>"
}
```

Auth: как `/api/push/apns-register` и LA register — `requireUserId` / Bearer (spec 041).

Response:

```json
{ "success": true }
```

Поведение: **UPSERT** по `(user_id, device_id)` — ротация token перезаписывает строку.

### DELETE `/api/push/apns-register-widget?device_id=…`

Response: `{ "success": true }` (idempotent).

Вызывать при logout / account wipe / opt-out (если появится).

> Имена путей могут быть слегка уточнены при server implement, но семантика UPSERT + device_id обязательна. Альтернативный префикс `/api/v1/push/…` допустим, если единообразно с остальным push API — зафиксировать в web-зеркале.

## APNs: widget content-changed

### Headers

| Header | Value |
|--------|-------|
| `apns-push-type` | `widgets` |
| `apns-topic` | `ru.recipescaler.RecipeScaler.push-type.widgets` |
| `apns-priority` | `5` (рекомендуется) или `10` |
| `authorization` | `bearer <JWT>` (тот же APNs key, что 023/058) |

Topic = **main app Bundle ID** + `.push-type.widgets`.

### Payload

```json
{
  "aps": {
    "content-changed": true
  }
}
```

**Не** включать alert/sound/badge. **Не** класть timer content-state — виджет сам делает `GET /api/v1/timers/active`.

## Fan-out rules

1. Триггеры (те же timer sync events, что и для LA):  
   `timer_started`, `timer_paused`, `timer_resumed`, `timer_updated`, `timer_deleted`.
2. После (или параллельно с) realtime `timer_event` / LA push pipeline.
3. Для каждого **другого** устройства пользователя с строкой в `widget_push_tokens` — отправить widgets push.
4. **Exclude** `device_id` источника события.
5. **Debounce ~1 s** per `user_id`: один push на окно; **union** всех `device_id` источников в окне исключается из fan-out (не «last exclude wins»).
6. `ApnsService.isConfigured === false` → no-op.
7. APNs `BadDeviceToken` / `Unregistered` → DELETE row из `widget_push_tokens` (parity с 023/058 cleanup).

## iOS 17–25 primary path (silent + Provider fetch)

Apple `WidgetPushHandler` / `.pushHandler` — **SDK `@available(iOS 26.0, *)`** (не iOS 18). Пока HomeWidgetExtension `IPHONEOS_DEPLOYMENT_TARGET` = **17.0**, клиент **не** регистрирует widget push token через `.pushHandler` (opaque config + DT floor). Primary client path:

| Header / field | Value |
|----------------|-------|
| Push type | `background` (silent) |
| Token | существующий **device** APNs token (таблица/путь spec 023) |
| Body | `aps.content-available: 1` (+ опциональный data-ключ `reason: "timers"` / `widget-refresh`) |

Клиент: при silent wake — sync active timers → `TimerSnapshotStore.save` → `WidgetCenter.reloadTimelines(ofKind: "TimerWidget")`. Provider дополнительно делает `GET /api/v1/timers/active` при timeline reload.

Best-effort: iOS может отложить или не разбудить app.

### Server policy (B4.1) — зафиксировано

**Silent только для устройств без widget token** (не dual-send):

1. На тех же timer events / том же debounce (~1 s per `user_id`), что и widget fan-out.
2. Для каждого **другого** `device_id` с строкой в `apns_tokens` **и без** строки в `widget_push_tokens` — silent `content-available`.
3. Устройства с widget token получают только WidgetKit `content-changed` (iOS 26 path не дублируется silent).
4. Exclude `device_id` источника.
5. `BadDeviceToken` / `Unregistered` → DELETE из `apns_tokens` (parity 023).

Payload data-ключ: `reason: "timers"`.

## iOS registration lifecycle (WidgetKit push — future / iOS 26+)

1. Когда `.pushHandler` снова прикреплён к widget config (dual-target или type-erasure **без** поднятия appex DT выше 17): система отдаёт WidgetKit push token в `WidgetPushHandler`.
2. Hex-encode → `POST /api/push/apns-register-widget` с `device_id`.
3. Token rotation → POST снова (UPSERT).
4. Logout / wipe → `DELETE …?device_id=…`.
5. Все вызовы WidgetKit push API — только под `#available(iOS 26, *)`; deployment target main app **и** HomeWidgetExtension остаётся **iOS 17**.
6. До wire-up: registrar в main app готов принимать cached token; silent + Provider покрывают cross-device.

## Provider после push

Система вызывает timeline reload. `TimerWidgetProvider`:

1. Auth из `SharedAuthStore`.
2. `GET /api/v1/timers/active`.
3. Map → `TimerSnapshotDocument` → App Group.
4. Offline/error → existing snapshot (см. [data-model.md](../data-model.md)).

## Out of scope этого контракта

- Live Activity `event=update|end|start` — [058](../../058-live-activity-push/contracts/liveactivity-push.md).
- Alert timer-completed push — 023 / 036.
- Интерактивные кнопки на Home Widget.

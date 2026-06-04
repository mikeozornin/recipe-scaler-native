# Контракт: планирование push для таймеров (iOS)

**Спека**: [../spec.md](../spec.md)  
**Эталон веб**: `recipe-scaler-web/recipe-scaler/src/services/timer-service.ts` (`scheduleServerNotification`, `cancelServerNotification`)  
**API**: `recipe-scaler-web/server/src/routes/push.ts`

## Когда вызывать

| `TimerManager` | HTTP | Примечание |
|----------------|------|------------|
| `createTimer` (без старта) | `POST /api/push/schedule` | `duration_seconds` = `Int(timer.duration)` |
| `createAndStartTimer` | `POST /api/push/schedule` | `duration_seconds` = remaining до `endTime` |
| `startTimer` | `POST /api/push/schedule` | remaining от `endTime` |
| `pauseTimer` | `POST /api/push/cancel` | |
| `resumeTimer` | cancel → schedule | remaining после resume; reminder: сервер при `duration_seconds > 1800` |
| `deleteTimer` | `POST /api/push/cancel` | |

Не вызывать для `timer_completed` (локальное событие, не в HTTP sync — как 014).

## Тело schedule

```json
{
  "timer_id": "timer_<uuid>",
  "title": "Выпекать",
  "locale": "ru",
  "duration_seconds": 900,
  "recipe_id": "7daed53b-..."
}
```

Заголовки: те же, что REST/sync (`userId` / auth middleware на сервере).

## Тело cancel

```json
{
  "timer_id": "timer_<uuid>"
}
```

## Reminder (сервер)

- `duration_seconds > 1800` → `shouldScheduleReminder: true` (уже в `push.ts`).
- Reminder за 120 с до `triggerTime` (completion).
- При resume с remaining ≤ 120: передавать `duration_seconds ≤ 120` → reminder не планируется.

## Офлайн

- Если нет сети при schedule/cancel — положить в очередь (отдельная таблица или расширение `TimerSyncService` pending).
- При reconnect — drain после успешного auth.

## Локальный fallback

- Сохранить существующие UN в `TimerManager` для foreground и until APNs delivery подтверждена.
- После SC-PUSH-001 можно ужесточить дедуп (не показывать UN если server push доставлен в фоне за N с).
# Протокол Socket.IO — запись (Phase 3)

**Дата**: 2026-06-01  
**Расширяет**: [001-yrs-native-read/contracts/sync-protocol.md](../../001-yrs-native-read/contracts/sync-protocol.md)

## Клиент → сервер: `sync_request`

**Когда**: после локальной yrs write + debounce (~1 с) или при drain офлайн-очереди.

```json
{
  "recipeId": "uuid",
  "yjsUpdate": [1, 2, 3],
  "lastSyncedAt": "2026-06-01T12:00:00.000Z"
}
```

**Предусловия**:
- socket аутентифицирован (`auth` завершён)
- `RecipeEditPolicy.canEdit(version)` == true (только v3)
- `recipeId` совпадает с активным документом рецепта

**Emit в Swift** (`SyncEventHandler` или `YjsSyncService`):

```swift
socket.emit("sync_request", [
    "recipeId": recipeId,
    "yjsUpdate": YjsPayloadBytes.array(from: updateData),
    "lastSyncedAt": lastSyncedAt
])
```

## Сервер → клиент: `sync_confirmed`

**Действия Phase 3** (в Phase 2 было no-op):

1. Разобрать `recipeId`, `lastSyncedAt`
2. Обновить `ydoc_snapshots.lastSyncedAt` для `{userId}:recipe:{recipeId}`
3. Выставить `WriteSyncState.synced` для UI
4. Удалить соответствующие записи из `offline_sync_queue`

## Drain офлайн-очереди

После reconnect и `auth`:

1. Загрузить `offline_sync_queue` по `createdAt`
2. Для каждого `docKey` при нескольких строках — merge (опционально)
3. Emit `sync_request` последовательно по рецептам
4. Ждать `sync_confirmed` или `sync_error` перед следующим (или параллельно по doc с осторожностью)

## Контракт debounce

| Событие | Действие |
|---------|----------|
| Локальный commit yrs | Запланировать debounce 1000 мс для `recipeId` |
| Debounce + online | Emit `sync_request`, state → `syncing` |
| Debounce + offline | INSERT в `offline_sync_queue`, state → `queued` |
| Новый commit до срабатывания | Сброс таймера; merge буфера апдейтов |

## Ошибки (запись)

Та же таблица, что `sync_error` в Phase 2; при ошибке записи — `WriteSyncState.error`, не помечать synced.

| Паттерн | Действие при записи |
|---------|---------------------|
| Ownership failed | Показать ошибку; не считать dequeue успехом |
| Рецепт удалён | Очистить очередь рецепта; закрыть UI |
| Invalid update | Перезагрузить документ с сервера; отбросить failed queue entry |

## Матрица двунаправленного теста

| Шаг | Актор | Ожидание |
|-----|-------|----------|
| 1 | iOS | Edit name v3 → `sync_request` |
| 2 | Web | Новое имя <5 с |
| 3 | Web | Edit servings → `recipe_updated` |
| 4 | iOS | UI через observer |
| 5 | iOS | Edit в авиарежиме → очередь |
| 6 | iOS | Online → drain → веб видит изменение |

## Явно не отправляем (Phase 3)

- `sync_request` для ключа документа коллекции
- `sync_request` для документов рецептов v1/v2
- апдейты фрагмента описания
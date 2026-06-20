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

После reconnect и `auth` (паритет `processOfflineOperationsAfterLoad` на вебе):

1. `applyOfflineQueueToLocalDocs()` — idempotent merge в yrs
2. Для каждого recipe с unsynced local: `load_document` → CRDT-merge сервера в локальный doc (**не** skip при pending outbound; как `Y.applyUpdate` на вебе)
3. Для каждого `docKey` с pending:
   - **recipe v3 description**: push **полного yjs wire state** из `yjs_wire_snapshots` или `YjsMergeHelper.encodeFullState` (никогда yrs `encodeStateAsUpdate` на сервер)
   - collection / shopping: yrs snapshot или последний queued update
3. Emit `sync_request`; при `sync_confirmed` — очистить очередь и `yjs_wire_snapshots` для doc
4. Глобальный scan коллекции при cold start — без открытия редактора

## Контракт debounce

| Событие | Действие |
|---------|----------|
| Локальный commit yrs | Запланировать debounce 1000 мс для `recipeId` |
| Debounce + online | Emit `sync_request`, state → `syncing` |
| Debounce + offline | INSERT в `offline_sync_queue`, state → `queued` |
| Новый commit до срабатывания | Сброс таймера; merge буфера апдейтов |

## Ошибки (запись)

Каталог dot-key кодов для `sync_error`, legacy English-паттернов и клиентских действий поддерживается в едином контракте: [`specs/031-error-i18n/sync-error-codes.md`](../../031-error-i18n/sync-error-codes.md). При ошибке записи iOS устанавливает `WriteSyncState.error` и не помечает рецепт `synced`.

| `code` | Действие при записи |
|--------|---------------------|
| `sync.error.ownership` | Показать ошибку; не считать dequeue успехом |
| `sync.error.recipe-deleted` | Очистить очередь рецепта; закрыть UI |
| `sync.error.invalid-update` / `sync.error.empty-update` | Перезагрузить документ с сервера; отбросить failed queue entry |
| `sync.error.generic` | Sleep 5s, перезагрузить документ |

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
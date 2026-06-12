# Исследование: нативное редактирование рецепта (Phase 3)

**Дата**: 2026-06-01

## R1: API записи (yffi)

**Решение**: расширить Swift-обёртки `YrsInput` + `ymap_insert` / `yarray_insert_range` / `yarray_remove_range` внутри `withWriteTransaction` на `YrsDocument`. Исходящий апдейт — через существующий `encodeStateAsUpdate()` (diff после commit) или буфер `ydoc_observe_updates_v1`.

**Обоснование**: в Phase 2 уже используется `ydoc_write_transaction` для `applyUpdate`. Запись переиспользует те же экземпляры документов в `DocumentManager`. `ymap_insert` — канонический API yrs (не устаревший `ymap_set`).

**Отвергнутые варианты**:
- Переотправка полного state на каждое редактирование — отклонено (трафик, шум конфликтов)
- JavaScriptCore Yjs для записи — отклонено конституцией

## R2: Debounce и merge (паритет с вебом)

**Решение**: `actor UpdateDebouncer` — накапливать массив `Data` 1 с после последней локальной мутации; по срабатыванию отправлять каждый pending update отдельным `sync_request` (порядок сохраняется). Веб склеивает через `Y.mergeUpdates`; в bundled `libyrs.h` нет `ytransaction_merge_updates_v1` / `ymerge_updates`. Склейка через `state_diff_v1` на пустом doc **ломает** sync (no-op `00 00`).

**Обоснование**: SC-004; веб `yjs-client.ts` debounce; паритет по задержке и доставке, не по форме одного бинарника.

**Отвергнутые варианты**:
- Отправка на каждый keystroke — отклонено (нагрузка на сервер, провал SC-004)
- Debounce 3 с — отклонено (хуже паритет)

## R3: Офлайн-очередь

**Решение**: таблица GRDB `offline_sync_queue(id, docKey, recipeId, payload BLOB, createdAt, attemptCount)` — enqueue при срабатывании debouncer без socket; drain после успешного `auth` на reconnect; merge нескольких строк на `docKey` перед emit где возможно.

**Обоснование**: конституция offline-first; в Phase 2 есть snapshots, но нет очереди записи.

**Отвергнутые варианты**:
- Только in-memory — отклонено (kill приложения теряет правки)
- Отдельный файл очереди на doc — отклонено (GRDB уже используется)

## R4: Gate read-only для v1/v2

**Решение**: `RecipeEditPolicy.canEdit(recipe: RecipeData) -> Bool` возвращает `recipe.version == "v3"`. Проверка в `DocumentManager.applyLocalMutation` и публичных API `YjsSyncService` (throw или `.legacyFormatReadOnly`).

**Обоснование**: продуктовое решение — без миграции на iOS; миграция в вебе; защита от порчи v1 ingredients как JSON-string.

**Отвергнутые варианты**:
- Авто-upgrade v1→v3 при первом edit — отклонено продуктом
- Блок только в UI — отклонено (defense in depth на уровне сервиса)

## R5: Паттерн UX

**Решение**: один экран `YDocRecipeDetailView` с режимами **Просмотр / Редактирование**; редактирование ингредиента через **sheet**; баннер legacy сверху.

**Обоснование**: расширение экрана Phase 2; без нового navigation stack; sheet — привычный iOS-паттерн для CRUD строки списка.

**Отвергнутые варианты**:
- Отдельный `RecipeEditView` push — лишняя навигация, дублирование layout
- Всегда inline TextField — перегруз в режиме просмотра

## R6: Обработка `sync_confirmed`

**Решение**: по `sync_confirmed` обновить `lastSyncedAt` в SQLite для doc key, `WriteSyncState = .synced`, снять соответствующую запись из офлайн-очереди.

**Обоснование**: в Phase 2 handler был no-op; для Phase 3 нужно подтверждение для доверия UI.

**Отвергнутые варианты**:
- Считать успехом отсутствие `sync_error` — отклонено (неоднозначно)
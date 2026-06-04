# Задачи: нативное редактирование рецепта (Phase 3)

**Вход**: артефакты из `/specs/002-native-editing/`

**Предусловия**: plan.md, spec.md, research.md, data-model.md, contracts/

**Тесты**: в спеке явно не запрошены — задачи на автотесты не включены.

**Конституция**: строки i18n, обновление `docs/` — см. `.specify/memory/constitution.md`.

**Организация**: задачи сгруппированы по пользовательским историям для независимой реализации и проверки.

## Формат: `[ID] [P?] [Story] Описание`

- **[P]**: можно параллельно (разные файлы, нет зависимостей от незавершённых задач)
- **[Story]**: пользовательская история (US0–US5)
- Пути файлов — от корня репозитория

---

## Фаза 1: Setup (общая инфраструктура)

**Цель**: подтвердить базу Phase 2; добавить ключи i18n для Phase 3

- [x] T001 Проверить успешный `xcodebuild -scheme RecipeScalerNative -sdk iphonesimulator build` на текущей ветке (база Phase 2)
- [x] T002 [P] Добавить ключи i18n в `RecipeScalerNative/Localizable.xcstrings`: баннер legacy (FR-UI-002), статусы sync записи idle/pending/syncing/synced/error (FR-UI-003, FR-012), Edit/Done/Cancel, подписи sheet ингредиента (ru/en)

**Контрольная точка**: проект собирается; ключи локализации для всех FR-UI на месте

---

## Фаза 2: Foundational (блокирующие предпосылки)

**Цель**: API записи yrs, политика edit, debouncer, офлайн-очередь, `sync_request` / `sync_confirmed` — **обязательно до UI любой истории**

**⚠️ КРИТИЧНО**: работа по пользовательским историям не начинается, пока фаза не завершена

### Слой записи yrs

- [x] T003 Создать `RecipeScalerNative/Services/YjsSync/RecipeEditPolicy.swift` — `canEdit(version:) -> Bool` (только v3); `EditBlockedReason.legacyFormat` для ошибок сервиса
- [x] T004 Создать `RecipeScalerNative/Services/Yrs/YrsInput.swift` — мост `YInput` для string, int, double, bool по `contracts/yffi-write-api.md`
- [x] T005 [P] Расширить `RecipeScalerNative/Services/Yrs/YrsMap.swift` — `set(key:txn:value: YrsInput)`, `remove(key:txn:)` через `ymap_insert` в write txn вызывающего
- [x] T006 [P] Расширить `RecipeScalerNative/Services/Yrs/YrsArray.swift` — `insert(value:txn:at:)`, `remove(index:txn:len:)` через `yarray_insert_range` / `yarray_remove_range`
- [x] T007 Расширить `RecipeScalerNative/Services/Yrs/YrsDocument.swift` — `withWriteTransaction` + diff `encodeStateAsUpdate()` для debouncer; комментарии по памяти yffi

### Документ + путь sync записи

- [x] T008 Расширить `RecipeScalerNative/Services/YjsSync/DocumentManager.swift` — `applyLocalUpdate(recipeId:mutation:)` только v3; отклонение v1/v2 через `RecipeEditPolicy`; refresh observers после txn
- [x] T009 Создать `RecipeScalerNative/Services/YjsSync/UpdateDebouncer.swift` — `actor` на `docKey`, idle 1000 мс, накопление `Data`, callback по срабатыванию
- [x] T010 Расширить `RecipeScalerNative/Services/Storage/Database.swift` — миграция v2: таблица `offline_sync_queue` по `data-model.md`
- [x] T011 Создать `RecipeScalerNative/Services/YjsSync/OfflineWriteQueue.swift` — enqueue/dequeue/merge-by-docKey; GRDB через расширение `YDocStore` или `OfflineWriteQueueStore.swift`
- [x] T012 Расширить `RecipeScalerNative/Services/YjsSync/SyncEventHandler.swift` — обработка `sync_confirmed`: `lastSyncedAt`, уведомление `YjsSyncService` по `contracts/sync-write-protocol.md`
- [x] T013 Расширить `RecipeScalerNative/Services/YjsSync/YjsSyncService.swift` — `@Published writeSyncState: [String: WriteSyncState]`; методы `updateRecipeName/Servings/Color`, заглушки CRUD ингредиентов; при debounce — emit `sync_request` или enqueue offline; `drainOfflineQueue()` после auth на reconnect
- [x] T014 Расширить `RecipeScalerNative/Services/Storage/YDocStore.swift` — `saveSnapshot` после локальной записи и после `sync_confirmed`

**Контрольная точка**: мутация v3 в коде; debounced `sync_request` online; очередь offline; `sync_confirmed` обновляет snapshot

---

## Фаза 3: US0 — Просмотр legacy (Приоритет: P1)

**Цель**: v1/v2 с баннером; запись из UI недоступна

**Независимый тест**: открыть v1 — баннер, нет Edit; слайдер масштаба работает локально

### Реализация US0

- [x] T015 [US0] Создать `RecipeScalerNative/Views/RecipeLegacyBanner.swift` — info-баннер, ключ i18n FR-UI-002
- [x] T016 [US0] Расширить `RecipeScalerNative/Views/YDocRecipeDetailView.swift` — `RecipeLegacyBanner` при `version` v1/v2; скрыть Edit; скрыть баннер при переходе на v3 после observer

**Контрольная точка**: SC-007 — legacy не входят в edit mode

---

## Фаза 4: US1 — Основные поля v3 (Приоритет: P1) 🎯 MVP

**Цель**: название, порции, цвет на v3; iOS → web за 5 с

**Независимый тест**: изменить заголовок на iOS → обновить веб → совпадает

### Реализация US1

- [x] T017 [US1] Создать `RecipeScalerNative/ViewModels/RecipeEditViewModel.swift` — черновик name/servings/color; `commit()` → `YjsSyncService`; `cancel()` из `currentRecipe`
- [x] T018 [P] [US1] Создать `RecipeScalerNative/Views/RecipeEditToolbar.swift` — чип статуса sync из `writeSyncState[recipeId]` (FR-UI-003); UX по `plan.md` / веб mobile
- [x] T019 [US1] Расширить `RecipeScalerNative/Views/YDocRecipeDetailView.swift` — переключатель View/Edit; `TextField` названия, stepper/поле порций, чипы цвета; `RecipeEditViewModel`; `RecipeEditToolbar` только для v3
- [x] T020 [US1] Реализовать мутации `recipe.name`, `recipe.servings`, `recipe.color` в `Y.Map('recipe')` — `servings >= 1`; не писать `scaleFactor` (FR-007)

**Контрольная точка**: SC-001 — основные поля на вебе

---

## Фаза 5: US2 — CRUD ингредиентов v3 (Приоритет: P2)

**Цель**: добавление, правка, удаление, порядок через `Y.Array` of `Y.Map`

**Независимый тест**: добавить ингредиент на iOS → тот же список на вебе (id, order)

### Реализация US2

- [x] T021 [US2] Создать `RecipeScalerNative/Views/IngredientEditSheet.swift` — имя, amount (+ originalAmount при изменении), order; Save/Delete
- [x] T022 [US2] Расширить `DocumentManager` + `YjsSyncService` — `addIngredient`, `updateIngredient`, `removeIngredient` (поля v3: `id`, `name`, `amount`, `originalAmount`, `order`)
- [x] T023 [US2] Расширить `YDocRecipeDetailView.swift` — в edit: +, swipe-delete, tap → sheet; в view — read-only (FR-UI-004)

**Контрольная точка**: SC-002 — паритет ингредиентов с вебом

---

## Фаза 6: US3 — Nutrition v3 (Приоритет: P3)

**Цель**: калории, белки, жиры, углеводы редактируются и синхронизируются

**Независимый тест**: изменить калории на iOS → блок nutrition на вебе совпадает

### Реализация US3

- [x] T024 [US3] Расширить `RecipeEditViewModel` + `YDocRecipeDetailView` — числовые поля nutrition в edit (создать map при отсутствии)
- [x] T025 [US3] Путь записи nutrition в `DocumentManager`/`YjsSyncService` — double в `Y.Map` по `docs/YJS-SCHEMA.md` v3

**Контрольная точка**: создание/обновление nutrition на вебе

---

## Фаза 7: US4 — Офлайн-очередь (Приоритет: P4)

**Цель**: правки offline сохраняются и уходят на сервер при reconnect без ручного «синхронизировать»

**Независимый тест**: авиарежим → правка → сеть → веб за 10 с

### Реализация US4

- [x] T026 [US4] При срабатывании debouncer и `connectionState != .connected` → `OfflineWriteQueue.enqueue` вместо emit; `WriteSyncState` queued/pendingLocal (FR-008)
- [x] T027 [US4] `drainOfflineQueue()` из `YjsSyncService` после успешного `auth` на reconnect; FIFO по docKey, опциональный merge (research R3)
- [x] T028 [US4] Очистка `offline_sync_queue` при смене `userId` (logout / смена аккаунта) — без утечки между пользователями

**Контрольная точка**: SC-003 — offline edit доходит до веба

---

## Фаза 8: US5 — Debounce и ошибки sync (Приоритет: P5)

**Цель**: ≤2 `sync_request` за 10 с при быстром вводе; локализованные ошибки; удалённый рецепт

**Независимый тест**: быстрые правки полей → debounce; симуляция ownership error → сообщение

### Реализация US5

- [x] T029 [US5] Проверить/настроить `UpdateDebouncer` — сброс таймера на каждый commit; merge `Data` в буфере перед emit (SC-004)
- [x] T030 [US5] Расширить `SyncEventHandler` + `YDocRecipeDetailView`/`RecipeEditToolbar` — `sync_error` → локализованные алерты; не synced при ошибке (FR-011, SC-006)
- [x] T031 [US5] При tombstone/deleted `sync_error` — убрать рецепт из `collectionEntries`, pop navigation, purge очереди для `recipeId`

**Контрольная точка**: SC-004, SC-006 — debounce и UX ошибок проверены вручную

---

## Фаза 9: Polish (сквозные задачи)

**Цель**: документация, ручная валидация, сборка

- [x] T032 [P] Обновить `docs/ARCHITECTURE.md` и `PROJECT_STATUS.md` — write path Phase 3, офлайн-очередь, политика v3-only
- [x] T033 [P] Обновить `SETUP.md` — шаги ручных тестов из `specs/002-native-editing/quickstart.md`
- [ ] T034 Полная сборка simulator + матрица тестов quickstart (iOS→web, баннер legacy, offline)

---

## Зависимости и порядок

### Зависимости фаз

- **Фаза 1** → **Фаза 2** → пользовательские истории
- **US0** после фазы 2 (UI; policy уже в T003)
- **US1 (MVP)** после фазы 2
- **US2** зависит от edit shell US1
- **US3** зависит от edit mode US1
- **US4** зависит от T009–T011, T013
- **US5** после debouncer + `sync_confirmed`; после US1–US4

### Граф историй

```text
Фаза 2 (Foundational)
    ↓
US0 (legacy UI)
    ↓
US1 (основные поля) 🎯 MVP
    ↓
US2 (ингредиенты)
    ↓
US3 (nutrition)
    ↓
US4 (offline)
    ↓
US5 (debounce/ошибки)
    ↓
Polish
```

### Параллельные возможности

- T002 i18n параллельно T001
- T005 + T006 расширения yrs
- T015 + T018 после фазы 2
- T032 + T033 docs

---

## Пример параллели: US1

```text
После фазы 2:
T017 — RecipeEditViewModel.swift
T018 — RecipeEditToolbar.swift
затем T019 — интеграция в YDocRecipeDetailView.swift
T020 — мутации полей в YjsSyncService
```

---

## Стратегия реализации

### MVP (US0 + US1)

1. Фазы 1–2 (write path + debounce emit)
2. US0 — баннер legacy
3. US1 — основные поля → **проверка iOS → web**
4. US2 — ингредиенты
5. US4 — offline-first для записи
6. US3, US5 — polish

### Рекомендуемый scope MVP

**US0 + US1** после фазы 2 — двунаправленная запись v3 с защитой legacy.

---

## Фаза 6: US2a — Сетка ингредиентов (mobile web parity)

**Цель**: зафиксировать и реализовать UI сетки по `contracts/ingredients-grid-ui.md` (обсуждение 2026-06-04).

**Независимый тест**: тот же v3-рецепт на iOS (mobile) и веб (viewport &lt;640px) — две колонки qty, заголовки, scale в view, swipe delete, List reorder.

- [x] T040 [US2a] Документация: `contracts/ingredients-grid-ui.md` + FR-ING / US2a в `spec.md`, обновление `plan.md`
- [x] T041 [US2a] `YDocIngredientsSection.swift` — две колонки qty, заголовки Ingredient/Qty, нумерация, KBJU под именем
- [x] T042 [US2a] Просмотр: редактируемое scaled qty → `scaleFactor` (`YDocRecipeDetailView` + `RecipeScaleStorage`)
- [x] T043 [US2a] Edit: `List` + `swipeActions` delete + `onMove` reorder; убрать context menu / кастомный swipe
- [x] T044 [US2a] `RecipeRowLayoutMetrics` — ширина колонок под `280.8`, Qty над base-колонкой
- [ ] T045 [US2a] Ручной parity + скриншот: iOS vs mobile web (SC-002a); при расхождении — правка до совпадения. Авто: `scripts/verify-ingredients-edit-grid.sh` (edit grid screenshot); side-by-side с вебом — вручную

**Контрольная точка**: SC-002a; `xcodebuild` зелёный.

---

## Примечания

- **Референс UI**: веб mobile в `../recipe-scaler-web/recipe-scaler` — см. `plan.md`, § «Референс дизайна» и **`contracts/ingredients-grid-ui.md`**
- Расширять `YDocRecipeDetailView` Phase 2, не новый корень навигации
- XmlFragment описания read-only даже для v3 (FR-013)
- CRUD коллекции и создание рецепта — вне scope (FR-014)
- Payload `sync_request` — `contracts/sync-write-protocol.md`

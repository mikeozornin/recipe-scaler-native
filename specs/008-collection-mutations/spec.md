# Спецификация: мутации коллекции рецептов

**Ветка**: `008-collection-mutations`  
**Дата**: 2026-06-02  
**Статус**: ✅ Реализовано (аудит 2026-06-03)  
**Зависимости**: `002-native-editing` (паттерн write + offline queue), `007-app-shell-navigation`  
**Эталон**: `recipe-list.tsx`, `use-yjs-sync` collection writes, swipe gestures

## Аудит реализации (2026-06-03)

Реализовано полностью: `setRecipePinned` / `deleteRecipeFromCollection` / `createRecipe` в `YjsSyncService`, swipeActions (pin/delete) и кнопка создания в `RecipeListView`, инициализация v3-документа, offline-очередь, поиск без регрессий. US1–US5 закрыты.

## Контекст

Phase 2–3 читают `Y.Array('recipes')` и пишут **только документ рецепта**. На вебе пользователь **создаёт**, **удаляет (tombstone)**, **закрепляет** рецепты в коллекции — всё через CRDT коллекции.

iOS показывает pin-секции, но **не пишет** `isPinned` / `deleted` / новые entries.

## Цель

Полный CRUD метаданных коллекции на iOS с паритетом мобильного веба (жесты + действия).

## Пользовательские сценарии

### US1 — Pin / Unpin (P1)

**Когда** пользователь закрепляет рецепт (swipe или контекстное меню), **тогда** `isPinned: true` в entry коллекции; на вебе рецепт в секции «Закреплённые» ≤ 5 с.

Сортировка внутри секций — как `RecipeTitleEmoji.sortCollectionEntries` (уже на iOS).

### US2 — Удаление (P1)

**Когда** пользователь удаляет рецепт, **тогда** `deleted: true` (tombstone), рецепт исчезает из списка; открытая деталь закрывается; `sync_error` для удалённого документа — как 002.

### US3 — Создание рецепта (P1)

**Когда** пользователь создаёт пустой рецепт (кнопка «+» как на вебе), **тогда**:
- новый `id` (UUID),
- entry в коллекции,
- инициализированный документ `{userId}:recipe:{id}` version **v3** с `servings: 1`,
- навигация на деталь в режиме редактирования.

### US4 — Офлайн (P1)

Pin/delete/create в офлайне → очередь на документ коллекции + при create — также очередь на новый recipe doc.

### US5 — Жесты (P2)

**Паритет PRD**: pin/unpin и delete **без** перехода от одного swipe-действия к другому в одном жесте (как mobile list gestures).

## Требования

### FR-COL-001 — Документ

Ключ: `{userId}:collection`, события `collection_updated`, `sync_request` с `documentKind` коллекции (как веб).

### FR-COL-002 — Поля entry

`id`, `name`, `color`, `imageUrl`, `updatedAt`, `deleted`, `isPinned` — по `docs/YJS-SCHEMA.md`.

### FR-COL-003 — Создание recipe doc

После entry — `load_document` / локальная инициализация v3 map + пустой `XmlFragment('description')` опционально.

### FR-COL-004 — UI

- Кнопка добавления в toolbar списка (как mobile header веба).
- `swipeActions`: pin, delete (destructive).
- Подтверждение удаления (alert).

### FR-COL-005 — Поиск

Существующий поиск не ломается; удалённые не показываются.

## Вне scope

- Массовый импорт в коллекцию (010 создаёт через сервер)
- Дублирование рецепта (можно позже)
- Редактирование `name` в списке inline (веб desktop; mobile — через деталь)

## Критерии успеха

- **SC-001**: Pin на iOS → веб закреплён ≤ 5 с.
- **SC-002**: Delete на iOS → веб не показывает рецепт ≤ 5 с.
- **SC-003**: Create → оба клиента видят новый id; v3 на вебе.
- **SC-004**: Офлайн create → оба видят после reconnect ≤ 10 с.

## Артефакты

- `contracts/collection-sync.md` — payload `collection_updated` / queue
- `data-model.md` — CollectionEntry write paths
- `quickstart.md`
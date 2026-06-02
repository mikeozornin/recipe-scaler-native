# Спецификация: список покупок

**Ветка**: `009-shopping-list`  
**Дата**: 2026-06-02  
**Статус**: Draft  
**Зависимости**: `007-app-shell-navigation`, `002` (sync patterns)  
**Эталон**: `shopping-list-page.tsx`, `use-shopping-list-sync.ts`, `@shared/shopping-list/types`

## Контекст

Список покупок — **отдельный Y.Doc** (`{userId}:shoppingList`, `documentKind: shopping`), не часть коллекции. PRD: checked items, sort recipe/A-Z, manual items, swipe-delete, add from recipe (без section headers).

iOS: документ не синхронизируется, вкладки Shopping нет.

## Цель

Полная работа со списком покупок на iOS offline-first, паритет мобильного веба.

## Пользовательские сценарии

### US1 — Просмотр и сортировка (P1)

**Когда** открыта вкладка Shopping, **тогда** секции «Купить» / «Куплено», переключатель sort `recipe` | `alphabet` в meta.

### US2 — Check / uncheck (P1)

**Когда** пользователь отмечает пункт, **тогда** optimistic UI → `purchased` + `purchasedAt`; undo в pending фазе (как PRD); sync через `shopping_list_updated`.

### US3 — Добавление из рецепта (P1)

**Дано** деталь рецепта, **когда** «Добавить в список покупок» (все или выбранные ингредиенты), **тогда** items с `recipeId`, `ingredientId`, `recipeName`; без separator/header строк.

**Эталон**: `shopping-list-from-recipe.ts`, swipe side `shopping` на `recipe-detail.tsx`.

### US4 — Ручной пункт (P2)

**Когда** пользователь добавляет текст вручную, **тогда** item без `recipeId`.

### US5 — Удаление swipe (P2)

Swipe-delete удаляет item из `Y.Array`.

### US6 — Офлайн (P1)

Все операции в локальном doc + offline queue; drain при reconnect.

## Требования

### FR-SHOP-001 — Sync

- Socket: `shopping_list_updated`, `sync_request` с `documentKind: shoppingList` (имя как на сервере — сверить с `llm/ARCHITECTURE.md`).
- `YjsSyncService` расширить: отдельный document manager или ветка в `DocumentManager`.

### FR-SHOP-002 — Схема

```
Y.Map('shopping')
  items: Y.Array<Y.Map>
  meta: Y.Map { sortMode, schemaVersion }
```

Поля item — `docs/PRD.md` § Shopping List Document.

### FR-SHOP-003 — UI mobile

Stacked header две строки (PRD shopping header mobile); кнопка share — в **012**, здесь placeholder disabled или hidden.

### FR-SHOP-004 — Discover entry в header

Ссылка Discover в header списка — как веб (навигация на Discover tab).

## Вне scope

- Публичный share списка (012)
- Text export popover (012 / 013)

## Критерии успеха

- **SC-001**: Add from recipe iOS → item на вебе shopping ≤ 5 с.
- **SC-002**: Check offline → веб после reconnect.
- **SC-003**: Sort mode persists в meta на обоих клиентах.

## Артефакты

- `data-model.md`
- `contracts/shopping-list-sync.md`
- `quickstart.md`
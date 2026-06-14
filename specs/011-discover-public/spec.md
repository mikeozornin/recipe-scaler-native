# Спецификация: Discover и публичные профили

**Ветка**: `011-discover-public`  
**Дата**: 2026-06-02  
**Статус**: ✅ Реализовано (аудит 2026-06-15). Включение вкладки — [017-discover-enablement](../017-discover-enablement/spec.md) ✅  
**Зависимости**: `007-app-shell-navigation`, `008-collection-mutations` (clone → create)  
**Эталон**: `/discover` routes, `PublicProfileHeader`, PRD § Discover / Public Sharing

## Аудит реализации (2026-06-15)

Вкладка Discover активна в `AppShellView`. Экраны: `DiscoverRootView`, `DiscoverCollectionView`, `DiscoverRecipeView`, `DiscoverPublicProfileView`, `DiscoverAPI`, превью через `DiscoverRecipePreviewImage` / URLCache.

| Требование | Статус |
|------------|--------|
| US1 Discover home | ✅ |
| US2 curated collection/recipe | ✅ |
| US3 публичный профиль | ✅ `DiscoverPublicProfileView` (grid, search, share-mode) |
| US4 copy to my recipes (clone) | ✅ `DiscoverAPI.cloneRecipe` + `loadRecipe` |
| US5 reset tab | ✅ |

**iOS-отступления** (зафиксировано в 017): нет sticky breadcrumb как на вебе; deep links — опционально позже (FR-DISC-004).

## Прошлый аудит (2026-06-03)

| Требование | Статус |
|------------|--------|
| US1–US2 | 🟡 код есть, вкладка была отключена |
| US3 | ❌ заглушка «open on web» |

## Контекст

Вкладка Discover — curated collections, curated recipes, публичные профили `/#/public/@/{username}/{recipeId}`.

iOS реализует REST discover и публичные экраны (см. аудит 2026-06-15).

## Цель

Просмотр curated контента и копирование рецептов в свою коллекцию; просмотр чужих публичных профилей (read-only).

## Пользовательские сценарии

### US1 — Discover home (P1)

**Когда** открыт Discover, **тогда** список коллекций и рецептов с API `GET /api/discover/collections`, карточки с превью.

### US2 — Curated collection / recipe (P1)

**Когда** пользователь открывает элемент, **тогда** деталь с sticky header (back + breadcrumb) как `PublicProfileHeader`.

### US3 — Публичный профиль (P2)

**Когда** открыт `/@username`, **тогда** grid рецептов, search, режимы share owner (`one_by_one` | `all` | `with_images_and_steps`) — read-only для гостя.

### US4 — Copy to my recipes (P1)

**Когда** «Скопировать в мои рецепты», **тогда** `POST .../clone` → новый id в коллекции пользователя, toast + navigate to recipe.

### US5 — Reset tab (P1)

Повторный tap Discover с вложенного экрана → корень (FR-NAV-002 в 007).

## Требования

### FR-DISC-001 — REST only

Discover metadata **не** в пользовательском Y.Doc; кэш в памяти/URLCache, offline — последний кэш + сообщение.

### FR-DISC-002 — Clone

После clone — sync collection + load recipe doc (как create в 008).

### FR-DISC-003 — Public recipe page

Read-only detail: author, breadcrumbs, copy CTA; без редактирования чужого doc.

### FR-DISC-004 — URL formats

Поддержать deep link схемы PRD для шаринга в 012 (опционально universal links позже).

## Вне scope

- Редактирование своего public profile (013)
- PDF cookbook публичного профиля

## Критерии успеха

- **SC-001**: Clone curated recipe → появляется в «Мои рецепты» на вебе ≤ 10 с.
- **SC-002**: UI header соответствует веб mobile screenshots (breadcrumb/back).

## Артефакты

- `contracts/discover-api.md`
- `quickstart.md`
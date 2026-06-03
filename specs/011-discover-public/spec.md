# Спецификация: Discover и публичные профили

**Ветка**: `011-discover-public`  
**Дата**: 2026-06-02  
**Статус**: 🔴 Написано, но недоступно (аудит 2026-06-03). Остаток → [017-discover-enablement](../017-discover-enablement/spec.md)  
**Зависимости**: `007-app-shell-navigation`, `008-collection-mutations` (clone → create)  
**Эталон**: `/discover` routes, `PublicProfileHeader`, PRD § Discover / Public Sharing

## Аудит реализации (2026-06-03)

Реализовано в коде, но **вкладка Discover закомментирована в `AppShellView` → экраны недостижимы** для пользователя. Файлы: `DiscoverRootView`, `DiscoverAPI` (collections/collection/recipe/clone).

| Требование | Статус |
|------------|--------|
| US1 Discover home | 🟡 код есть, **вкладка отключена** |
| US2 curated collection/recipe | 🟡 код есть, недостижим |
| US3 публичный профиль | ❌ заглушка «open on web for full parity» |
| US4 copy to my recipes (clone) | ✅ `DiscoverAPI.cloneRecipe` + `loadRecipe` |
| US5 reset tab | ✅ (в shell), но недостижим пока вкладка off |

Не сделано → **017-discover-enablement**: включить вкладку, реализовать экран публичного профиля (grid + search + share-mode read-only), загрузку превью-изображений curated.

## Контекст

Вкладка Discover — curated collections, curated recipes, публичные профили `/#/public/@/{username}/{recipeId}`.

iOS не реализует REST discover и публичные экраны.

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
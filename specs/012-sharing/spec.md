# Спецификация: публичный шаринг

**Ветка**: `012-sharing`  
**Дата**: 2026-06-02  
**Статус**: 🟡 Частично реализовано (аудит 2026-06-03). Остаток → [019-sharing-shopping](../019-sharing-shopping/spec.md)  
**Зависимости**: `008` (`isPublic` в recipe doc), `009` (shopping share API), `011` (public URLs)  
**Эталон**: share popover на recipe + shopping, PRD § Public Sharing

## Аудит реализации (2026-06-03)

Реализовано: `RecipeDetailShareButton` (ShareLink + `PublicURLBuilder`), toggle public в `RecipeDetailActionsMenu` → `updateRecipeIsPublic`. `SharingAPI` для shopping написан, **но не подключён в UI**.

| Требование | Статус |
|------------|--------|
| US1 share recipe link | ✅ |
| US2 toggle public рецепта | ✅ |
| US3 shopping list share | ❌ `SharingAPI.updateShoppingListShare` есть, нет UI |
| US4 text export shopping | ❌ |

Не сделано → **019-sharing-shopping**: UI шаринга списка покупок (toggle + публичный URL) и text-export секции «to buy». Строки кнопок — на английском (см. 022).

## Контекст

Пользователь делится:

- отдельным рецептом (`is_public`, legacy `/#/public/{id}` и profile URL),
- списком покупок (read-only public link),
- режимами публичного профиля (013).

## Цель

Те же переключатели и ссылки, что мобильный веб; системный share sheet iOS.

## Пользовательские сценарии

### US1 — Share recipe link (P1)

**Когда** Share на детали рецепта, **тогда** копирование/ShareLink URL в формате PRD; учёт `is_public`.

### US2 — Toggle public (P1)

**Когда** пользователь включает публичность рецепта, **тогда** `isPublic` в Y.Map + sync; private profile + `is_public` — по PRD (direct link still works).

### US3 — Shopping list share (P2)

**Когда** enable share в shopping settings, **тогда** `PUT /api/v1/shopping-list/share`, показ URL `/#/public/shopping-list/:publicId`.

### US4 — Text export shopping (P3)

**Когда** export text из popover, **тогда** только секция «to buy» (PRD), даже если public share off.

## Требования

### FR-SHR-001 — Recipe public flag

Запись `isPublic` только v3 + collection visibility rules как веб.

### FR-SHR-002 — UI

- Menu на mobile header recipe (`recipe-header.tsx` mobile actions).
- Не дублировать destructive delete в том же gesture, что pin (PRD).

### FR-SHR-003 — Read-only recipients

Нативное приложение **не** обязано рендерить guest public pages в 012 — достаточно генерации URL; guest view может оставаться веб/PWA (опционально in-app WebView — out of scope unless requested).

## Критерии успеха

- **SC-001**: Toggle public iOS → веб public URL открывается без логина.
- **SC-002**: Shopping share URL read-only на вебе.

## Артефакты

- `contracts/sharing-api.md`
- `quickstart.md`
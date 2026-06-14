# Спецификация: публичный шаринг

**Ветка**: `012-sharing`  
**Дата**: 2026-06-02  
**Статус**: ✅ Реализовано (аудит 2026-06-15). Shopping share/export → [024-shopping-list-completion](../024-shopping-list-completion/spec.md) ✅  
**Зависимости**: `008` (`isPublic` в recipe doc), `024` (shopping share UI), `011` (public URLs)  
**Эталон**: share popover на recipe + shopping, PRD § Public Sharing

## Аудит реализации (2026-06-15)

| Требование | Статус |
|------------|--------|
| US1 share recipe link | ✅ `RecipeDetailShareButton` → `RecipeShareSheet` (ShareLink + `PublicURLBuilder`) |
| US2 toggle public рецепта | ✅ toggle в `RecipeShareSheet` → `updateRecipeIsPublic` |
| US3 shopping list share | ✅ `ShoppingListShareSheet` + `SharingAPI` (024) |
| US4 text export shopping | ✅ `ShoppingListPlainText` + copy (024) |

> Аудит 2026-06-03 («SharingAPI не в UI») устарел — shopping share закрыт в 024.

## Прошлый аудит (2026-06-03)

Shopping list share/export были в процессе; recipe share ✅.

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
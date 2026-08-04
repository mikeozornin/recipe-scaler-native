# Спецификация: Universal Links для публичных share-URL

**Ветка**: `059-universal-links`  
**Дата**: 2026-08-04  
**Статус**: ✅ Реализовано (код + AASA на prod 2026-08-04; device QA после portal Associated Domains)  
**Зависимости**: `011` (Discover public), `012` (sharing / PublicURLBuilder), `025` (`DeepLinkRouter`)  
**Эталон**: Apple Universal Links + AASA; веб path-based `/public/@/...`

## Контекст

Кастомная схема `recipe-scaler://` уже открывает свои рецепты / shopping / home. Публичные share-ссылки — **path-based** `https://recipe-scaler.ru/public/@/{username}[/{recipeId}]` (OG + ShareLink). Без Associated Domains тап по такой ссылке всегда остаётся в Safari, хотя в app уже есть `DiscoverPublicProfileView` / `DiscoverRecipeView`.

## Цель

Тап по публичной share-ссылке на устройстве с установленным Recipe Scaler открывает **нативное** приложение на соответствующем экране Discover. Без app — обычный веб.

## Пользовательские сценарии

### US1 — Публичный профиль (P1)

**Когда** пользователь тапает `https://recipe-scaler.ru/public/@/{username}` (Notes, Messages, Safari и т.п.) и app установлен, **тогда** открывается Recipe Scaler → вкладка Discover → публичный профиль `@username`.

### US2 — Публичный рецепт (P1)

**Когда** пользователь тапает `https://recipe-scaler.ru/public/@/{username}/{recipeId}`, **тогда** app открывает Discover → экран публичного рецепта (с возможностью «Copy to my recipes»).

### US3 — Private / Discover path URLs (P1)

**Когда** пользователь тапает `https://recipe-scaler.ru/recipe/{id}`, `/`, `/shopping`, `/discover` или `/discover/collection|recipe/...`, **тогда** app открывает соответствующий экран (parity с `recipe-scaler://` и web path’ами).

### US4 — Нет app / не заявленный path (P2)

**Когда** app не установлен **или** URL вне claimed paths (legacy `/public/{uuid}`, public shopping-list, OAuth, about/privacy), **тогда** открывается Safari / веб как раньше.

## Требования

### FR-UL-001 — AASA

Сервер отдаёт `GET /.well-known/apple-app-site-association` с `Content-Type: application/json`, без редиректа. Claimed paths: `/public/@/*`, `/recipe/*`, `/discover`, `/discover/collection/*`, `/discover/recipe/*`, `/shopping`, `/`. App ID: `ZBPX4JYT24.ru.recipescaler.RecipeScaler`.

### FR-UL-002 — Associated Domains

Main app entitlement: `applinks:recipe-scaler.ru`. Capability в Apple Developer Portal на App ID.

### FR-UL-003 — Парсинг https

`DeepLinkRouter` принимает Universal Links: `/public/@/...`, `/recipe/{uuid}`, `/`, `/shopping`, `/discover`, `/discover/collection/{slug}`, `/discover/recipe/{uuid}` (и `www`). Игнорирует legacy `/public/{uuid}`, shopping-list public, oauth, чужие хосты. Схема `recipe-scaler://` без регрессий.

### FR-UL-004 — Навигация

Новые / расширенные `DeepLink`: `openPublicProfile`, `openPublicRecipe`, `openDiscover`, `openDiscoverCollection`, `openDiscoverRecipe`, плюс https-parity для `openRecipe` / `openHome` / `openShoppingList` → `AppShellCoordinator`.

### FR-UL-005 — Entry points

`.onOpenURL` и `.onContinueUserActivity(NSUserActivityTypeBrowsingWeb)`.

## Вне scope

- Legacy `/public/{recipeId}` без `@`
- Guest shopping list viewer (`/public/shopping-list/*`)
- `/oauth/*`, `/about`, `/privacy`, `/account`
- BrowserRouter — реализовано в web `060` (полная миграция); path в адресной строке совпадает с AASA

## Критерии успеха

- **SC-001**: AASA на prod → 200 JSON с нужным `appID` и paths.
- **SC-002**: Unit-тесты парсера: public/@, recipe, home, shopping, discover accepted; legacy / public shopping-list / oauth / wrong host rejected.
- **SC-003**: `recipe-scaler://recipe/{id}` по-прежнему → My Recipes.
- **SC-004** (device): tap share / app URL → native screen (после portal + signing + CDN AASA cache).

## Артефакты

- `plan.md`, `tasks.md`, `contracts/aasa.md`

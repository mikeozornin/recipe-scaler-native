# Спецификация: шаринг списка покупок и text-export

**Ветка**: `019-sharing-shopping`  
**Дата**: 2026-06-03  
**Статус**: Draft (перенос недоделок из 012)  
**Зависимости**: `012-sharing` (recipe share готов), `009-shopping-list`  
**Эталон**: share popover на shopping, PRD § Public Sharing

## Контекст

В 012 отгружено: share-ссылка рецепта (`RecipeDetailShareButton`) и toggle public рецепта. **Не закрыто**: шаринг списка покупок (US3) и text-export (US4). `SharingAPI.updateShoppingListShare` / `fetchShoppingListSettings` уже написаны, но **не подключены к UI**.

## Цель

Дать пользователю включить публичную read-only ссылку на список покупок и выгрузить текст секции «to buy» — паритет popover мобильного веба.

## Пользовательские сценарии

### US1 — Toggle публичного списка (P1)

**Дано** вкладка Shopping, **когда** пользователь включает share, **тогда** `PUT /api/v1/shopping-list/share` → показ URL `/#/public/shopping-list/:publicId`, системный ShareLink.

### US2 — Статус share при открытии (P2)

**Когда** открыт share-UI, **тогда** текущее состояние подтягивается через `fetchShoppingListSettings` (enabled + publicId).

### US3 — Text export (P3)

**Когда** пользователь выбирает «export text», **тогда** копируется/шарится только секция «to buy» (PRD), даже если public share выключен.

### US4 — Офлайн (P2)

**Дано** офлайн, **тогда** кнопки share/export недоступны с понятным i18n-сообщением.

## Требования

### FR-019-001 — UI в Shopping header

Кнопка/меню share в шапке `ShoppingListView` (paritet mobile shopping header). Подключить существующий `SharingAPI`.

### FR-019-002 — URL формат

Публичный URL списка — через `PublicURLBuilder` (формат как веб).

### FR-019-003 — Text export

Сборка текста из `shoppingSnapshot` (только непомеченные / «to buy»), через `UIActivityViewController` / ShareLink.

### FR-019-004 — i18n

Все строки — локализованные ключи ru/en (см. 022).

## Вне scope

- Рендер публичной страницы списка в приложении (остаётся веб/PWA)
- Шаринг рецепта (готово в 012)

## Критерии успеха

- **SC-001**: Toggle share iOS → публичный URL списка открывается на вебе без логина (read-only).
- **SC-002**: Состояние share корректно отображается при повторном открытии.
- **SC-003**: Text export содержит только «to buy».
- **SC-004**: Офлайн — кнопки disabled с i18n.

## Артефакты

- `contracts/sharing-api.md` — shopping share/settings
- `quickstart.md`

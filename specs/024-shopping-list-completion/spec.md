# Спецификация: список покупок (единая)

**Ветка**: `024-shopping-list` (или `024-shopping-list-completion`)  
**Дата**: 2026-06-04  
**Закрыто**: 2026-06-04  
**Статус**: ✅ **Готово** — **каноническая спека** (объединяет бывшие 009-shopping-list и 019-sharing-shopping)  
**Зависимости**: `007-app-shell-navigation`, `012-sharing` (share рецепта), `022-i18n-new-views`  
**Эталон (мобильный веб)**:

- `recipe-scaler-web/recipe-scaler/src/pages/shopping-list-page.tsx`
- `recipe-scaler-web/recipe-scaler/src/hooks/use-shopping-list-sync.ts`
- `recipe-scaler-web/recipe-scaler/src/pages/recipe-detail.tsx`
- `recipe-scaler-web/recipe-scaler/src/utils/format-shopping-list-plain-text.ts`
- `@shared/shopping-list/types`

---

## Итог

Фича закрыта на iOS: вкладка **Shopping**, offline-first Y.Doc, паритет мобильного веба по списку, добавлению из рецепта, share/export и UX-полировке (toast, swipe, header).

### Верификация (локально, симулятор iPhone 16)

| Скрипт | Назначение |
|--------|------------|
| `scripts/verify-shopping-list.sh` | вкладка, grep контрактов, скрин |
| `scripts/verify-shopping-list-smoke.sh` | sync + add flows (`-ShoppingSmokeTest=1`, 8 items) |
| `scripts/verify-shopping-list-ui-polish.sh` | header, share sheet, copy → toast |

`xcodebuild -scheme RecipeScalerNative build` — обязателен после правок.

Скриншоты: `specs/024-shopping-list-completion/screenshots/`.

---

## Контекст

Список покупок — **отдельный Y.Doc** (`{userId}:shoppingList`, `documentKind: shoppingList`), не часть коллекции. PRD: checked items, sort recipe/A-Z, manual items, swipe-delete, add from recipe, публичный share, text export.

### Реализовано на iOS


| Компонент | Статус |
|-----------|--------|
| `ShoppingListView`, `ShoppingListData`, `DocumentManager+ShoppingList` | ✅ |
| Sync `shopping_list_updated`, offline queue (`documentKind: shoppingList` без `recipeId`) | ✅ |
| Sort, check/uncheck (staging + haptic), swipe-delete, ручной пункт, inline edit | ✅ |
| `clearPurchasedShoppingItems`, `updateShoppingItemLabel` | ✅ |
| Add all / add ingredient / swipe recipe list → shopping | ✅ |
| `SharingAPI`, share sheet, plain text export, `PublicURLBuilder` | ✅ |
| Вкладка Shopping в `AppShellView` | ✅ |
| Toast `TransientStatusBanner` + `ShoppingFeedback` | ✅ |
| `ShoppingListPlainText`, DEBUG smoke / UI verify | ✅ |

---

## Пользовательские сценарии

### Базовые (009)

| ID | Сценарий | Статус |
|----|----------|--------|
| US-B1 | Просмотр и сортировка (вкладка Shopping, секции, sort в meta) | ✅ |
| US-B2 | Check / uncheck, sync | ✅ |
| US-B3 | Добавление из рецепта (все ингредиенты + swipe одного) | ✅ |
| US-B4 | Ручной пункт, inline edit | ✅ |
| US-B5 | Удаление swipe / onDelete | ✅ |
| US-B6 | Офлайн + drain | ✅ |

### Шаринг и export (019)

| ID | Сценарий | Статус |
|----|----------|--------|
| US-S1 | Toggle публичного списка, URL, copy link | ✅ |
| US-S2 | `fetchShoppingListSettings` при открытии share | ✅ |
| US-S3 | «Скопировать текстом» — только «Купить», `ShoppingListPlainText` | ✅ |
| US-S4 | Share/export офлайн — disabled + alert | ✅ |

### Доведение до веба (024)

| ID | Сценарий | Статус |
|----|----------|--------|
| US0 | Вкладка Shopping, a11y `tabShopping` | ✅ |
| US-L1 | Stacked header: заголовок + «Поделиться», sort | ✅ |
| US-L2 | Пустые состояния, «Очистить» купленное | ✅ |
| US-L3 | Поле «Добавить» внизу to-buy | ✅ |
| US-L4 | Inline edit ручных пунктов | ✅ |
| US-R1 | Swipe ингредиента → shopping (read-only detail) | ✅ |
| US-R2 | Toast при добавлении (`shopping.items-added.*`) | ✅ |
| US-R3 | «Открыть список» из меню рецепта | ✅ |
| US-P1 | Check staging (~1 с) + haptic (не полный confetti веба) | ✅ зафиксировано |
| US-P2 | Discover в header shopping | ⏸ вне scope до 017 |

---

## Требования

### Sync и схема

- **FR-SHOP-001** — `shopping_list_updated`, `sync_request` с `documentKind: shoppingList` ✅
- **FR-SHOP-002** — схема `Y.Map('shopping')` / items / meta ✅
- **FR-SHOP-003** — `updateShoppingItemLabel`, `clearPurchasedShoppingItems` ✅

### UI и навигация

- **FR-024-001** — вкладка Shopping ✅
- **FR-024-002** — share UI (toggle, URL accent, copy link/text, toast после dismiss sheet) ✅
- **FR-024-003** — `ShoppingListPlainText` ✅
- **FR-024-004** — i18n `Localizable.xcstrings` ✅
- **FR-024-005** — `scripts/verify-shopping-list*.sh` ✅

---

## Вне scope (не входило в 024)

- Публичная страница списка в нативном app (веб/PWA)
- Confetti при покупке
- Шаринг рецепта (012, отдельно)
- Rich-text описание (018)
- v1/v2 editing на iOS
- Discover в header shopping (017)

---

## Критерии успеха


| ID | Критерий | Статус |
|----|----------|--------|
| SC-001 | Add from recipe iOS → item на вебе ≤ 5 с online | ✅ smoke |
| SC-002 | Check offline → веб после reconnect | ✅ архитектура 009 |
| SC-003 | Sort mode persists в meta | ✅ |
| SC-004 | Вкладка Shopping без debug | ✅ |
| SC-005 | Toggle share → публичный URL на вебе | ✅ API + UI |
| SC-006 | Text export = только «Купить» | ✅ |
| SC-007 | `verify-shopping-list.sh` + build | ✅ |


---

## Решения при закрытии

1. **Discover в header** — отложено до [017-discover-enablement](../017-discover-enablement/spec.md).
2. **Анимация check** — staging + haptic; полный confetti веба не переносился.
3. **«Открыть список»** — реализовано в `RecipeDetailActionsMenu` (`openAppShoppingTab`).

---

## Артефакты

- `screenshots/` — симулятор (список, header, share, toast)
- `scripts/verify-shopping-list.sh`, `verify-shopping-list-smoke.sh`, `verify-shopping-list-ui-polish.sh`
- Код: `ShoppingListView`, `TransientStatusBanner`, `ShoppingListPlainText`, `ShoppingFeedback`, `DocumentManager+ShoppingList`

Контракты `contracts/*`, `data-model.md`, `quickstart.md` — по необходимости при расширении; для закрытия фичи не блокируют.

---

## История спек

- **009-shopping-list**, **019-sharing-shopping** — удалены/слиты в эту спеку (2026-06-04).
- Статус **Готово** — после прохода sync-fix, smoke, UI polish, toast/swipe/share.
# Research: 074 process-table (native)

**Дата**: 2026-09-12  
**Спека**: [spec.md](./spec.md)

Все пункты Technical Context закрыты. Новых [NEEDS CLARIFICATION] нет.

## Landscape на iPhone

- **Decision:** `fullScreenCover` + системный landscape (`requestGeometryUpdate` + маска только landscape на время сессии). Поворот в portrait **не** dismiss — UI остаётся landscape до Close. iPad — без geometry lock. **Не** `rotationEffect` 90°.
- **Rationale:** chrome должен быть iOS-native, не web overlay и не «повёрнутая картинка». Navigation push оставляет portrait chrome карточки.
- **Alternatives:** web overlay; DIY 90° layout-swap (врёт safe area) — отвергнуты.

## Канон хеша

- **Decision:** ручная сборка JSON как `canonicalizeProcessTableSource` (порядок ключей `ingredients` → `steps`; поля id / originalAmount / unit). SHA-256 UTF-8 hex через CryptoKit. Шаги — strip тегов с живого HTML (`<li>` иначе `<p>`), тот же decode entities, что TS.
- **Rationale:** `JSONEncoder` не гарантирует порядок ключей JS `JSON.stringify`.
- **Alternatives:** Codable + sorted keys — расходится с web, если порядок полей другой.

## Do-No-Harm

- **Decision:** writers по-прежнему `insert` отдельных ключей (уже так). Добавить `processTableRaw` в `RecipeData`, чтобы любой full rewrite копировал строку. Regression: после `updateIngredient` / rename ключ на месте. Invalid JSON не `remove()` ключ.
- **Rationale:** codec сегодня не читает `processTable`; полный `RecipeData` → Yjs потерял бы поле.
- **Alternatives:** не класть в `RecipeData`, фильтр в каждом writer — легко забыть.

## Merge

- **Decision:** UI-only `ProcessTableMatrixBuilder`. Хранение булево. Span = подряд filled; текст `cellTitles` на первой строке span.
- **Rationale:** web canon. Sanitize на сервере, native не дописывает смеси.
- **Alternatives:** пререндер HTML с web — WebView запрещён конституцией.

## Rebuild REST

- **Decision:** `APIClient.rebuildProcessTable(recipeId:)` рядом с `calculateNutrition`. ViewModel по образцу `RecipeNutritionRecalculationModel`, но 404/500 → тост (не swallow). Single-flight, capture `recipeId` + `userId` + generation.
- **Rationale:** spec FR-015 vs nutrition, который глотает ошибки.
- **Alternatives:** fire-and-forget как import — endpoint **ждёт** LLM.

## Чекбоксы

- **Decision:** in-memory `CookingSession`, сброс на dismiss / logout. Не UserDefaults.
- **Rationale:** web sessionStorage.
- **Alternatives:** persist до смены рецепта — расходится с «закрыл вкладку — сбросил».

## Точка входа vs 056

- **Decision:** одна кнопка `recipe.process-table.toggle.start`. Ключ `cooking.start-button` не вводить.
- **Rationale:** clarification 074 owns Cook.
- **Alternatives:** две кнопки — отвергнуто.

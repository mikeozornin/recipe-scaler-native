# Задачи: иллюстрации ингредиентов на iOS

Чеклист по [plan.md](./plan.md). Зачёркивать по факту выполнения.

## Spec Kit

- [x] `spec.md`
- [x] `plan.md`
- [x] `tasks.md`
- [x] `contracts/yjs-ingredient-illustration.md`
- [x] `contracts/ingredient-grid-thumb.md`
- [ ] `layout.md` — черновик (iPhone only)
- [ ] `layout-audit.json`
- [ ] Ревью `layout.md` человеком → можно кодить picker/thumb

## Фаза 1 — Sync, Core, Yjs

### Sync script

- [x] `scripts/sync-ingredient-illustrations.mjs` (env `WEB_ROOT=../recipe-scaler-web` или аргумент)
- [x] Генерация `RecipeScalerCore/Resources/ingredient-catalog.json` из `registry.json` (`status: ready`)
- [x] Генерация `RecipeScalerCore/Resources/ingredient-catalog.manifest.json` (`catalogVersion`, `readyEntryCount`, `thumbPixelSize: 120`)
- [x] Копирование `ingredients/web/{id}.jpg` → `RecipeScalerNative/Resources/IngredientIllustrations/`
- [ ] Режим `--check`: counts + hash без записи (для CI)
- [x] Добавить файлы в `RecipeScalerNative.xcodeproj` (Core resources + image folder reference)
- [x] Прогон sync локально; ~339 JPEG в app bundle

### RecipeScalerCore

- [x] `IngredientIllustrationCatalogEntry` + decode JSON
- [x] `IngredientIllustrationCatalog`: `load()`, `entryCount`, `contains(id:)`, `label(id:locale:)`
- [x] `SearchNormalization` (NFKD strip + lower) — порт логики `shared/utils/search-utils.ts`
- [x] `search(query:locale:)` — trim, tokenize (кавычки), AND по normalized haystack (ru+en labels/aliases/id)
- [x] Сортировка результатов: primary label locale, then `id`
- [x] `IngredientIllustrationLayoutMetrics` — `displaySlotPt = 40`, corner radius 6 pt
- [x] `IngredientIllustrationNameMatcher` — lazy-resolve parity с веб-matcher

### Тесты Core (в `RecipeScalerNativeTests` или новый target при необходимости)

- [x] `IngredientIllustrationCatalogTests` — loads bundled JSON, `entryCount == manifest.readyEntryCount`
- [x] Search: NFKD / multi-token (catalog tests)
- [x] `IngredientIllustrationNameMatcherTests` — ru/en name → slug

### Yjs / модель

- [x] `IngredientData`: `illustrationId`, `illustrationPickerCleared`; helpers `withIllustrationBinding(...)`
- [x] `RecipeYjsCodec.parseIngredientMap` + `parseJSONIngredients` — read keys
- [x] `RecipeYjsWriter.writeIngredient` — write/remove keys
- [x] `IngredientIllustrationBindingPersistenceTests` — round-trip illustration fields
- [x] `DocumentManager` + `RecipeYjsWriter`: partial illustration binding updates

## Фаза 2 — Thumb + сетка (view/edit display)

### Assets / image store

- [x] `IngredientBowlIcon` (SwiftUI) — parity веб Bowl ~22 pt in 40 pt slot
- [x] `IngredientIllustrationImageStore` — bundle lookup `{id}.jpg`, nil → Bowl
- [x] Invalid/unknown id per `catalog.contains` → Bowl

### UI components

- [x] `IngredientIllustrationThumb` — white rounded background, decorative vs button mode
- [x] Thumb top inset: cancel row chrome padding (parity recipe list preview)
- [x] `AccessibilityIdentifiers` — `ingredient_icon`, picker keys

### Сетка

- [x] `RecipeRowLayoutMetrics.illustrationSlotWidth` = 40
- [x] `IngredientIllustrationSlot` — thumb / empty / «+»
- [x] `YDocIngredientViewRow` — thumb + `illustrationId` from model
- [x] Edit rows в `YDocIngredientsSection` — interactive thumb → picker
- [x] Убрать нумерацию для qty rows (headers unchanged)

### i18n

- [x] `Localizable.xcstrings`: picker / icon keys (ru+en)
- [x] `LocalizationConsistencyTests`

### Verify

- [x] `xcodebuild build` / `scripts/test-fast.sh`
- [x] Симулятор: lazy-resolve + bundled thumbs

## Фаза 3 — Picker (edit)

- [x] `IngredientIllustrationPickerSheet` — `.appOpaqueSheetPresentation`, search → `catalog.search`
- [x] LazyVGrid, thumb + label, clear
- [x] Edit row: thumb `Button` → sheet; header rows excluded
- [x] `YDocRecipeDetailView` / edit VM: picker target, `DocumentManager` bindings
- [x] `IngredientIllustrationLazyResolve` на detail (view/edit display)

### Verify

- [x] Unit: `IngredientIllustrationBindingPersistenceTests`
- [x] Симулятор: edit → tap icon → search → select
- [ ] `bash scripts/audit-ui-layout.sh specs/043-ingredient-illustrations` (ждёт `layout.md` + audit)

## Фаза 4 — Docs

- [x] `docs/ARCHITECTURE.md` — ingredient `illustrationId`, bundled catalog, Core vs app split
- [ ] Упоминание sync script в `docs/AGENT-WORKFLOW.md` (опционально, одна строка)

## Фаза 5 — P2 (после закрытия P1)

- [ ] `DiscoverRecipeView` — reuse thumb in read-only ingredients
- [ ] Shopping: read `illustrationId` on item snapshot; thumb in row
- [ ] Add-from-recipe: copy `illustrationId` from `IngredientData` if missing today
- [ ] Build + smoke shopping list
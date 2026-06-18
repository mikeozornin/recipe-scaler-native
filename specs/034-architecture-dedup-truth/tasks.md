# Tasks: Architecture dedup & truth cleanup

## #26 — SwiftData cleanup

- [x] Извлечь StepsSection + IngredientRow + ScaleFactorControl в `Views/RecipeStepsSection.swift`
- [x] Извлечь DisplayIngredient в `Models/YDoc/DisplayIngredient.swift`
- [x] Удалить `Views/RecipeDetailView.swift` (git rm)
- [x] Удалить `Models/Recipe.swift` (git rm)
- [x] Удалить `Models/Ingredient.swift` (git rm)
- [x] Удалить `Models/ApiCacheEntry.swift` (git rm)
- [x] Обновить Schema в `RecipeScalerNativeApp.swift` → `[RecipeTimer.self]`
- [x] Обновить `ContentView.swift` #Preview → `RecipeTimer.self`
- [x] Убрать `import SwiftData` из `RecipeListViewModel.swift`
- [x] Обновить `TestSupport.swift` — только `RecipeTimer.self`
- [x] Удалить `testRecipeListView` и `testRecipeDetailView` из `SnapshotTests.swift`
- [x] Удалить `testRecipeHasSteps` из `RecipeScalerNativeTests.swift`
- [x] Обновить pbxproj — удалить dead entries, добавить новые файлы
- [x] Build verify — все 3 scheme green
- [x] Обновить docs: ARCHITECTURE.md, SETUP.md, PROJECT_STATUS.md, specs/001/

## #23 — Validator + Localizer dedup

- [x] Расширить Core `ImportPhotoItem`: Identifiable, byteCount, convenience init
- [x] Расширить Core `ImportErrorLocalizer`: per-recipe, servings, translate helper, locale:
- [x] Удалить Native `ImportPhotoValidator.swift` (мёртвый код, не в pbxproj)
- [x] Удалить Native `ImportErrorLocalizer.swift` (мёртвый код, не в pbxproj)
- [x] Обновить `ImportRecipeSheet.swift` — `locale: AppLanguagePreference.current.locale`
- [x] Обновить комментарий в `ImportLimitsConsistencyTests.swift`
- [x] Очистить stale `UI/.DS_Store` exclude в `Package.swift`
- [x] Build verify — все 3 scheme green
- [x] Test verify — PluralizationTests, ImportLimitsConsistencyTests, ShareContentClassifierTests green

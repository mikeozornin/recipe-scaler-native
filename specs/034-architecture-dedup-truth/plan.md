# Plan: Architecture dedup & truth cleanup

**Date**: 2026-06-18 | **Spec**: [spec.md](./spec.md)

## Очерёдность

1. **#26** (schema cleanup) — безопасно, нет production-writers
2. **#23** (validator dedup) — публичные типы, миграция callers

## #26 — SwiftData cleanup

### Изменения

| Файл | Действие |
|------|----------|
| `Views/RecipeStepsSection.swift` | **Создан** — StepsSection + IngredientRow + ScaleFactorControl + IngredientsSection |
| `Models/YDoc/DisplayIngredient.swift` | **Создан** — DisplayIngredient |
| `Views/RecipeDetailView.swift` | **Удалён** (git rm) |
| `Models/Recipe.swift` | **Удалён** (git rm) |
| `Models/Ingredient.swift` | **Удалён** (git rm) |
| `Models/ApiCacheEntry.swift` | **Удалён** (git rm) |
| `RecipeScalerNativeApp.swift` | Schema → `[RecipeTimer.self]` |
| `ContentView.swift` | #Preview → `RecipeTimer.self` |
| `RecipeListViewModel.swift` | Убран `import SwiftData` |
| `TestSupport.swift` | Только `RecipeTimer.self` |
| `SnapshotTests.swift` | Удалены testRecipeListView, testRecipeDetailView; убран import SwiftData |
| `RecipeScalerNativeTests.swift` | Удалён testRecipeHasSteps |
| `project.pbxproj` | Удалены PBXBuildFile/PBXFileReference/group children/Sources entries для 3 моделей + RecipeDetailView; добавлены RecipeStepsSection + DisplayIngredient |
| `docs/ARCHITECTURE.md` | Раздел 4 Local Storage — RecipeTimer only |
| `docs/SETUP.md` | Models/, Views/ — обновлены |
| `PROJECT_STATUS.md` | Phase 1 — RecipeTimer only |
| `specs/001-yrs-native-read/data-model.md` | Historical note для Recipe/Ingredient SwiftData |
| `specs/001-yrs-native-read/plan.md` | Historical note в шапке |
| `specs/001-yrs-native-read/quickstart.md` | RecipeDetailView → YDocRecipeDetailView |

## #23 — Validator + Localizer dedup

### Изменения

| Файл | Действие |
|------|----------|
| `RecipeScalerCore/Import/ImportPhotoValidator.swift` | Расширен: Identifiable, byteCount, convenience init |
| `RecipeScalerCore/Import/ImportErrorLocalizer.swift` | Расширен: per-recipe, servings, translate helper, locale: параметр |
| `RecipeScalerNative/Utils/ImportPhotoValidator.swift` | **Удалён** (git rm) — был мёртвым кодом (не в pbxproj) |
| `RecipeScalerNative/Utils/ImportErrorLocalizer.swift` | **Удалён** (git rm) — был мёртвым кодом (не в pbxproj) |
| `Views/ImportRecipeSheet.swift` | `ImportErrorLocalizer.localize(error, locale:)` |
| `ImportLimitsConsistencyTests.swift` | Комментарий: 3 → 2 места (Native удалён) |
| `Package.swift` | Убран stale `UI/.DS_Store` exclude |

### Note

Native `ImportPhotoValidator.swift` и `ImportErrorLocalizer.swift` **не были в pbxproj** — они существовали только на диске и никогда не компилировались. Callers в `ImportRecipeSheet.swift` разрешали имена к Core-типам через `import RecipeScalerCore`. Удаление файлов на диске — cleanup мёртвого кода.

## Verify

- `xcodebuild build` — RecipeScalerNative, ShareExtension, ActionExtension (все 3 scheme green)
- `xcodebuild test` — PluralizationTests, ImportLimitsConsistencyTests, ShareContentClassifierTests, SnapshotTests, YrsXmlFragmentTests (все green)

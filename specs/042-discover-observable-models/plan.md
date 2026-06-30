# Plan: @Observable view models для Discover cluster + RecipeDetailShareButton

**Дата**: 2026-06-30 | **Spec**: [spec.md](./spec.md) | **Linear**: MIK-200

## Паттерн

Эталон: [RecipeNutritionRecalculationModel.swift](../../RecipeScalerNative/ViewModels/RecipeNutritionRecalculationModel.swift) — `@MainActor @Observable final class`, `init(api: APIClient)`, создаётся как `@State` во view.

`DiscoverAPI` остаётся static namespace; view models вызывают его методы, не view.

## Очерёдность

1. `LoadState.swift`
2. Пять моделей в `ViewModels/Discover/`
3. Миграция пяти view
4. `project.pbxproj`
5. Build + test + acceptance grep

## Файлы

| Создать | Назначение |
|---------|------------|
| `Utils/LoadState.swift` | Generic idle/loading/loaded/failed |
| `ViewModels/Discover/DiscoverRootModel.swift` | `fetchDiscovery()` |
| `ViewModels/Discover/DiscoverRecipeModel.swift` | public recipe + clone |
| `ViewModels/Discover/DiscoverCollectionModel.swift` | collection detail |
| `ViewModels/Discover/DiscoverPublicProfileModel.swift` | public profile |
| `ViewModels/Discover/RecipeShareModel.swift` | sharing settings для share sheet |

| Изменить | Что |
|----------|-----|
| `DiscoverRootView.swift` | `@State model`, `model.state` |
| `DiscoverRecipeView.swift` | recipe load + clone в модель |
| `DiscoverCollectionView.swift` | collection load в модель |
| `DiscoverPublicProfileView.swift` | profile load в модель |
| `RecipeDetailShareButton.swift` | `RecipeShareModel` в sheet |
| `project.pbxproj` | 6 новых файлов + группа Discover |

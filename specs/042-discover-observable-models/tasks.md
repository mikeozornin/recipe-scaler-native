# Tasks: MIK-200 — Discover observable models

## 1. Инфраструктура

- [x] T1.1 `specs/042-discover-observable-models/{spec,plan,tasks}.md`
- [x] T1.2 `RecipeScalerNative/Utils/LoadState.swift`

## 2. View models

- [x] T2.1 `DiscoverRootModel.swift`
- [x] T2.2 `DiscoverRecipeModel.swift`
- [x] T2.3 `DiscoverCollectionModel.swift`
- [x] T2.4 `DiscoverPublicProfileModel.swift`
- [x] T2.5 `RecipeShareModel.swift`

## 3. Миграция views

- [x] T3.1 `DiscoverRootView.swift`
- [x] T3.2 `DiscoverRecipeView.swift`
- [x] T3.3 `DiscoverCollectionView.swift`
- [x] T3.4 `DiscoverPublicProfileView.swift`
- [x] T3.5 `RecipeDetailShareButton.swift`

## 4. Xcode + verify

- [x] T4.1 `project.pbxproj` — 6 файлов
- [x] T4.2 Build 3 schemes + test
- [x] T4.3 `rg "DiscoverAPI|AccountAPI" RecipeScalerNative/Views/` → 0
- [x] T4.4 Smoke-test Discover tab

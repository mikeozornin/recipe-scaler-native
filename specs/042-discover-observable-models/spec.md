# Спецификация: @Observable view models для Discover cluster + RecipeDetailShareButton

**Ветка**: `042-discover-observable-models`  
**Дата**: 2026-06-30  
**Статус**: in-progress  
**Linear**: [MIK-200](https://linear.app/mikeozornin/issue/MIK-200/extract-observable-view-models-for-discover-cluster-and)  
**Зависимости**: `017-discover-enablement`, `035-architecture-di-observable` (паттерн `RecipeNutritionRecalculationModel`)

## Проблема

Четыре экрана Discover и `RecipeDetailShareButton` вызывают `DiscoverAPI.*` / `AccountAPI.fetchSharingSettings()` напрямую из View struct (в `.task` / private `load()`). Это нарушает правило SwiftUI UI Patterns: сетевые вызовы не должны жить в view-слое.

## Цель

1. Вынести загрузку данных в `@MainActor @Observable` view models с `LoadState<Value>`.
2. Убрать все ссылки на `DiscoverAPI` и `AccountAPI` из `RecipeScalerNative/Views/`.
3. Сохранить текущий UX (loading / error / loaded / pull-to-refresh).

## Non-goals

- Полный DI-refactor `DiscoverAPI` (enum → injectable struct).
- Изменения UI/layout Discover-экранов.
- Рефакторинг `YjsSyncService` (MIK-186).

## Критерии приёмки

- [ ] `RecipeScalerNative/Utils/LoadState.swift` создан.
- [ ] Пять моделей в `RecipeScalerNative/ViewModels/Discover/`.
- [ ] Четыре Discover view + `RecipeDetailShareButton` мигрированы.
- [ ] `rg "DiscoverAPI|AccountAPI" RecipeScalerNative/Views/` → 0 совпадений.
- [ ] Build + test зелёные.

## Verify

```bash
xcodebuild build -scheme RecipeScalerNative -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'
xcodebuild test -scheme RecipeScalerNative -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'
rg "DiscoverAPI|AccountAPI" RecipeScalerNative/Views/
```

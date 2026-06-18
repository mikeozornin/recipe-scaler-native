# Spec: Architecture dedup & truth cleanup (#23, #26)

**Date**: 2026-06-18 | **Status**: implemented

## Обзор

Две архитектурные очистки из review-kilo:

- **#23** — устранение дубликатов `ImportPhotoValidator` / `ImportErrorLocalizer` между Core и Native. Core становится единственным источником истины; Native-дубликаты удаляются.
- **#26** — удаление мёртвого SwiftData-кода: `Recipe`, `Ingredient`, `ApiCacheEntry` (0 production-readers, 0 `@Query`) + unreachable `RecipeDetailView`. Schema сокращается до `[RecipeTimer.self]`.

## #23 — Validator + Localizer dedup

### Проблема

Core и Native содержали раздельные типы с одинаковыми именами:
- `ImportPhotoItem` / `ImportPhotoValidator` — Core (public, Sendable+Equatable, dot-key+args) vs Native (internal, Identifiable с UUID, pluralized-string)
- `ImportErrorLocalizer` — Core (public, bundle: параметр) vs Native (internal, app-only, доп. cases: per-recipe, servings)

### Решение

1. Core `ImportPhotoItem` расширен: `Identifiable` (id: UUID = UUID()), `byteCount`, convenience init с defaults. Custom Equatable сохранён (по data+fileName).
2. Core `ValidationError` уже имел associated values — оставлен как есть.
3. Core `ImportErrorLocalizer` расширен: per-recipe failure regex, servings validation, ICU- substitution (translate helper), locale: параметр.
4. Native `ImportPhotoValidator.swift` и `ImportErrorLocalizer.swift` удалены (они не были в pbxproj — мёртвый код на диске).
5. Callers в `ImportRecipeSheet.swift` обновлены: `ImportErrorLocalizer.localize(error, locale: AppLanguagePreference.current.locale)`.

## #26 — SwiftData cleanup

### Проблема

`@Model` классы `Recipe` (24 поля), `Ingredient` (cascade relationship), `ApiCacheEntry` (dead code) — никогда не читались в production (0 `@Query`, 0 production writers). `RecipeDetailView.swift` (444 LOC) — unreachable в runtime (только #Preview + SnapshotTests).

### Решение

1. `StepsSection` + `IngredientRow` + `ScaleFactorControl` извлечены в `Views/RecipeStepsSection.swift`.
2. `DisplayIngredient` извлечён в `Models/YDoc/DisplayIngredient.swift`.
3. Удалены: `RecipeDetailView.swift`, `Models/Recipe.swift`, `Models/Ingredient.swift`, `Models/ApiCacheEntry.swift`.
4. Schema: `[RecipeTimer.self]` only.
5. Тесты: удалены `testRecipeHasSteps`, `testRecipeDetailView`, `testRecipeListView` (требовал YjsSyncService mock). `TestSupport.makeInMemoryContainer()` — только `RecipeTimer.self`.
6. Документация обновлена: ARCHITECTURE.md, SETUP.md, PROJECT_STATUS.md, specs/001/data-model.md (historical note).

## Риски

- **#23**: `ImportPhotoItem` Identifiable + Sendable + Equatable — UUID генерируется при init, Equatable по data+fileName (id исключён). Два item с одинаковыми данными имеют разные id но == true. Это соответствует прежнему Native-поведению.
- **#26**: потеря snapshot-покрытия для legacy `RecipeDetailView` (был unreachable). Замены нет; spec фиксирует.

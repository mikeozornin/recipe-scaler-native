import Foundation
import RecipeScalerCore

/// Parity with web `planLazyResolveIngredientIllustrationIds` + `applyLazyResolveIngredientIllustrationWrites`.
enum IngredientIllustrationLazyResolve {
    struct Plan: Sendable {
        let displayIngredients: [IngredientData]
        let pendingWrites: [(ingredientId: String, illustrationId: String, expectedName: String)]
    }

    /// Merges lazy auto-match preview with stored Y.Doc bindings.
    /// Persisted picker choices and clears always win over preview rows.
    static func mergeStoredIllustrationBindings(
        stored: [IngredientData],
        lazyPreview: [IngredientData]
    ) -> [IngredientData] {
        let previewById = Dictionary(uniqueKeysWithValues: lazyPreview.map { ($0.id, $0) })
        return stored.map { ingredient in
            if hasPersistedIllustrationBinding(ingredient) {
                return ingredient
            }
            return previewById[ingredient.id] ?? ingredient
        }
    }

    private static func hasPersistedIllustrationBinding(_ ingredient: IngredientData) -> Bool {
        if ingredient.illustrationPickerCleared { return true }
        guard let illustrationId = ingredient.illustrationId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !illustrationId.isEmpty
        else { return false }
        return true
    }

    static func plan(ingredients: [IngredientData]) -> Plan {
        var pendingWrites: [(String, String, String)] = []
        var displayChanged = false
        let next = ingredients.map { ing -> IngredientData in
            if let id = ing.illustrationId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
                return ing
            }
            if ing.illustrationPickerCleared {
                return ing
            }
            guard let matched = IngredientIllustrationNameMatcher.match(rawName: ing.name),
                  IngredientIllustrationCatalog.shared.contains(id: matched)
            else { return ing }

            pendingWrites.append((ing.id, matched, ing.name))
            displayChanged = true
            return ing.withIllustrationBinding(illustrationId: matched, pickerCleared: false)
        }
        return Plan(
            displayIngredients: displayChanged ? next : ingredients,
            pendingWrites: pendingWrites
        )
    }

    @MainActor
    static func applyPendingWrites(
        writes: [(ingredientId: String, illustrationId: String, expectedName: String)],
        syncService: YjsSyncService
    ) async {
        guard !writes.isEmpty else { return }
        let bindings = writes.map {
            (
                ingredientId: $0.ingredientId,
                illustrationId: $0.illustrationId,
                pickerCleared: false,
                expectedName: $0.expectedName as String?
            )
        }
        syncService.suspendRecipeRefresh()
        do {
            try await syncService.updateIngredientIllustrationBindings(bindings)
            await syncService.resumeRecipeRefresh()
        } catch {
            await syncService.resumeRecipeRefresh()
            AppLog.error(.sync, "lazy_illustration_write_failed", data: [
                "writeCount": String(writes.count),
                "error": error.localizedDescription,
            ])
        }
    }
}
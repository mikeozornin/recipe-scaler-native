import Foundation
import RecipeScalerCore

/// Parity with web `planLazyResolveIngredientIllustrationIds` + `applyLazyResolveIngredientIllustrationWrites`.
enum IngredientIllustrationLazyResolve {
    struct Plan: Sendable {
        let displayIngredients: [IngredientData]
        let pendingWrites: [(ingredientId: String, illustrationId: String, expectedName: String)]
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
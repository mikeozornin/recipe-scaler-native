import Foundation
import RecipeScalerCore

/// Owns the «nutrition may be outdated → recalculate» flow for `YDocRecipeDetailView`.
///
/// Replaces the previous in-`body` call to `APIClient.shared.calculateNutrition(...)`,
/// which violated the project architecture rule (`.shared` is a cross-process IPC
/// shim, not for view code) and could fire duplicate / racy network calls on
/// every re-render. The view constructs this model once via `.task(id: recipeId)`
/// and forwards button taps to `recalculate(recipeId:syncService:)`.
@MainActor
@Observable
final class RecipeNutritionRecalculationModel {
    /// True while a recalculation request is in flight; disables the button.
    var isCalculating = false

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    /// POST `/api/recipes/:id/calculate-nutrition`, then pull the updated doc.
    /// Errors are swallowed intentionally — the outdated banner stays until the
    /// next successful recalculation (matches the previous behavior).
    func recalculate(recipeId: String, syncService: YjsSyncService) async {
        guard !isCalculating else { return }
        isCalculating = true
        defer { isCalculating = false }
        do {
            try await api.calculateNutrition(recipeId: recipeId)
            await syncService.refreshCurrentRecipe(recipeId: recipeId)
        } catch {
            // Banner stays until next successful recalculation.
        }
    }
}

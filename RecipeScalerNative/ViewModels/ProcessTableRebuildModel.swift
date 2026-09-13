import Foundation
import RecipeScalerCore

/// Owns `POST /api/recipes/:id/rebuild-process-table` for recipe detail / cooking.
@MainActor
@Observable
final class ProcessTableRebuildModel {
    var isRebuilding = false

    private let api: APIClient
    private var generation = 0
    private var inFlight: Task<Void, Never>?
    var rebuildOverride: ((String) async throws -> Void)?

    init(api: APIClient) {
        self.api = api
    }

    static func makePreview() -> ProcessTableRebuildModel {
        ProcessTableRebuildModel(api: APIClient.shared)
    }

    func cancel() {
        generation += 1
        inFlight?.cancel()
        inFlight = nil
        isRebuilding = false
    }

    func rebuild(recipeId: String, userId: String?, syncService: YjsSyncService?) {
        guard !isRebuilding else { return }
        let capturedRecipeId = recipeId
        let capturedUserId = userId
        generation += 1
        let capturedGeneration = generation
        isRebuilding = true
        inFlight?.cancel()
        inFlight = Task { [weak self] in
            guard let self else { return }
            defer {
                if capturedGeneration == self.generation {
                    self.isRebuilding = false
                }
            }
            do {
                if let rebuildOverride {
                    try await rebuildOverride(capturedRecipeId)
                } else {
                    try await self.api.rebuildProcessTable(recipeId: capturedRecipeId)
                }
                try Task.checkCancellation()
                guard capturedGeneration == self.generation else { return }
                if let syncService {
                    guard capturedUserId == syncService.currentUserId else { return }
                    await syncService.refreshCurrentRecipe(recipeId: capturedRecipeId)
                }
            } catch is CancellationError {
                return
            } catch {
                guard capturedGeneration == self.generation else { return }
                if let syncService {
                    guard capturedUserId == syncService.currentUserId else { return }
                }
                let message = Bundle.currentLocalizedString("recipe.process-table.recalculate-error")
                ShoppingFeedback.postStatus(message, symbolName: "exclamationmark.triangle")
                AppLog.debug(.sync, "process table rebuild failed: \(error.localizedDescription)")
            }
        }
    }
}

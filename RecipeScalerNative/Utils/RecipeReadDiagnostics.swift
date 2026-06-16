//
//  RecipeReadDiagnostics.swift
//  RecipeScalerNative
//
//  DEBUG-only NDJSON traces for `/debug` (see AgentSyncDebugLog).
//

import Foundation

#if DEBUG
enum RecipeReadDiagnostics {
    static func launchRecipeId() -> String? {
        for arg in ProcessInfo.processInfo.arguments {
            guard arg.hasPrefix("-RecipeReadDiagnostics=") else { continue }
            let id = String(arg.dropFirst("-RecipeReadDiagnostics=".count))
            return id.isEmpty ? nil : id
        }
        return nil
    }

    /// Runs after collection is available; exercises the same read path as recipe detail.
    static func runAfterCollectionLoad(
        documentManager: DocumentManager,
        userId: String
    ) async {
        guard let recipeId = launchRecipeId() else { return }

        let started = CFAbsoluteTimeGetCurrent()
        AgentSyncDebugLog.write(
            hypothesisId: "A",
            location: "RecipeReadDiagnostics.swift:runAfterCollectionLoad",
            message: "diag_start",
            data: ["recipeId": recipeId, "userId": userId]
        )

        let docKey = "\(userId):recipe:\(recipeId)"
        do {
            let t0 = CFAbsoluteTimeGetCurrent()
            _ = try await documentManager.getOrCreateDoc(key: docKey)
            AgentSyncDebugLog.write(
                hypothesisId: "B",
                location: "RecipeReadDiagnostics.swift:getOrCreateDoc",
                message: "getOrCreateDoc_done",
                data: ["ms": String(ms(since: t0))]
            )

            let collectionEntry = try? await documentManager.readCollectionEntries()
                .first { $0.id == recipeId && !$0.deleted }

            let t1 = CFAbsoluteTimeGetCurrent()
            let recipe = try await documentManager.readRecipeData(recipeId: recipeId, userId: userId)
            let readMs = ms(since: t1)
            let displayName = recipe.map { RecipeCollectionMerge.merged($0, with: collectionEntry) }?.name
            var diagData: [String: String] = [
                "ms": readMs,
                "hasRecipe": String(recipe != nil),
                "recipeDocName": recipe?.name ?? "nil",
                "collectionName": collectionEntry?.name ?? "nil",
                "collectionUpdatedAt": collectionEntry?.updatedAt ?? "nil",
                "recipeDocUpdatedAt": recipe?.updatedAt ?? "nil",
                "displayName": displayName ?? recipe?.name ?? "nil",
                "version": recipe?.version ?? "nil",
                "ingredientCount": String(recipe?.ingredients.count ?? 0),
                "descriptionLen": String(recipe?.description?.count ?? 0),
            ]
            if let html = recipe?.description {
                let doc = RecipeDescriptionParser.parse(html)
                let linkRuns = doc.blocks.flatMap { block -> [RecipeDescriptionInlineRun] in
                    switch block {
                    case .paragraph(_, let runs), .orderedStep(_, _, let runs),
                         .bullet(_, let runs), .heading(_, _, let runs):
                        return runs
                    }
                }.filter { if case .link = $0 { return true }; return false }
                let stepBlocks = doc.blocks.filter {
                    if case .orderedStep = $0 { return true }
                    return false
                }
                diagData["linkCount"] = String(linkRuns.count)
                diagData["orderedStepCount"] = String(stepBlocks.count)
                diagData["blockCount"] = String(doc.blocks.count)
            }
            AgentSyncDebugLog.write(
                hypothesisId: "C",
                location: "RecipeReadDiagnostics.swift:readRecipeData",
                message: "readRecipeData_done",
                data: diagData
            )

            AgentSyncDebugLog.write(
                hypothesisId: "A",
                location: "RecipeReadDiagnostics.swift:runAfterCollectionLoad",
                message: "diag_finish",
                data: ["totalMs": ms(since: started)]
            )
        } catch {
            AgentSyncDebugLog.write(
                hypothesisId: "E",
                location: "RecipeReadDiagnostics.swift:runAfterCollectionLoad",
                message: "diag_error",
                data: ["error": error.localizedDescription]
            )
        }
    }

    private static func ms(since start: CFAbsoluteTime) -> String {
        String(Int((CFAbsoluteTimeGetCurrent() - start) * 1000))
    }
}
#endif

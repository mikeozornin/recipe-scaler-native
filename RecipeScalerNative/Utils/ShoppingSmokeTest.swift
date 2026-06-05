//
//  ShoppingSmokeTest.swift
//  RecipeScalerNative
//
//  DEBUG simulator smoke: same code paths as UI (YjsSyncService), result in Caches for verify scripts.
//

import Foundation

#if DEBUG
enum ShoppingSmokeTest {
    @MainActor
    enum Launcher {
        private static var didStart = false

        static func launchIfNeeded(syncService: YjsSyncService, userId: String) async {
            guard shouldRun, !didStart else { return }
            didStart = true
            recordLaunchArgumentsIfNeeded()
            await syncService.prepareForShoppingSmokeTest(userId: userId)
            await run(syncService: syncService)
            await syncService.start(userId: userId)
        }
    }

    struct Result: Codable {
        var passed: Bool
        var finished: Bool
        var steps: [String: Bool]
        var itemCount: Int
        var error: String?
    }

    static var shouldRun: Bool {
        #if targetEnvironment(simulator)
        for arg in ProcessInfo.processInfo.arguments {
            if arg == "-ShoppingSmokeTest" || arg == "-ShoppingSmokeTest=1" { return true }
            if arg.hasPrefix("-ShoppingSmokeTest=") {
                let value = String(arg.dropFirst("-ShoppingSmokeTest=".count))
                return value == "1" || value.lowercased() == "true"
            }
        }
        #endif
        return false
    }

    /// Writes launch argv for verify scripts when smoke flag may be missing from ProcessInfo.
    static func writeProgress(_ step: String, itemCount: Int = 0, extra: [String: Bool] = [:]) {
        var steps = extra
        steps[step] = true
        writeResult(Result(passed: false, finished: false, steps: steps, itemCount: itemCount, error: nil))
    }

    static func recordLaunchArgumentsIfNeeded() {
        guard shouldRun else { return }
        let payload = ["arguments": ProcessInfo.processInfo.arguments]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let url = resultURL().deletingLastPathComponent().appendingPathComponent("shopping-smoke-launch.json")
        try? data.write(to: url, options: .atomic)
    }

    private static var didFinish = false

    @MainActor
    static func run(syncService: YjsSyncService) async {
        guard !didFinish else { return }
        defer {
            if !didFinish {
                writeResult(
                    Result(
                        passed: false,
                        finished: true,
                        steps: ["aborted": true],
                        itemCount: 0,
                        error: "smoke_task_cancelled"
                    )
                )
            }
        }
        AgentSyncDebugLog.sync(
            location: "ShoppingSmokeTest.swift",
            message: "shopping_smoke_start",
            data: [:]
        )
        var steps: [String: Bool] = [:]
        var lastError: String?
        var itemCount = 0

        do {
            let ready = await waitForCollection(syncService, timeoutSeconds: 30)
            steps["collectionLoaded"] = ready
            guard ready else {
                throw SmokeError.timeout("collection")
            }

            let beforeManual = syncService.shoppingSnapshot.items.count
            try await syncService.addManualShoppingItem(label: "Smoke manual item")
            await syncService.refreshShoppingSnapshotForSmokeTest()
            itemCount = syncService.shoppingSnapshot.items.count
            steps["manualAdd"] = itemCount > beforeManual
                && syncService.shoppingSnapshot.items.contains { $0.label == "Smoke manual item" }
            writeResult(Result(passed: false, finished: false, steps: steps, itemCount: itemCount, error: nil))

            if let recipeId = syncService.collectionEntries.first(where: { !$0.deleted })?.id {
                let added = try await syncService.addWholeRecipeToShoppingList(recipeId: recipeId)
                await syncService.refreshShoppingSnapshotForSmokeTest()
                itemCount = syncService.shoppingSnapshot.items.count
                steps["wholeRecipe"] = added > 0 && itemCount > beforeManual

                if let recipe = try await syncService.readRecipeDataForShopping(recipeId: recipeId),
                   RecipeEditPolicy.supportsEditFormat(version: recipe.version),
                   let ingredient = recipe.ingredients.first(where: ShoppingListFromRecipe.isIngredientEligible) {
                    let countBefore = syncService.shoppingSnapshot.items.count
                    try await syncService.addRecipeToShoppingList(
                        recipeId: recipeId,
                        recipeName: recipe.name,
                        ingredients: recipe.ingredients,
                        selectedIngredientIds: [ingredient.id]
                    )
                    await syncService.refreshShoppingSnapshotForSmokeTest()
                    itemCount = syncService.shoppingSnapshot.items.count
                    steps["singleIngredient"] = itemCount > countBefore
                } else {
                    steps["singleIngredient"] = false
                    lastError = "no eligible ingredient or non-v3 recipe"
                }
            } else {
                steps["wholeRecipe"] = false
                steps["singleIngredient"] = false
                lastError = "no recipes in collection"
            }
        } catch {
            lastError = error.localizedDescription
        }

        let passed = steps["manualAdd"] == true
            && steps["wholeRecipe"] == true
            && steps["singleIngredient"] == true

        let result = Result(
            passed: passed,
            finished: true,
            steps: steps,
            itemCount: itemCount,
            error: lastError
        )
        didFinish = true
        writeResult(result)
        AgentSyncDebugLog.sync(
            location: "ShoppingSmokeTest.swift",
            message: "shopping_smoke_done",
            data: [
                "passed": String(passed),
                "itemCount": String(itemCount),
                "steps": steps.map { "\($0.key)=\($0.value)" }.joined(separator: ","),
                "error": lastError ?? "",
            ]
        )
    }

    private enum SmokeError: LocalizedError {
        case timeout(String)

        var errorDescription: String? {
            switch self {
            case .timeout(let what): return "Timeout waiting for \(what)"
            }
        }
    }

    @MainActor
    private static func waitForCollection(_ syncService: YjsSyncService, timeoutSeconds: Int) async -> Bool {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            if !syncService.collectionEntries.filter({ !$0.deleted }).isEmpty {
                return true
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    private static func writeResult(_ result: Result) {
        guard let data = try? JSONEncoder().encode(result) else { return }
        let url = resultURL()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    static func resultURL() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("shopping-smoke-result.json")
    }
}
#endif
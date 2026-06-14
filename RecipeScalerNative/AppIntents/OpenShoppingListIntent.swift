//
//  OpenShoppingListIntent.swift
//  RecipeScalerNative
//

import AppIntents

struct OpenShoppingListIntent: AppIntent {
    static var title: LocalizedStringResource = "Open shopping list"
    static var description = IntentDescription("Opens the shopping list in Recipe Scaler.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await DeepLinkRouter.shared.handle(.openShoppingList)
        return .result()
    }
}

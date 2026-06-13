//
//  AddToShoppingListIntent.swift
//  RecipeScalerNative
//

import AppIntents

struct AddToShoppingListIntent: AppIntent {
    static var title: LocalizedStringResource = "Add to shopping list"
    static var description = IntentDescription("Adds an item to your Recipe Scaler shopping list.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Item", description: "The item to add, e.g. 'milk'.")
    var item: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let label = item.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else {
            throw ShoppingIntentError.emptyItem
        }
        ShoppingIntentActionQueue.enqueue(.addItem(label: label))
        return .result(dialog: "Adding \(label) to your shopping list.")
    }
}

private enum ShoppingIntentError: Error, CustomLocalizedStringResourceConvertible {
    case emptyItem
    var localizedStringResource: LocalizedStringResource {
        "Please specify what you'd like to add."
    }
}

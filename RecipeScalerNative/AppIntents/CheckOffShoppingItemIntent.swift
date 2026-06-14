//
//  CheckOffShoppingItemIntent.swift
//  RecipeScalerNative
//

import AppIntents

struct CheckOffShoppingItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Check off shopping item"
    static var description = IntentDescription("Marks an item in your shopping list as purchased.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Item", description: "The exact name of the shopping item to check off.")
    var item: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let query = item.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            throw CheckOffIntentError.emptyItem
        }

        let snapshot = ShoppingListSnapshotStore.load()
        guard let match = snapshot.items.first(where: {
            !$0.purchased && $0.label.localizedLowercase == query.localizedLowercase
        }) else {
            return .result(dialog: "I couldn't find \"\(query)\" in your shopping list.")
        }

        ShoppingIntentActionQueue.enqueue(.checkOff(id: match.id))
        return .result(dialog: "Checked off \(match.label).")
    }
}

private enum CheckOffIntentError: Error, CustomLocalizedStringResourceConvertible {
    case emptyItem
    var localizedStringResource: LocalizedStringResource {
        "Please specify the item you'd like to check off."
    }
}

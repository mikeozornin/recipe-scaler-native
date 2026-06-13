//
//  RecipeScalerShortcuts.swift
//  RecipeScalerNative
//
//  Russian translations for Siri phrases should be added to AppShortcuts.xcstrings
//  after the first build (Xcode generates the base file from this provider).
//

import AppIntents

struct RecipeScalerShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .orange

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartTimerIntent(),
            phrases: [
                "Start a \(.applicationName) cooking timer",
                "Set a \(.applicationName) timer",
            ],
            shortTitle: "Start timer",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: AddToShoppingListIntent(),
            phrases: [
                "Add to my \(.applicationName) shopping list",
            ],
            shortTitle: "Add to shopping list",
            systemImageName: "cart.badge.plus"
        )
        AppShortcut(
            intent: OpenRecipeIntent(),
            phrases: [
                "Open \(\.$recipe) in \(.applicationName)",
                "Show \(\.$recipe) in \(.applicationName)",
            ],
            shortTitle: "Open recipe",
            systemImageName: "book.fill"
        )
    }
}

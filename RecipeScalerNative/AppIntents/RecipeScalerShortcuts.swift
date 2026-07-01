//
//  RecipeScalerShortcuts.swift
//  RecipeScalerNative
//
//  Spotlight Top Hit: parameterless shortcuts only (open screen or fixed preset).
//  Other AppIntent types remain in Shortcuts / Siri via the action library.
//  Russian translations for Siri phrases — AppShortcuts.xcstrings.
//

import AppIntents

struct RecipeScalerShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .orange

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenShoppingListIntent(),
            phrases: [
                "Open my \(.applicationName) shopping list",
                "Show my \(.applicationName) shopping list",
            ],
            shortTitle: "Shopping list",
            systemImageName: "cart"
        )
        AppShortcut(
            intent: {
                var intent = StartTimerIntent()
                intent.minutes = 10
                return intent
            }(),
            phrases: [
                "Start a 10 minute \(.applicationName) timer",
                "Set a 10 minute \(.applicationName) timer",
            ],
            shortTitle: "10 min timer",
            systemImageName: "timer"
        )
    }
}

//
//  AssistantToolStatusI18n.swift
//  RecipeScalerNative
//
//  Maps assistant tool names to localized status keys (subset of web assistant-tool-status.ts).
//

import Foundation

enum AssistantToolStatusI18n {
    static func localizationKey(for toolName: String) -> String {
        switch toolName {
        case "search_recipes", "list_recipes":
            return "assistant.tool-status.search-recipes"
        case "get_recipe", "get_recipe_human":
            return "assistant.tool-status.open-recipe"
        case "scale_recipe":
            return "assistant.tool-status.scale-recipe"
        case "add_to_shopping_list", "add_recipe_to_shopping_list":
            return "assistant.tool-status.add-to-shopping-list"
        case "create_recipe_from_url", "create_recipe_from_text":
            return "assistant.tool-status.create-recipe-from-text"
        default:
            return "assistant.tool-status.generic"
        }
    }

    static func localizedStatus(for toolName: String) -> String {
        Bundle.currentLocalizedString(localizationKey(for: toolName))
    }
}

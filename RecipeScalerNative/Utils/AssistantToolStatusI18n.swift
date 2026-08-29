//
//  AssistantToolStatusI18n.swift
//  RecipeScalerNative
//
//  Maps assistant tool names to localized status keys (1:1 with web assistant-tool-status.ts).
//

import Foundation

enum AssistantToolStatusI18n {
    static func localizationKey(for toolName: String) -> String {
        switch toolName {
        case "search_recipes", "list_recipes":
            return "assistant.tool-status.search-recipes"
        case "get_recipe", "get_recipe_human":
            return "assistant.tool-status.open-recipe"
        case "get_current_user":
            return "assistant.tool-status.load-profile"
        case "scale_recipe":
            return "assistant.tool-status.scale-recipe"
        case "create_recipe_from_url":
            return "assistant.tool-status.create-recipe-from-url"
        case "create_recipe_from_text":
            return "assistant.tool-status.create-recipe-from-text"
        case "get_recipe_url":
            return "assistant.tool-status.get-recipe-url"
        case "render_widget":
            return "assistant.tool-status.render-widget"
        case "add_to_shopping_list":
            return "assistant.tool-status.add-to-shopping-list"
        case "add_recipe_to_shopping_list":
            return "assistant.tool-status.add-recipe-to-shopping-list"
        case "delete_recipe":
            return "assistant.tool-status.delete-recipe"
        case "update_recipe", "update_description":
            return "assistant.tool-status.update-recipe"
        case "add_ingredients_bulk", "update_ingredient", "delete_ingredient":
            return "assistant.tool-status.update-ingredients"
        case "set_recipe_public_status":
            return "assistant.tool-status.set-public"
        case "start_timer", "resume_timer":
            return "assistant.tool-status.start-timer"
        case "stop_timer", "pause_timer":
            return "assistant.tool-status.stop-timer"
        case "list_timers":
            return "assistant.tool-status.list-timers"
        case "get_shopping_list":
            return "assistant.tool-status.get-shopping-list"
        case "clear_shopping_list":
            return "assistant.tool-status.clear-shopping-list"
        case "change_shopping_items_status":
            return "assistant.tool-status.change-items-status"
        case "vkusvill_search_products":
            return "assistant.tool-status.vkusvill-search-products"
        case "vkusvill_create_cart_link":
            return "assistant.tool-status.vkusvill-create-cart-link"
        default:
            return "assistant.tool-status.generic"
        }
    }

    static func localizedStatus(for toolName: String) -> String {
        Bundle.currentLocalizedString(localizationKey(for: toolName))
    }
}

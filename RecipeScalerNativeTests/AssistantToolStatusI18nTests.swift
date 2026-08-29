//
//  AssistantToolStatusI18nTests.swift
//  RecipeScalerNativeTests
//
//  Parity with web assistant-tool-status.ts (spec 073).
//

import XCTest
@testable import RecipeScalerNative

final class AssistantToolStatusI18nTests: XCTestCase {
    func testKnownToolNamesMapToDistinctKeys() {
        let cases: [(String, String)] = [
            ("search_recipes", "assistant.tool-status.search-recipes"),
            ("list_recipes", "assistant.tool-status.search-recipes"),
            ("get_recipe", "assistant.tool-status.open-recipe"),
            ("get_current_user", "assistant.tool-status.load-profile"),
            ("scale_recipe", "assistant.tool-status.scale-recipe"),
            ("create_recipe_from_url", "assistant.tool-status.create-recipe-from-url"),
            ("create_recipe_from_text", "assistant.tool-status.create-recipe-from-text"),
            ("render_widget", "assistant.tool-status.render-widget"),
            ("add_to_shopping_list", "assistant.tool-status.add-to-shopping-list"),
            ("add_recipe_to_shopping_list", "assistant.tool-status.add-recipe-to-shopping-list"),
            ("delete_recipe", "assistant.tool-status.delete-recipe"),
            ("update_recipe", "assistant.tool-status.update-recipe"),
            ("add_ingredients_bulk", "assistant.tool-status.update-ingredients"),
            ("set_recipe_public_status", "assistant.tool-status.set-public"),
            ("start_timer", "assistant.tool-status.start-timer"),
            ("pause_timer", "assistant.tool-status.stop-timer"),
            ("list_timers", "assistant.tool-status.list-timers"),
            ("get_shopping_list", "assistant.tool-status.get-shopping-list"),
            ("clear_shopping_list", "assistant.tool-status.clear-shopping-list"),
            ("change_shopping_items_status", "assistant.tool-status.change-items-status"),
            ("vkusvill_search_products", "assistant.tool-status.vkusvill-search-products"),
            ("vkusvill_create_cart_link", "assistant.tool-status.vkusvill-create-cart-link"),
        ]

        for (toolName, expectedKey) in cases {
            XCTAssertEqual(
                AssistantToolStatusI18n.localizationKey(for: toolName),
                expectedKey,
                "Unexpected i18n key for \(toolName)"
            )
        }
    }

    func testUnknownToolNameUsesGenericKey() {
        XCTAssertEqual(
            AssistantToolStatusI18n.localizationKey(for: "unknown_future_tool"),
            "assistant.tool-status.generic"
        )
    }

    func testOptimisticToolStatusMessageShape() {
        let message = AssistantMessage.optimisticToolStatus(toolName: "search_recipes")
        XCTAssertTrue(message.id.hasPrefix("optimistic-tool-status-"))
        XCTAssertEqual(message.role, "assistant")
        XCTAssertTrue(message.isToolStatusRow)
        XCTAssertFalse(message.isProcessingPlaceholder)
        XCTAssertEqual(message.metadata?.toolStatus?.toolName, "search_recipes")
    }

    func testProcessingPlaceholderDetection() {
        var streaming = AssistantMessage(
            id: "optimistic-assistant-1",
            role: "assistant",
            text: "",
            isStreaming: true,
            metadata: nil,
            createdAt: Date()
        )
        XCTAssertTrue(streaming.isProcessingPlaceholder)

        streaming.text = "Hello"
        XCTAssertFalse(streaming.isProcessingPlaceholder)
    }

    func testOptimisticIDDetectionAndCleanupPredicate() {
        XCTAssertTrue(AssistantMessage.isOptimisticID("optimistic-user-abc"))
        XCTAssertTrue(AssistantMessage.isOptimisticID("optimistic-assistant-abc"))
        XCTAssertTrue(AssistantMessage.isOptimisticID("optimistic-tool-status-abc"))
        XCTAssertFalse(AssistantMessage.isOptimisticID("error-abc"))
        XCTAssertFalse(AssistantMessage.isOptimisticID("server-msg-123"))

        let messages = [
            AssistantMessage.optimisticToolStatus(toolName: "search_recipes"),
            AssistantMessage(
                id: "optimistic-user-1",
                role: "user",
                text: "Hi",
                isStreaming: false,
                metadata: nil,
                createdAt: Date()
            ),
            AssistantMessage(
                id: "optimistic-assistant-1",
                role: "assistant",
                text: "",
                isStreaming: true,
                metadata: nil,
                createdAt: Date()
            ),
            AssistantMessage(
                id: "error-1",
                role: "assistant",
                text: "Failed",
                isStreaming: false,
                metadata: nil,
                createdAt: Date()
            ),
        ]
        let remaining = messages.filter { !AssistantMessage.isOptimisticID($0.id) }
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, "error-1")
    }
}

//
//  DeepLinkRouterTests.swift
//
//  Spec 025-share-extension T028 — URL scheme parsing for recipe-scaler://.
//

import XCTest
@testable import RecipeScalerNative

@MainActor
final class DeepLinkRouterTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        // Clear pending state before each test.
        DeepLinkRouter.shared.clear()
    }

    // MARK: - URL scheme parsing

    func test_validRecipeURL_setsOpenRecipePending() {
        let id = "11111111-2222-3333-4444-555555555555"
        let url = URL(string: "recipe-scaler://recipe/\(id)")!

        DeepLinkRouter.handle(url)

        XCTAssertEqual(DeepLinkRouter.shared.pending, .openRecipe(recipeId: id))
    }

    func test_uppercaseUUID_isAcceptedAndNormalized() {
        let raw = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        let url = URL(string: "recipe-scaler://recipe/\(raw)")!

        DeepLinkRouter.handle(url)

        let normalized = UUID(uuidString: raw)!.uuidString.lowercased()
        XCTAssertEqual(DeepLinkRouter.shared.pending, .openRecipe(recipeId: normalized))
    }

    func test_wrongScheme_isIgnored() {
        let id = "11111111-2222-3333-4444-555555555555"
        let url = URL(string: "https://recipe/\(id)")!

        DeepLinkRouter.handle(url)

        XCTAssertNil(DeepLinkRouter.shared.pending)
    }

    func test_wrongHost_isIgnored() {
        let id = "11111111-2222-3333-4444-555555555555"
        let url = URL(string: "recipe-scaler://shopping/\(id)")!

        DeepLinkRouter.handle(url)

        XCTAssertNil(DeepLinkRouter.shared.pending)
    }

    func test_nonUUIDPath_isIgnored() {
        // recipe-scaler://recipe/not-a-uuid
        let url = URL(string: "recipe-scaler://recipe/not-a-uuid")!

        DeepLinkRouter.handle(url)

        XCTAssertNil(DeepLinkRouter.shared.pending)
    }

    // MARK: - pending lifecycle

    func test_clear_setsPendingToNil() {
        let id = "11111111-2222-3333-4444-555555555555"
        DeepLinkRouter.shared.handle(.openRecipe(recipeId: id))
        XCTAssertNotNil(DeepLinkRouter.shared.pending)

        DeepLinkRouter.shared.clear()

        XCTAssertNil(DeepLinkRouter.shared.pending)
    }

    // MARK: - consumePendingRecipeId (legacy UserDefaults path)

    func test_consumePendingRecipeId_returnsAndClears() {
        let id = "legacy-id-\(UUID().uuidString)"
        UserDefaults.standard.set(id, forKey: DeepLinkRouter.pendingRecipeIdKey)

        let consumed = DeepLinkRouter.consumePendingRecipeId()
        XCTAssertEqual(consumed, id)

        // Second call returns nil (idempotent clear).
        let again = DeepLinkRouter.consumePendingRecipeId()
        XCTAssertNil(again)
    }

    func test_consumePendingRecipeId_returnsNilWhenEmpty() {
        UserDefaults.standard.removeObject(forKey: DeepLinkRouter.pendingRecipeIdKey)
        XCTAssertNil(DeepLinkRouter.consumePendingRecipeId())
    }
}

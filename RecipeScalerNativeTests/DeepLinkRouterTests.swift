//
//  DeepLinkRouterTests.swift
//
//  Spec 025 — URL scheme parsing for recipe-scaler://.
//  Spec 059 — Universal Links https://recipe-scaler.ru/public/@/...
//

import XCTest
@testable import RecipeScalerNative

@MainActor
final class DeepLinkRouterTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        // Clear pending state before each test.
        DeepLinkRouter.shared.clear()
        // Reset the double-delivery guard (spec 059 architecture finding #2).
        DeepLinkRouter._resetLastHandledURLForTesting()
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

    func test_unrelatedHTTPS_isIgnored() {
        let id = "11111111-2222-3333-4444-555555555555"
        let url = URL(string: "https://example.com/recipe/\(id)")!

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
        let url = URL(string: "recipe-scaler://recipe/not-a-uuid")!

        DeepLinkRouter.handle(url)

        XCTAssertNil(DeepLinkRouter.shared.pending)
    }

    // MARK: - Universal Links (spec 059)

    func test_universalLink_publicProfile_setsPending() {
        let url = URL(string: "https://recipe-scaler.ru/public/@/alice")!

        DeepLinkRouter.handle(url)

        XCTAssertEqual(DeepLinkRouter.shared.pending, .openPublicProfile(username: "alice"))
    }

    func test_universalLink_publicRecipe_setsPending() {
        let id = "11111111-2222-3333-4444-555555555555"
        let url = URL(string: "https://recipe-scaler.ru/public/@/alice/\(id)")!

        DeepLinkRouter.handle(url)

        XCTAssertEqual(
            DeepLinkRouter.shared.pending,
            .openPublicRecipe(recipeId: id, username: "alice")
        )
    }

    func test_universalLink_wwwHost_accepted() {
        let url = URL(string: "https://www.recipe-scaler.ru/public/@/bob")!

        DeepLinkRouter.handle(url)

        XCTAssertEqual(DeepLinkRouter.shared.pending, .openPublicProfile(username: "bob"))
    }

    func test_universalLink_legacyPublicRecipe_ignored() {
        let id = "11111111-2222-3333-4444-555555555555"
        let url = URL(string: "https://recipe-scaler.ru/public/\(id)")!

        DeepLinkRouter.handle(url)

        XCTAssertNil(DeepLinkRouter.shared.pending)
    }

    func test_universalLink_shoppingList_ignored() {
        let url = URL(string: "https://recipe-scaler.ru/public/shopping-list/abc123")!

        DeepLinkRouter.handle(url)

        XCTAssertNil(DeepLinkRouter.shared.pending)
    }

    func test_universalLink_nonUUIDRecipe_ignored() {
        let url = URL(string: "https://recipe-scaler.ru/public/@/alice/not-a-uuid")!

        DeepLinkRouter.handle(url)

        XCTAssertNil(DeepLinkRouter.shared.pending)
    }

    func test_universalLink_wrongHost_ignored() {
        let url = URL(string: "https://evil.example/public/@/alice")!

        DeepLinkRouter.handle(url)

        XCTAssertNil(DeepLinkRouter.shared.pending)
    }

    func test_parse_doesNotMutatePending() {
        let url = URL(string: "https://recipe-scaler.ru/public/@/alice")!
        let link = DeepLinkRouter.parse(url)
        XCTAssertEqual(link, .openPublicProfile(username: "alice"))
        XCTAssertNil(DeepLinkRouter.shared.pending)
    }

    /// Spec 059 architecture finding #2 — double delivery (onOpenURL +
    /// NSUserActivityTypeBrowsingWeb) of the same URL must not re-trigger.
    func test_handle_sameURLTwice_isIdempotent() {
        let url = URL(string: "https://recipe-scaler.ru/public/@/alice")!

        DeepLinkRouter.handle(url)
        let firstPending = DeepLinkRouter.shared.pending
        XCTAssertEqual(firstPending, .openPublicProfile(username: "alice"))
        DeepLinkRouter.shared.clear()

        // Simulate iOS firing the same UL again via the second callback.
        DeepLinkRouter.handle(url)

        XCTAssertNil(DeepLinkRouter.shared.pending,
                     "Second delivery of the same URL must not re-queue a pending link")
    }

    /// Spec 059 architecture finding #2 — a different URL after the first
    /// still routes normally (guard is equality, not "any subsequent").
    func test_handle_differentURL_afterFirst_isRouted() {
        let first = URL(string: "https://recipe-scaler.ru/public/@/alice")!
        let second = URL(string: "https://recipe-scaler.ru/public/@/bob")!

        DeepLinkRouter.handle(first)
        XCTAssertEqual(DeepLinkRouter.shared.pending, .openPublicProfile(username: "alice"))
        DeepLinkRouter.shared.clear()

        DeepLinkRouter.handle(second)
        XCTAssertEqual(DeepLinkRouter.shared.pending, .openPublicProfile(username: "bob"))
    }

    // MARK: - pending lifecycle

    func test_clear_setsPendingToNil() {
        let id = "11111111-2222-3333-4444-555555555555"
        DeepLinkRouter.shared.handle(.openRecipe(recipeId: id))
        XCTAssertNotNil(DeepLinkRouter.shared.pending)

        DeepLinkRouter.shared.clear()

        XCTAssertNil(DeepLinkRouter.shared.pending)
    }

    // MARK: - file:// URL handling (spec 057)

    func test_fileURL_setsOpenRecipeFilePending() {
        let url = URL(fileURLWithPath: "/tmp/incoming.recipe")
        DeepLinkRouter.shared.handle(.openRecipeFile(url))
        XCTAssertEqual(DeepLinkRouter.shared.pending, .openRecipeFile(url))
    }

    func test_handle_fileURL_routesToOpenRecipeFile() {
        let url = URL(fileURLWithPath: "/tmp/incoming.recipe")
        DeepLinkRouter.shared.handle(.openRecipeFile(url))
        XCTAssertEqual(DeepLinkRouter.shared.pending, .openRecipeFile(url))
    }

    func test_handle_recipeSchemeURL_doesNotRouteFileURLs() {
        let id = "11111111-2222-3333-4444-555555555555"
        let url = URL(string: "recipe-scaler://recipe/\(id)")!
        DeepLinkRouter.handle(url)
        XCTAssertEqual(DeepLinkRouter.shared.pending, .openRecipe(recipeId: id))
    }

    // MARK: - consumePendingRecipeId (legacy UserDefaults path)

    func test_consumePendingRecipeId_returnsAndClears() {
        let id = "legacy-id-\(UUID().uuidString)"
        UserDefaults.standard.set(id, forKey: DeepLinkRouter.pendingRecipeIdKey)

        let consumed = DeepLinkRouter.consumePendingRecipeId()
        XCTAssertEqual(consumed, id)

        let again = DeepLinkRouter.consumePendingRecipeId()
        XCTAssertNil(again)
    }

    func test_consumePendingRecipeId_returnsNilWhenEmpty() {
        UserDefaults.standard.removeObject(forKey: DeepLinkRouter.pendingRecipeIdKey)
        XCTAssertNil(DeepLinkRouter.consumePendingRecipeId())
    }
}

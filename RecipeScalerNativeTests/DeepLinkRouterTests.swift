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

    func test_universalLink_home_setsOpenHome() {
        let url = URL(string: "https://recipe-scaler.ru/")!

        DeepLinkRouter.handle(url)

        XCTAssertEqual(DeepLinkRouter.shared.pending, .openHome)
    }

    func test_universalLink_recipe_setsOpenRecipe() {
        let id = "11111111-2222-3333-4444-555555555555"
        let url = URL(string: "https://recipe-scaler.ru/recipe/\(id)")!

        DeepLinkRouter.handle(url)

        XCTAssertEqual(DeepLinkRouter.shared.pending, .openRecipe(recipeId: id))
    }

    func test_universalLink_shopping_setsOpenShoppingList() {
        let url = URL(string: "https://recipe-scaler.ru/shopping")!

        DeepLinkRouter.handle(url)

        XCTAssertEqual(DeepLinkRouter.shared.pending, .openShoppingList)
    }

    func test_universalLink_discover_root_setsOpenDiscover() {
        let url = URL(string: "https://recipe-scaler.ru/discover")!

        DeepLinkRouter.handle(url)

        XCTAssertEqual(DeepLinkRouter.shared.pending, .openDiscover)
    }

    func test_universalLink_discover_collection_setsPending() {
        let url = URL(string: "https://recipe-scaler.ru/discover/collection/weeknight")!

        DeepLinkRouter.handle(url)

        XCTAssertEqual(DeepLinkRouter.shared.pending, .openDiscoverCollection(slug: "weeknight"))
    }

    /// Spec 072: `/discover/feed` (digest push target) parses to
    /// `.openDiscoverFeed` — the «Моя лента» segment.
    func test_universalLink_discover_feed_setsOpenDiscoverFeed() {
        let url = URL(string: "https://recipe-scaler.ru/discover/feed")!

        DeepLinkRouter.handle(url)

        XCTAssertEqual(DeepLinkRouter.shared.pending, .openDiscoverFeed)
    }

    func test_universalLink_discover_recipe_setsPending() {
        let id = "11111111-2222-3333-4444-555555555555"
        let url = URL(string: "https://recipe-scaler.ru/discover/recipe/\(id)")!

        DeepLinkRouter.handle(url)

        XCTAssertEqual(DeepLinkRouter.shared.pending, .openDiscoverRecipe(recipeId: id))
    }

    func test_universalLink_oauth_ignored() {
        let url = URL(string: "https://recipe-scaler.ru/oauth/consent?client_id=x")!

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
    /// Code review 2026-08-05, finding #1 — must still re-route after the
    /// dedup TTL elapses, so a real user re-tap of the same UL navigates.
    func test_handle_sameURLTwice_withinDedupWindow_isIdempotent() {
        let url = URL(string: "https://recipe-scaler.ru/public/@/alice")!

        DeepLinkRouter.handle(url)
        let firstPending = DeepLinkRouter.shared.pending
        XCTAssertEqual(firstPending, .openPublicProfile(username: "alice"))
        DeepLinkRouter.shared.clear()

        // Simulate iOS firing the same UL again immediately via the second callback.
        DeepLinkRouter.handle(url)

        XCTAssertNil(DeepLinkRouter.shared.pending,
                     "Second delivery of the same URL within the dedup window must not re-queue a pending link")
    }

    /// Code review 2026-08-05, finding #1 — after the dedup window elapses,
    /// a repeat tap on the same URL must route again (real user re-tap).
    func test_handle_sameURL_afterDedupWindow_isRouted() {
        let url = URL(string: "https://recipe-scaler.ru/public/@/alice")!

        DeepLinkRouter.handle(url)
        XCTAssertEqual(DeepLinkRouter.shared.pending, .openPublicProfile(username: "alice"))
        DeepLinkRouter.shared.clear()

        // Push the last-handled timestamp out past the dedup window.
        DeepLinkRouter._backdateLastHandledForTesting(by: DeepLinkRouter.lastHandledURLDedupWindow + 1)

        DeepLinkRouter.handle(url)
        XCTAssertEqual(DeepLinkRouter.shared.pending, .openPublicProfile(username: "alice"),
                       "After dedup window elapses, the same URL must route again")
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

    // MARK: - Push payload routing (spec 072)

    /// Digest push `url` (`https://recipe-scaler.ru/discover`) routes to the
    /// Discover tab root («Подборки» segment).
    func test_pushURL_discoverDigest_routesToOpenDiscover() {
        let routed = DeepLinkRouter.handlePushURL("https://recipe-scaler.ru/discover")

        XCTAssertTrue(routed)
        XCTAssertEqual(DeepLinkRouter.shared.pending, .openDiscover)
    }

    /// Spec 072 (2026-08-30): the digest push deep link targets the follower's
    /// feed segment (`/discover/feed`), not the Discover collections root.
    /// Path form.
    func test_pushURL_discoverFeed_routesToOpenDiscoverFeed() {
        let routed = DeepLinkRouter.handlePushURL("https://recipe-scaler.ru/discover/feed")

        XCTAssertTrue(routed)
        XCTAssertEqual(DeepLinkRouter.shared.pending, .openDiscoverFeed)
    }

    /// Server sends web-format hash URLs (`/#/discover/feed`); the hash form
    /// of the digest link routes to the same target.
    func test_pushURL_discoverFeed_hashForm_routesToOpenDiscoverFeed() {
        let routed = DeepLinkRouter.handlePushURL("https://recipe-scaler.ru/#/discover/feed")

        XCTAssertTrue(routed)
        XCTAssertEqual(DeepLinkRouter.shared.pending, .openDiscoverFeed)
    }

    /// Single-recipe push `url` lands *inside the feed* («Моя лента» with the
    /// recipe card pushed on top, product decision 2026-08-30) — not the
    /// Universal Link profile → recipe stack.
    func test_pushURL_publicRecipe_routesToOpenFeedRecipe() {
        let id = "11111111-2222-3333-4444-555555555555"

        let routed = DeepLinkRouter.handlePushURL(
            "https://recipe-scaler.ru/public/@/alice/\(id)"
        )

        XCTAssertTrue(routed)
        XCTAssertEqual(DeepLinkRouter.shared.pending, .openFeedRecipe(recipeId: id))
    }

    /// Hash form of the single-recipe link (server web format) routes
    /// identically to the path form.
    func test_pushURL_publicRecipe_hashForm_routesToOpenFeedRecipe() {
        let id = "11111111-2222-3333-4444-555555555555"

        let routed = DeepLinkRouter.handlePushURL(
            "https://recipe-scaler.ru/#/public/@/alice/\(id)"
        )

        XCTAssertTrue(routed)
        XCTAssertEqual(DeepLinkRouter.shared.pending, .openFeedRecipe(recipeId: id))
    }

    /// Universal Link taps keep the spec 059 profile → recipe stack;
    /// the feed-landing rewrite applies only to push payload URLs.
    func test_universalLink_publicRecipe_keepsProfileStack() {
        let id = "11111111-2222-3333-4444-555555555555"
        let url = URL(string: "https://recipe-scaler.ru/public/@/alice/\(id)")!

        DeepLinkRouter.handle(url)

        XCTAssertEqual(
            DeepLinkRouter.shared.pending,
            .openPublicRecipe(recipeId: id, username: "alice")
        )
    }

    /// Unknown push URLs (web-only paths without a native route) are rejected
    /// instead of being forced into a semantic flow (rule 8: no prefix-based
    /// fallback routing).
    func test_pushURL_unroutable_isRejected() {
        let routed = DeepLinkRouter.handlePushURL("https://recipe-scaler.ru/settings")

        XCTAssertFalse(routed)
        XCTAssertNil(DeepLinkRouter.shared.pending)
    }

    func test_pushURL_malformed_isRejected() {
        let routed = DeepLinkRouter.handlePushURL("not a url %%%")

        XCTAssertFalse(routed)
        XCTAssertNil(DeepLinkRouter.shared.pending)
    }

    func test_pushURL_missing_isRejected() {
        XCTAssertFalse(DeepLinkRouter.handlePushURL(nil))
        XCTAssertFalse(DeepLinkRouter.handlePushURL(""))
        XCTAssertNil(DeepLinkRouter.shared.pending)
    }

    /// APNs redelivery of the same push within the dedup window must not
    /// queue the link twice — same guard as Universal Link delivery.
    func test_pushURL_sameURLTwice_withinDedupWindow_isIdempotent() {
        let url = "https://recipe-scaler.ru/discover"

        XCTAssertTrue(DeepLinkRouter.handlePushURL(url))
        DeepLinkRouter.shared.clear()

        DeepLinkRouter.handlePushURL(url)

        XCTAssertNil(
            DeepLinkRouter.shared.pending,
            "Redelivered push URL within the dedup window must not re-queue a pending link"
        )
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

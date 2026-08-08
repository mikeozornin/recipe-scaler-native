import XCTest
@testable import RecipeScalerNative

@MainActor
final class DiscoverListStateStoreTests: XCTestCase {
    func testCollectionAndProfileScopesKeepIndependentState() {
        let store = DiscoverListStateStore()
        let collection = DiscoverListScope.collection("weeknight")
        let profile = DiscoverListScope.profile("alice")

        store.recordAnchor(recipeID: "collection-recipe", for: collection)
        store.recordAnchor(recipeID: "profile-recipe", for: profile)

        XCTAssertEqual(store.anchor(for: collection), "collection-recipe")
        XCTAssertEqual(store.anchor(for: profile), "profile-recipe")
    }

    func testSearchTextIsTrimmedAndInvalidatesPreviousAnchor() {
        let store = DiscoverListStateStore()
        let scope = DiscoverListScope.collection("weeknight")
        store.recordAnchor(recipeID: "recipe-1", for: scope)

        store.updateSearchText("  soup  ", for: scope)

        XCTAssertEqual(store.state(for: scope).searchText, "soup")
        XCTAssertNil(store.anchor(for: scope))
    }

    func testConsumeAnchorReturnsAndClearsAnchor() {
        let store = DiscoverListStateStore()
        let scope = DiscoverListScope.profile("alice")
        store.recordAnchor(recipeID: "recipe-1", for: scope)

        XCTAssertEqual(store.consumeAnchor(for: scope), "recipe-1")
        XCTAssertNil(store.consumeAnchor(for: scope))
    }

    func testClearAllRemovesTransientDiscoverState() {
        let store = DiscoverListStateStore()
        store.updateSearchText(
            "soup",
            for: .collection("weeknight")
        )
        store.recordAnchor(
            recipeID: "recipe-1",
            for: .profile("alice")
        )

        store.clearAll()

        XCTAssertEqual(store.states.count, 0)
    }
}

import XCTest
@testable import RecipeScalerNative

@MainActor
final class DiscoverSearchStoreTests: XCTestCase {
    private let debounceWait: UInt64 = 250

    func testEmptyQueryReturnsAllItems() async {
        let store = DiscoverSearchStore<CuratedRecipeMetadataDTO>()
        let items = [
            CuratedRecipeMetadataDTO(id: "1", name: "Beef Stew", imageURL: nil, color: "red"),
            CuratedRecipeMetadataDTO(id: "2", name: "Chicken Soup", imageURL: nil, color: "blue")
        ]
        store.setItems(items)
        store.setQuery("")

        try? await Task.sleep(for: .milliseconds(debounceWait))

        XCTAssertEqual(store.filteredSnapshot.count, 2)
    }

    func testFiltersByName() async {
        let store = DiscoverSearchStore<CuratedRecipeMetadataDTO>()
        let items = [
            CuratedRecipeMetadataDTO(id: "1", name: "Beef Stew", imageURL: nil, color: "red"),
            CuratedRecipeMetadataDTO(id: "2", name: "Chicken Soup", imageURL: nil, color: "blue"),
            CuratedRecipeMetadataDTO(id: "3", name: "Vegetable Stir Fry", imageURL: nil, color: "green")
        ]
        store.setItems(items)
        store.setQuery("beef")

        try? await Task.sleep(for: .milliseconds(debounceWait))

        XCTAssertEqual(store.filteredSnapshot.count, 1)
        XCTAssertEqual(store.filteredSnapshot.first?.name, "Beef Stew")
    }

    func testMultipleTokensUseAND() async {
        let store = DiscoverSearchStore<CuratedRecipeMetadataDTO>()
        let items = [
            CuratedRecipeMetadataDTO(id: "1", name: "Beef Stew", imageURL: nil, color: "red"),
            CuratedRecipeMetadataDTO(id: "2", name: "Beef Soup", imageURL: nil, color: "blue"),
            CuratedRecipeMetadataDTO(id: "3", name: "Chicken Soup", imageURL: nil, color: "green")
        ]
        store.setItems(items)
        store.setQuery("beef soup")

        try? await Task.sleep(for: .milliseconds(debounceWait))

        XCTAssertEqual(store.filteredSnapshot.count, 1)
        XCTAssertEqual(store.filteredSnapshot.first?.name, "Beef Soup")
    }

    func testFiltersPublicRecipeByDescription() async {
        let store = DiscoverSearchStore<PublicRecipePreviewDTO>()
        let items = [
            PublicRecipePreviewDTO(
                id: "1",
                name: "Mystery Dish",
                description: "A rich tomato sauce over pasta",
                imageUrl: nil,
                color: nil,
                createdAt: nil
            ),
            PublicRecipePreviewDTO(
                id: "2",
                name: "Plain Rice",
                description: "Steamed white rice",
                imageUrl: nil,
                color: nil,
                createdAt: nil
            )
        ]
        store.setItems(items)
        store.setQuery("tomato")

        try? await Task.sleep(for: .milliseconds(debounceWait))

        XCTAssertEqual(store.filteredSnapshot.count, 1)
        XCTAssertEqual(store.filteredSnapshot.first?.name, "Mystery Dish")
    }

    func testDebounceCancelsStaleQuery() async {
        let store = DiscoverSearchStore<CuratedRecipeMetadataDTO>()
        let items = [
            CuratedRecipeMetadataDTO(id: "1", name: "Steak", imageURL: nil, color: "red"),
            CuratedRecipeMetadataDTO(id: "2", name: "Soup", imageURL: nil, color: "blue")
        ]
        store.setItems(items)

        store.setQuery("soup")
        try? await Task.sleep(for: .milliseconds(50))
        store.setQuery("steak")

        try? await Task.sleep(for: .milliseconds(debounceWait))

        XCTAssertEqual(store.filteredSnapshot.count, 1)
        XCTAssertEqual(store.filteredSnapshot.first?.name, "Steak")
    }

    func testNormalizedCachePersistsAcrossQueries() async {
        let store = DiscoverSearchStore<CuratedRecipeMetadataDTO>()
        let items = [
            CuratedRecipeMetadataDTO(id: "1", name: "Borscht", imageURL: nil, color: "red"),
            CuratedRecipeMetadataDTO(id: "2", name: "Pelmeni", imageURL: nil, color: "blue")
        ]
        store.setItems(items)

        store.setQuery("bor")
        try? await Task.sleep(for: .milliseconds(debounceWait))
        XCTAssertEqual(store.filteredSnapshot.count, 1)

        store.setQuery("pel")
        try? await Task.sleep(for: .milliseconds(debounceWait))
        XCTAssertEqual(store.filteredSnapshot.count, 1)
        XCTAssertEqual(store.filteredSnapshot.first?.name, "Pelmeni")
    }
}

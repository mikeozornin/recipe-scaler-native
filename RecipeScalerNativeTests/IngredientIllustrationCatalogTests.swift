import RecipeScalerCore
import UIKit
import XCTest

@testable import RecipeScalerNative

final class IngredientIllustrationCatalogTests: XCTestCase {
    func testBundledCatalogLoads() {
        let catalog = IngredientIllustrationCatalog.shared
        XCTAssertGreaterThan(catalog.entryCount, 300)
    }

    func testSearchFindsBeefSteakByRussianToken() {
        let catalog = IngredientIllustrationCatalog.shared
        let results = catalog.search(query: "стейк", locale: .ru)
        XCTAssertTrue(results.contains { $0.id == "beef-steak" })
    }

    func testSearchNFKDDiacriticsMatchPlainQuery() {
        let catalog = IngredientIllustrationCatalog.shared
        let withDiacritic = catalog.search(query: "gruyère", locale: .en)
        let plain = catalog.search(query: "gruyere", locale: .en)
        XCTAssertFalse(withDiacritic.isEmpty)
        XCTAssertTrue(withDiacritic.contains { $0.id == "cheese-gruyere" })
        XCTAssertEqual(Set(withDiacritic.map(\.id)), Set(plain.map(\.id)))
    }

    func testBundledThumbWebPLoadsFromMainAppBundle() {
        XCTAssertNotNil(
            Bundle.main.url(forResource: "beef-steak", withExtension: "webp", subdirectory: "IngredientIllustrations"),
            "IngredientIllustrations must be copied into RecipeScalerNative.app, not only Watch"
        )
        XCTAssertNotNil(IngredientIllustrationImageStore.uiImage(for: "beef-steak"))
    }

    func testManifestEntryCountMatchesCatalog() throws {
        let bundle = Bundle(for: IngredientIllustrationCatalog.self)
        guard let manifestURL = bundle.url(forResource: "ingredient-catalog.manifest", withExtension: "json"),
              let data = try? Data(contentsOf: manifestURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let readyCount = json["readyEntryCount"] as? Int
        else {
            XCTFail("manifest missing")
            return
        }
        XCTAssertEqual(IngredientIllustrationCatalog.shared.entryCount, readyCount)
    }
}
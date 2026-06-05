//
//  LocalizationConsistencyTests.swift
//

import XCTest

final class LocalizationConsistencyTests: XCTestCase {
    /// Smoke check that the keys used in the freshly migrated SwiftUI call sites
    /// actually exist in the compiled Localizable.strings for both supported languages.
    /// Acts as a regression net for the "literal string as LocalizedStringKey" pattern.
    func testCriticalKeysResolveInBothLanguages() {
        let keys = [
            "shopping.title",
            "shopping.section.to-buy",
            "shopping.section.purchased",
            "shopping.share-button",
            "shopping.clear-bought",
            "shopping.sort.by-recipe",
            "shopping.sort.az",
            "shopping.empty-to-buy",
            "shopping.empty-to-buy-all-done",
            "shopping.copy-as-text",
            "recipe.list.add",
            "telegram.connect",
            "telegram.disconnect",
            "discover.nav.discover",
            "discover.nav.import"
        ]

        for lang in ["en", "ru"] {
            guard let lproj = Bundle.main.path(forResource: lang, ofType: "lproj"),
                  let bundle = Bundle(path: lproj) else {
                XCTFail("Missing \(lang).lproj in test bundle")
                continue
            }
            for key in keys {
                let resolved = bundle.localizedString(forKey: key, value: nil, table: nil)
                XCTAssertNotEqual(
                    resolved,
                    key,
                    "Key \(key) did not resolve in \(lang) (returned key as-is — missing entry)"
                )
            }
        }
    }
}

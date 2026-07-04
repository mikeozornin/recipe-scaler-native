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

    func testPreSortedCatalogsHaveSameEntryCountAsCanonical() {
        let bundle = Bundle(for: IngredientIllustrationCatalog.self)
        for resource in ["ingredient-catalog.ru", "ingredient-catalog.en"] {
            guard let url = bundle.url(forResource: resource, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let payload = try? JSONDecoder().decode(SingleCatalogFile.self, from: data)
            else {
                XCTFail("\(resource).json missing or unreadable")
                continue
            }
            XCTAssertEqual(
                payload.entries.count,
                IngredientIllustrationCatalog.shared.entryCount,
                "\(resource).json entry count drifted from canonical"
            )
            XCTAssertEqual(
                Set(payload.entries.map(\.id)),
                Set(IngredientIllustrationCatalog.shared.allEntriesForMatching().map(\.id)),
                "\(resource).json ids must match canonical catalog ids"
            )
        }
    }

    /// Safety net for ICU-collator drift between Node `localeCompare({sensitivity:'base'})`
    /// (used by `scripts/sync-ingredient-illustrations.mjs`) and Foundation `.localizedCompare`
    /// (used to be the runtime sort). If Node and Foundation ever disagree, this test fails
    /// before the bundled JSON drifts silently.
    func testBundledRuCatalogIsPreSortedForPicker() {
        let catalog = IngredientIllustrationCatalog.shared
        let expected = Self.referenceLocalizedSortedIds(
            from: catalog.allEntriesForMatching(),
            label: { $0.labelRu },
            localeIdentifier: "ru"
        )
        let actual = catalog.allPickerEntries(locale: .ru).map(\.id)
        XCTAssertEqual(actual, expected, "ingredient-catalog.ru.json order disagrees with Foundation .localizedCompare")
    }

    func testBundledEnCatalogIsPreSortedForPicker() {
        let catalog = IngredientIllustrationCatalog.shared
        let expected = Self.referenceLocalizedSortedIds(
            from: catalog.allEntriesForMatching(),
            label: { $0.labelEn },
            localeIdentifier: "en"
        )
        let actual = catalog.allPickerEntries(locale: .en).map(\.id)
        XCTAssertEqual(actual, expected, "ingredient-catalog.en.json order disagrees with Foundation .localizedCompare")
    }

    func testSearchPreservesPreSortedOrderWhenFiltered() {
        let catalog = IngredientIllustrationCatalog.shared
        for locale in [IngredientIllustrationCatalogLocale.ru, .en] {
            let baseline = catalog.allPickerEntries(locale: locale).map(\.id)
            let result = catalog.search(query: "flour", locale: locale).map(\.id)
            XCTAssertFalse(result.isEmpty, "filter 'flour' should match at least one entry for locale \(locale)")

            var baselineIndex = 0
            var resultIndex = 0
            while baselineIndex < baseline.count, resultIndex < result.count {
                if baseline[baselineIndex] == result[resultIndex] {
                    resultIndex += 1
                }
                baselineIndex += 1
            }
            XCTAssertEqual(
                resultIndex,
                result.count,
                "search result is not a subsequence of allPickerEntries for locale \(locale) — filter must not re-sort"
            )
        }
    }

    private static func referenceLocalizedSortedIds(
        from entries: [IngredientIllustrationCatalogEntry],
        label: (IngredientIllustrationCatalogEntry) -> String,
        localeIdentifier: String
    ) -> [String] {
        entries.sorted { lhs, rhs in
            let l = label(lhs)
            let r = label(rhs)
            if l != r { return l.localizedCompare(r) == .orderedAscending }
            return lhs.id.localizedCompare(rhs.id) == .orderedAscending
        }.map(\.id)
    }

    private struct SingleCatalogFile: Codable {
        let entries: [IngredientIllustrationCatalogEntry]
    }

    func testMergeStoredIllustrationBindingsPrefersPersistedPickerChoice() {
        let stored = [
            IngredientData(id: "ing-1", name: "Eggs", illustrationId: "apricot-jam"),
        ]
        let preview = [
            IngredientData(id: "ing-1", name: "Eggs", illustrationId: "egg"),
        ]

        let merged = IngredientIllustrationLazyResolve.mergeStoredIllustrationBindings(
            stored: stored,
            lazyPreview: preview
        )

        XCTAssertEqual(merged.first?.illustrationId, "apricot-jam")
    }

    func testMergeStoredIllustrationBindingsUsesLazyPreviewWhenUnbound() {
        let stored = [
            IngredientData(id: "ing-1", name: "Eggs"),
        ]
        let preview = [
            IngredientData(id: "ing-1", name: "Eggs", illustrationId: "egg"),
        ]

        let merged = IngredientIllustrationLazyResolve.mergeStoredIllustrationBindings(
            stored: stored,
            lazyPreview: preview
        )

        XCTAssertEqual(merged.first?.illustrationId, "egg")
    }

    func testMergeStoredIllustrationBindingsRespectsPickerClear() {
        let stored = [
            IngredientData(id: "ing-1", name: "Eggs", illustrationPickerCleared: true),
        ]
        let preview = [
            IngredientData(id: "ing-1", name: "Eggs", illustrationId: "egg"),
        ]

        let merged = IngredientIllustrationLazyResolve.mergeStoredIllustrationBindings(
            stored: stored,
            lazyPreview: preview
        )

        XCTAssertNil(merged.first?.illustrationId)
        XCTAssertTrue(merged.first?.illustrationPickerCleared ?? false)
    }
}
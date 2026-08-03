//
//  FeatureAdoptionRingLabelLayoutTests.swift
//  RecipeScalerNativeTests
//

import XCTest
@testable import RecipeScalerNative

@MainActor
final class FeatureAdoptionRingLabelLayoutTests: XCTestCase {
    func testFittingLabelFontSizeReturnsLargerSizeForShortLabel() {
        let short = FeatureAdoptionRingLabelLayout.fittingLabelFontSize(
            for: "1 of 9",
            maxWidth: FeatureAdoptionRingLabelLayout.labelMaxWidth
        )
        let wide = FeatureAdoptionRingLabelLayout.fittingLabelFontSize(
            for: "10 of 10",
            maxWidth: FeatureAdoptionRingLabelLayout.labelMaxWidth
                - FeatureAdoptionRingLabelLayout.measurementWidthSafetyMargin
        )
        XCTAssertGreaterThanOrEqual(short, wide)
        XCTAssertGreaterThanOrEqual(short, FeatureAdoptionRingLabelLayout.minimumLabelFontSize)
        XCTAssertLessThanOrEqual(short, FeatureAdoptionRingLabelLayout.baseLabelFontSize)
    }

    func testFittingLabelFontSizeShrinksForWideLabel() {
        let size = FeatureAdoptionRingLabelLayout.fittingLabelFontSize(
            for: "10 of 10",
            maxWidth: FeatureAdoptionRingLabelLayout.labelMaxWidth
                - FeatureAdoptionRingLabelLayout.measurementWidthSafetyMargin
        )
        XCTAssertLessThan(size, FeatureAdoptionRingLabelLayout.baseLabelFontSize)
        XCTAssertGreaterThanOrEqual(size, FeatureAdoptionRingLabelLayout.absoluteMinimumLabelFontSize)
    }

    func testCachedFontSizeIsStableForSameInput() {
        let text = "10 of 10"
        let locale = "en_US"
        let first = FeatureAdoptionRingLabelLayout.cachedFontSize(for: text, localeIdentifier: locale)
        let second = FeatureAdoptionRingLabelLayout.cachedFontSize(for: text, localeIdentifier: locale)
        XCTAssertEqual(first, second)
    }

    func testClearForLogoutResetsReportAndCache() {
        let store = FeatureAdoptionStore()
        store.report.installedWatchApp = true
        store.markInstalledLocally()
        UserDefaults.standard.set(Data("{}".utf8), forKey: "feature-adoption-cache")
        UserDefaults.standard.set(true, forKey: FeatureAdoptionStore.installedReportedKey)

        store.clearForLogout()

        XCTAssertEqual(store.report, .empty)
        XCTAssertNil(UserDefaults.standard.data(forKey: "feature-adoption-cache"))
        // Spec 038 changelog 2026-08-03: the per-account idempotency flag must
        // be cleared so a different account signing in on the same device
        // triggers a fresh installed_native_app POST. Without this, the first
        // account's flag suppresses the POST for every subsequent account.
        XCTAssertFalse(UserDefaults.standard.bool(forKey: FeatureAdoptionStore.installedReportedKey))
    }
}

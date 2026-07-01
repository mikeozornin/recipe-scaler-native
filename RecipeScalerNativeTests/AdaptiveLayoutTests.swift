//
//  AdaptiveLayoutTests.swift
//  RecipeScalerNativeTests
//
//  Spec 043 — layout mode and preferences.
//

import XCTest
@testable import RecipeScalerNative

@MainActor
final class AdaptiveLayoutTests: XCTestCase {
    func test_layoutModeResolver_compactWhenSizeClassCompact() {
        XCTAssertEqual(
            LayoutModeResolver.resolve(horizontalSizeClass: .compact, forceLayout: nil),
            .compact
        )
    }

    func test_layoutModeResolver_regularWhenSizeClassRegular() {
        XCTAssertEqual(
            LayoutModeResolver.resolve(horizontalSizeClass: .regular, forceLayout: nil),
            .regular
        )
    }

    func test_layoutModeResolver_forceOverridesSizeClass() {
        XCTAssertEqual(
            LayoutModeResolver.resolve(horizontalSizeClass: .regular, forceLayout: .compact),
            .compact
        )
    }

    func test_layoutPreferencesStore_recipeListWidthDefault() {
        let key = "layout.recipe-list-width"
        let prior = UserDefaults.standard.object(forKey: key)
        defer {
            if let prior {
                UserDefaults.standard.set(prior, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(LayoutPreferencesStore.recipeListWidth, LayoutPreferencesStore.recipeListWidthDefault)
    }
}
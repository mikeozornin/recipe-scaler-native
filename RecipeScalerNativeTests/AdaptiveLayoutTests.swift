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

    func test_interactionProfile_iOSUsesTouchProfile() {
#if os(iOS)
        XCTAssertEqual(InteractionProfile.current, .touch)
#else
        XCTFail("This test target must run on iOS")
#endif
    }

    func test_trackpadActionStrip_requiresNeutralBetweenDirections() {
        var state = TrackpadActionStripState()

        state.consume(deltaX: 24)
        XCTAssertEqual(state.strip, .leading)

        state.consume(deltaX: -24)
        XCTAssertEqual(state.strip, .leading)

        state.consume(deltaX: 0)
        XCTAssertEqual(state.strip, .none)

        state.consume(deltaX: -24)
        XCTAssertEqual(state.strip, .trailing)
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

    func test_layoutPreferencesStore_clampsPersistedWidths() {
        let listKey = "layout.recipe-list-width"
        let ingredientsKey = "layout.recipe-ingredients-width"
        let priorList = UserDefaults.standard.object(forKey: listKey)
        let priorIngredients = UserDefaults.standard.object(forKey: ingredientsKey)
        defer {
            if let priorList {
                UserDefaults.standard.set(priorList, forKey: listKey)
            } else {
                UserDefaults.standard.removeObject(forKey: listKey)
            }
            if let priorIngredients {
                UserDefaults.standard.set(priorIngredients, forKey: ingredientsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: ingredientsKey)
            }
        }

        UserDefaults.standard.set(-1, forKey: listKey)
        UserDefaults.standard.set(9_999, forKey: ingredientsKey)

        XCTAssertEqual(LayoutPreferencesStore.recipeListWidth, LayoutPreferencesStore.recipeListWidthMin)
        XCTAssertEqual(
            LayoutPreferencesStore.recipeIngredientsWidth,
            LayoutPreferencesStore.recipeIngredientsWidthMax
        )

        LayoutPreferencesStore.recipeListWidth = 9_999
        LayoutPreferencesStore.recipeIngredientsWidth = -1

        XCTAssertEqual(LayoutPreferencesStore.recipeListWidth, LayoutPreferencesStore.recipeListWidthMax)
        XCTAssertEqual(
            LayoutPreferencesStore.recipeIngredientsWidth,
            LayoutPreferencesStore.recipeIngredientsWidthMin
        )
    }

    func test_layoutPreferencesStore_roundTripsValidWidths() {
        let listKey = "layout.recipe-list-width"
        let ingredientsKey = "layout.recipe-ingredients-width"
        let priorList = UserDefaults.standard.object(forKey: listKey)
        let priorIngredients = UserDefaults.standard.object(forKey: ingredientsKey)
        defer {
            if let priorList {
                UserDefaults.standard.set(priorList, forKey: listKey)
            } else {
                UserDefaults.standard.removeObject(forKey: listKey)
            }
            if let priorIngredients {
                UserDefaults.standard.set(priorIngredients, forKey: ingredientsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: ingredientsKey)
            }
        }

        LayoutPreferencesStore.recipeListWidth = 356
        LayoutPreferencesStore.recipeIngredientsWidth = 512

        XCTAssertEqual(LayoutPreferencesStore.recipeListWidth, 356)
        XCTAssertEqual(LayoutPreferencesStore.recipeIngredientsWidth, 512)
        XCTAssertEqual(UserDefaults.standard.double(forKey: listKey), 356)
        XCTAssertEqual(UserDefaults.standard.double(forKey: ingredientsKey), 512)
    }

    func test_layoutPreferencesStore_roundTripsRecipesRoute() {
        let key = "layout.last-recipes-route"
        let prior = UserDefaults.standard.object(forKey: key)
        defer {
            if let prior {
                UserDefaults.standard.set(prior, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        LayoutPreferencesStore.lastRecipesRoute = "/folder/favorites"

        XCTAssertEqual(LayoutPreferencesStore.lastRecipesRoute, "/folder/favorites")
        XCTAssertEqual(UserDefaults.standard.string(forKey: key), "/folder/favorites")
    }
}

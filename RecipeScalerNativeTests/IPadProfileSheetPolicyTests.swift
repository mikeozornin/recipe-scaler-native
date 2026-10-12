//
//  IPadProfileSheetPolicyTests.swift
//
//  Spec 081 (T019a, plan.md Р2a) — «Профиль» in a wide iPad window is a sheet.
//

import XCTest
@testable import RecipeScalerNative

final class IPadProfileSheetPolicyTests: XCTestCase {

    func testRegularProfilePresentsSheetAndKeepsPrevious() {
        let result = IPadProfileSheetPolicy.resolve(selected: .profile, previous: .shopping, layoutMode: .padRegular)

        XCTAssertEqual(result.selected, .shopping)
        XCTAssertTrue(result.presentsSheet)
    }

    func testRegularProfileWithoutPreviousFallsBackToRecipes() {
        for previous in [nil, AppTab.profile, .assistant, .importTab] {
            let result = IPadProfileSheetPolicy.resolve(selected: .profile, previous: previous, layoutMode: .padRegular)

            XCTAssertEqual(result.selected, .recipes, "previous: \(String(describing: previous))")
            XCTAssertTrue(result.presentsSheet)
        }
    }

    func testPhoneProfileSelectsTab() {
        let result = IPadProfileSheetPolicy.resolve(selected: .profile, previous: .shopping, layoutMode: .phone)

        XCTAssertEqual(result.selected, .profile)
        XCTAssertFalse(result.presentsSheet)
    }

    func testCompactProfileWithSheetUpKeepsSheetAndPrevious() {
        let result = IPadProfileSheetPolicy.resolve(
            selected: .profile,
            previous: .discover,
            layoutMode: .phone,
            isSheetPresented: true
        )

        XCTAssertEqual(result.selected, .discover)
        XCTAssertTrue(result.presentsSheet)
    }

    func testNonProfileSelectionWithSheetUpUnchanged() {
        for mode in [AppLayoutMode.phone, .padRegular] {
            let result = IPadProfileSheetPolicy.resolve(
                selected: .shopping,
                previous: .recipes,
                layoutMode: mode,
                isSheetPresented: true
            )

            XCTAssertEqual(result.selected, .shopping)
            XCTAssertFalse(result.presentsSheet)
        }
    }

    func testNonProfileSelectionUnchanged() {
        for mode in [AppLayoutMode.phone, .padRegular] {
            for tab in [AppTab.discover, .recipes, .shopping] {
                let result = IPadProfileSheetPolicy.resolve(selected: tab, previous: .profile, layoutMode: mode)

                XCTAssertEqual(result.selected, tab)
                XCTAssertFalse(result.presentsSheet)
            }
        }
    }
}

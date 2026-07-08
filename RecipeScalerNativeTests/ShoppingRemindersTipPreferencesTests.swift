//
//  ShoppingRemindersTipPreferencesTests.swift
//  RecipeScalerNativeTests
//

import XCTest
@testable import RecipeScalerNative

final class ShoppingRemindersTipPreferencesTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ShoppingRemindersTipPreferences.resetForTests()
    }

    override func tearDown() {
        ShoppingRemindersTipPreferences.resetForTests()
        super.tearDown()
    }

    func test_default_shouldShow() {
        XCTAssertTrue(ShoppingRemindersTipPreferences.shouldShow)
    }

    func test_dismiss_hidesPermanently() {
        ShoppingRemindersTipPreferences.dismiss()
        XCTAssertFalse(ShoppingRemindersTipPreferences.shouldShow)
        // Second dismiss stays dismissed
        ShoppingRemindersTipPreferences.dismiss()
        XCTAssertFalse(ShoppingRemindersTipPreferences.shouldShow)
    }
}

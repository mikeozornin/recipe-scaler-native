//
//  UserIdFormatterTests.swift
//  RecipeScalerNativeTests
//

import XCTest
@testable import RecipeScalerNative

final class UserIdFormatterTests: XCTestCase {
    private let sampleUserId = "cfcd839f-56f2-4411-9632-7795b75f96d1"

    func testFormatMatchesWebStyle() {
        XCTAssertEqual(UserIdFormatter.format(sampleUserId), "cfc·6d1")
    }

    func testRedactNil() {
        XCTAssertEqual(UserIdFormatter.redact(nil), "<user:nil>")
    }

    func testRedactEmpty() {
        XCTAssertEqual(UserIdFormatter.redact(""), "<user:nil>")
    }

    func testRedactFullUserId() {
        XCTAssertEqual(UserIdFormatter.redact(sampleUserId), "<user:cfcd83>")
    }

    func testRedactDocKeyRecipe() {
        let docKey = "\(sampleUserId):recipe:abc-123"
        XCTAssertEqual(UserIdFormatter.redactDocKey(docKey), "<user:cfcd83>:recipe:abc-123")
    }

    func testRedactDocKeyCollection() {
        let docKey = "\(sampleUserId):collection"
        XCTAssertEqual(UserIdFormatter.redactDocKey(docKey), "<user:cfcd83>:collection")
    }

    func testRedactDocKeyWithoutColon() {
        XCTAssertEqual(UserIdFormatter.redactDocKey("no-colon-here"), "<unknown>")
    }

    // MARK: - redactRecipeId

    func testRedactRecipeIdNil() {
        XCTAssertEqual(UserIdFormatter.redactRecipeId(nil), "<recipe:nil>")
    }

    func testRedactRecipeIdEmpty() {
        XCTAssertEqual(UserIdFormatter.redactRecipeId(""), "<recipe:nil>")
    }

    func testRedactRecipeIdFull() {
        XCTAssertEqual(UserIdFormatter.redactRecipeId("abc-123-456"), "<recipe:abc-12>")
    }

    func testRedactRecipeIdShortStringKeptAsIs() {
        XCTAssertEqual(UserIdFormatter.redactRecipeId("ab"), "<recipe:ab>")
    }
}

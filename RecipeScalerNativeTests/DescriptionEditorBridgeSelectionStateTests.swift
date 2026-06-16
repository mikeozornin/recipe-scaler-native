//
//  DescriptionEditorBridgeSelectionStateTests.swift
//
//  019 T023 — парсинг selectionState JSON из description-editor-bridge.js.
//  Проверяет, что Swift-сторона корректно интерпретирует payload Tiptap.
//

import XCTest
@testable import RecipeScalerNative

@MainActor
final class DescriptionEditorBridgeSelectionStateTests: XCTestCase {

    // MARK: - Defaults

    func test_emptyDictionary_returnsAllInactiveState() {
        let state = DescriptionEditorBridge.makeSelectionStateForTesting([:])

        XCTAssertFalse(state.bold)
        XCTAssertFalse(state.heading1)
        XCTAssertFalse(state.highlight)
        XCTAssertFalse(state.bulletList)
        XCTAssertFalse(state.orderedList)
        XCTAssertFalse(state.hasSelection)
        XCTAssertEqual(state.selectedText, "")
        // can* default to true when key is absent.
        XCTAssertTrue(state.canBold)
        XCTAssertTrue(state.canHeading1)
        XCTAssertTrue(state.canHighlight)
        XCTAssertTrue(state.canBulletList)
        XCTAssertTrue(state.canOrderedList)
        XCTAssertFalse(state.canMarkTimer)
        XCTAssertFalse(state.canMarkIngredient)
    }

    // MARK: - Bool and NSNumber

    func test_boolLiteral_true() {
        let state = DescriptionEditorBridge.makeSelectionStateForTesting([
            "bold": true,
            "heading1": true,
            "hasSelection": true
        ])

        XCTAssertTrue(state.bold)
        XCTAssertTrue(state.heading1)
        XCTAssertTrue(state.hasSelection)
    }

    func test_nsNumber_one_isTrue() {
        // Tiptap иногда шлёт NSNumber (0/1) вместо bool.
        let state = DescriptionEditorBridge.makeSelectionStateForTesting([
            "bold": NSNumber(value: 1),
            "highlight": NSNumber(value: 0)
        ])

        XCTAssertTrue(state.bold)
        XCTAssertFalse(state.highlight)
    }

    // MARK: - Selected text

    func test_selectedText_stringUsed() {
        let state = DescriptionEditorBridge.makeSelectionStateForTesting([
            "hasSelection": true,
            "selectedText": "Boil water"
        ])

        XCTAssertTrue(state.hasSelection)
        XCTAssertEqual(state.selectedText, "Boil water")
        XCTAssertTrue(state.canMarkTimer)
        XCTAssertTrue(state.canMarkIngredient)
    }

    func test_selectedText_whitespaceOnly_disablesMark() {
        let state = DescriptionEditorBridge.makeSelectionStateForTesting([
            "hasSelection": true,
            "selectedText": "   \n\t "
        ])

        XCTAssertTrue(state.hasSelection)
        XCTAssertTrue(state.selectedText.isEmpty == false) // original preserved
        XCTAssertFalse(state.canMarkTimer)
        XCTAssertFalse(state.canMarkIngredient)
    }

    // MARK: - can* flags

    func test_canFlags_falseWhenExplicitlyFalse() {
        let state = DescriptionEditorBridge.makeSelectionStateForTesting([
            "canBold": false,
            "canHeading1": false,
            "canHighlight": false,
            "canBulletList": false,
            "canOrderedList": false
        ])

        XCTAssertFalse(state.canBold)
        XCTAssertFalse(state.canHeading1)
        XCTAssertFalse(state.canHighlight)
        XCTAssertFalse(state.canBulletList)
        XCTAssertFalse(state.canOrderedList)
    }

    func test_canFlags_trueWhenExplicitlyTrue() {
        let state = DescriptionEditorBridge.makeSelectionStateForTesting([
            "canBold": true,
            "canHeading1": true,
            "canHighlight": true,
            "canBulletList": true,
            "canOrderedList": true
        ])

        XCTAssertTrue(state.canBold)
        XCTAssertTrue(state.canHeading1)
        XCTAssertTrue(state.canHighlight)
        XCTAssertTrue(state.canBulletList)
        XCTAssertTrue(state.canOrderedList)
    }

    // MARK: - Full bridge payload (parity with description-editor-bridge-v2.md)

    func test_fullPayloadFromContract() {
        // Из contracts/description-editor-bridge-v2.md — пример selectionState.
        let dict: [String: Any] = [
            "empty": false,
            "bold": false,
            "heading1": false,
            "highlight": false,
            "bulletList": false,
            "orderedList": false,
            "link": false,
            "canBold": true,
            "canHeading1": true,
            "canHighlight": true,
            "canBulletList": true,
            "canOrderedList": true,
            "canLink": true,
            "hasSelection": true
        ]
        let state = DescriptionEditorBridge.makeSelectionStateForTesting(dict)

        XCTAssertFalse(state.bold)
        XCTAssertTrue(state.hasSelection)
        XCTAssertTrue(state.canBold)
        XCTAssertTrue(state.canHeading1)
        XCTAssertTrue(state.canHighlight)
        XCTAssertTrue(state.canBulletList)
        XCTAssertTrue(state.canOrderedList)
        // selectedText missing → "" but hasSelection true → mark allowed only
        // if selectedText has non-whitespace content.
        XCTAssertEqual(state.selectedText, "")
        XCTAssertFalse(state.canMarkTimer)
    }

    // MARK: - Unknown keys

    func test_unknownKeys_ignored() {
        let state = DescriptionEditorBridge.makeSelectionStateForTesting([
            "bold": true,
            "link": true,            // link не парсится в SelectionState
            "canLink": true,         // не парсится
            "future": "value"
        ])

        XCTAssertTrue(state.bold)
        // canBold defaults true when key absent.
        XCTAssertTrue(state.canBold)
    }

    // MARK: - Equatable

    func test_equatable_samePayloads_equal() {
        let dict: [String: Any] = ["bold": true, "hasSelection": true]
        let a = DescriptionEditorBridge.makeSelectionStateForTesting(dict)
        let b = DescriptionEditorBridge.makeSelectionStateForTesting(dict)
        XCTAssertEqual(a, b)
    }

    func test_equatable_differentPayloads_notEqual() {
        let a = DescriptionEditorBridge.makeSelectionStateForTesting(["bold": true])
        let b = DescriptionEditorBridge.makeSelectionStateForTesting(["bold": false])
        XCTAssertNotEqual(a, b)
    }
}

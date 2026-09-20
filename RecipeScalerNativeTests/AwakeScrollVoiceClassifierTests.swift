import XCTest
@testable import RecipeScalerNative

final class AwakeScrollVoiceClassifierTests: XCTestCase {
    func test_ru_vniz() {
        XCTAssertEqual(
            AwakeScrollVoiceClassifier.action(from: "вниз", isFinal: true),
            .down
        )
        XCTAssertEqual(
            AwakeScrollVoiceClassifier.action(from: "выше", isFinal: false),
            .up
        )
        XCTAssertEqual(
            AwakeScrollVoiceClassifier.action(from: "ниже", isFinal: false),
            .down
        )
        XCTAssertEqual(AwakeScrollVoiceClassifier.chip(from: "выше"), .higher)
        XCTAssertEqual(AwakeScrollVoiceClassifier.chip(from: "ниже"), .lower)
    }

    func test_ru_vverh() {
        XCTAssertEqual(
            AwakeScrollVoiceClassifier.action(from: "Вверх!", isFinal: true),
            .up
        )
    }

    func test_en_up_and_down() {
        XCTAssertEqual(AwakeScrollVoiceClassifier.action(from: "up", isFinal: true), .up)
        XCTAssertEqual(AwakeScrollVoiceClassifier.action(from: "down", isFinal: true), .down)
        XCTAssertEqual(
            AwakeScrollVoiceClassifier.action(from: "scroll down", isFinal: true),
            .down
        )
        XCTAssertEqual(
            AwakeScrollVoiceClassifier.action(from: "scroll down", isFinal: false),
            .down
        )
    }

    func test_recognizer_locale_follows_app_language() {
        XCTAssertEqual(
            AwakeScrollVoiceEngine.recognizerLocale(for: .en).identifier,
            "en_US"
        )
        XCTAssertEqual(
            AwakeScrollVoiceEngine.recognizerLocale(for: .ru).identifier,
            "ru_RU"
        )
    }

    func test_trailing_ru_and_rejects_english_collocations() {
        XCTAssertNil(AwakeScrollVoiceClassifier.action(from: "stop", isFinal: true))
        XCTAssertNil(AwakeScrollVoiceClassifier.action(from: "top", isFinal: true))
        XCTAssertNil(AwakeScrollVoiceClassifier.action(from: "вверх пожалуйста", isFinal: true))
        XCTAssertEqual(
            AwakeScrollVoiceClassifier.action(from: "ну вниз", isFinal: true),
            .down
        )
        XCTAssertEqual(
            AwakeScrollVoiceClassifier.action(from: "вниз вниз", isFinal: true),
            .down
        )
        XCTAssertEqual(
            AwakeScrollVoiceClassifier.action(from: "please scroll down", isFinal: true),
            .down
        )
        XCTAssertNil(AwakeScrollVoiceClassifier.action(from: "calm down", isFinal: true))
        XCTAssertNil(AwakeScrollVoiceClassifier.action(from: "hands up", isFinal: true))
        XCTAssertNil(AwakeScrollVoiceClassifier.action(from: "up", isFinal: false))
        XCTAssertNil(AwakeScrollVoiceClassifier.action(from: "", isFinal: true))
    }

    func test_fire_gate_ru_partial_fires_immediately() {
        var gate = AwakeScrollVoiceFireGate()
        XCTAssertEqual(gate.action(from: "вниз", isFinal: false, now: Date()), .down)
    }

    func test_fire_gate_english_singleton_needs_stability() {
        var gate = AwakeScrollVoiceFireGate()
        let t0 = Date()
        XCTAssertNil(gate.action(from: "down", isFinal: false, now: t0))
        XCTAssertEqual(
            gate.action(from: "down", isFinal: false, now: t0.addingTimeInterval(0.31)),
            .down
        )
    }

    func test_fire_gate_final_fires_immediately() {
        var gate = AwakeScrollVoiceFireGate()
        XCTAssertEqual(gate.action(from: "down", isFinal: true, now: Date()), .down)
    }
}

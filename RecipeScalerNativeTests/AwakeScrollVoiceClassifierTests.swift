import XCTest
@testable import RecipeScalerNative

final class AwakeScrollVoiceClassifierTests: XCTestCase {
    func test_ru_vniz() {
        XCTAssertEqual(
            AwakeScrollVoiceClassifier.action(from: "вниз", isFinal: true),
            .down
        )
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

    func test_rejects_near_miss() {
        XCTAssertNil(AwakeScrollVoiceClassifier.action(from: "stop", isFinal: true))
        XCTAssertNil(AwakeScrollVoiceClassifier.action(from: "top", isFinal: true))
        XCTAssertNil(AwakeScrollVoiceClassifier.action(from: "вверх пожалуйста", isFinal: true))
        XCTAssertEqual(
            AwakeScrollVoiceClassifier.action(from: "please scroll down", isFinal: true),
            .down
        )
        XCTAssertNil(AwakeScrollVoiceClassifier.action(from: "вниз", isFinal: false))
        XCTAssertEqual(
            AwakeScrollVoiceClassifier.action(from: "вниз", isFinal: false, isStablePartial: true),
            .down
        )
        XCTAssertNil(AwakeScrollVoiceClassifier.action(from: "", isFinal: true))
    }
}

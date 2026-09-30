//
//  ShakeToOpenAssistantPreferenceTests.swift
//  RecipeScalerNativeTests
//
//  Spec 078 — preference default OFF + shake debounce.
//

import XCTest
@testable import RecipeScalerNative

final class ShakeToOpenAssistantPreferenceTests: XCTestCase {
    private var suite: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = UserDefaults(suiteName: "ShakeToOpenAssistantPreferenceTests.\(UUID().uuidString)")
        ShakeToOpenAssistantPreference.defaults = suite
        DeviceShakeDetector.resetDebounceForTests()
    }

    override func tearDown() {
        ShakeToOpenAssistantPreference.defaults = .standard
        DeviceShakeDetector.resetDebounceForTests()
        suite = nil
        super.tearDown()
    }

    func test_default_disabled() {
        XCTAssertFalse(ShakeToOpenAssistantPreference.isEnabled)
    }

    func test_persists_enabled() {
        ShakeToOpenAssistantPreference.isEnabled = true
        XCTAssertTrue(ShakeToOpenAssistantPreference.isEnabled)
        ShakeToOpenAssistantPreference.isEnabled = false
        XCTAssertFalse(ShakeToOpenAssistantPreference.isEnabled)
    }

    func test_debounce_drops_second() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(DeviceShakeDetector.shouldAcceptShake(now: t0, debounce: 1.0))
        XCTAssertFalse(DeviceShakeDetector.shouldAcceptShake(
            now: t0.addingTimeInterval(0.5),
            debounce: 1.0
        ))
        XCTAssertTrue(DeviceShakeDetector.shouldAcceptShake(
            now: t0.addingTimeInterval(1.0),
            debounce: 1.0
        ))
    }

    func test_shake_request_with_recipe_does_not_force_new_chat() {
        let request = AssistantShakeOpenRequest.make(
            requestId: 1,
            visibleRecipeId: "abc",
            startVoiceRecording: true
        )
        XCTAssertEqual(request.attachRecipeId, "abc")
        XCTAssertFalse(request.forceNewChat)
        XCTAssertTrue(request.startVoiceRecording)
    }

    func test_shake_request_without_recipe_forces_new_chat() {
        let request = AssistantShakeOpenRequest.make(
            requestId: 2,
            visibleRecipeId: nil,
            startVoiceRecording: true
        )
        XCTAssertNil(request.attachRecipeId)
        XCTAssertTrue(request.forceNewChat)
        XCTAssertTrue(request.startVoiceRecording)
    }
}

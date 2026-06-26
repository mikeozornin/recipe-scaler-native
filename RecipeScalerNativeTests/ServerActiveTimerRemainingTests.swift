//
//  ServerActiveTimerRemainingTests.swift
//  RecipeScalerNativeTests
//

import XCTest
import RecipeScalerCore

final class ServerActiveTimerRemainingTests: XCTestCase {
    func testPausedProdTimerUsesPauseAnchorNotPausedDuration() {
        // Prod snapshot: pausedDuration=8 is accumulated pause seconds, not remaining.
        let timer = ServerActiveTimer(
            timerId: "timer_test",
            name: "Test",
            duration: 2700,
            endTime: 1_782_516_304_810,
            isPaused: true,
            pausedDuration: 8,
            createdAt: 1_782_512_985_696,
            lastUpdated: 1_782_513_616_115,
            startedAt: 1_782_512_985_696,
            pausedAt: nil,
            recipeId: nil
        )

        XCTAssertEqual(timer.remainingSeconds(), 2_688)
    }

    func testRunningUsesEndTimeMinusNow() {
        let nowMs: Int64 = 1_782_513_696_248
        let timer = ServerActiveTimer(
            timerId: "timer_test",
            name: "Test",
            duration: 2700,
            endTime: 1_782_516_304_810,
            isPaused: false,
            pausedDuration: 0,
            createdAt: 1_782_512_985_696,
            lastUpdated: nowMs,
            startedAt: 1_782_512_985_696,
            pausedAt: nil,
            recipeId: nil
        )

        let now = Date(timeIntervalSince1970: TimeInterval(nowMs) / 1000)
        XCTAssertEqual(timer.remainingSeconds(at: now), 2_608)
    }
}

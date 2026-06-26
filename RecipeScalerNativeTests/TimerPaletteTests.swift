//
//  TimerPaletteTests.swift
//  RecipeScalerNativeTests
//

import XCTest
import RecipeScalerCore

final class TimerPaletteTests: XCTestCase {
    func testExceededWhenRemainingNegative() {
        let accent = TimerPalette.Accent.resolve(
            phase: .running,
            remainingSeconds: -7,
            totalDuration: 10
        )
        XCTAssertEqual(accent, .exceeded)
    }

    func testSoonLastTenPercentInclusive() {
        // 10s timer: last 1s (10%) should be orange, not only 0s.
        let oneSecondLeft = TimerPalette.Accent.resolve(
            phase: .running,
            remainingSeconds: 1,
            totalDuration: 10
        )
        XCTAssertEqual(oneSecondLeft, .soon)

        let twoSecondsLeft = TimerPalette.Accent.resolve(
            phase: .running,
            remainingSeconds: 2,
            totalDuration: 10
        )
        XCTAssertEqual(twoSecondsLeft, .normal)
    }

    func testExceededPhaseExplicit() {
        let accent = TimerPalette.Accent.resolve(
            phase: .exceeded,
            remainingSeconds: -7,
            totalDuration: 10
        )
        XCTAssertEqual(accent, .exceeded)
    }

    func testSoonOn45MinuteTimer() {
        let accent = TimerPalette.Accent.resolve(
            phase: .running,
            remainingSeconds: 270,
            totalDuration: 2700
        )
        XCTAssertEqual(accent, .soon)

        let stillNormal = TimerPalette.Accent.resolve(
            phase: .running,
            remainingSeconds: 271,
            totalDuration: 2700
        )
        XCTAssertEqual(stillNormal, .normal)
    }
}

import XCTest
@testable import RecipeScalerNative
import RecipeScalerCore

/// Regression: widget must not freeze at `0s` (spec 030).
final class TimerWidgetTimelineTests: XCTestCase {

    func testTimerSnapshotAtZeroUsesExceededPhase() {
        let timer = RecipeTimer(
            id: "zero-phase",
            name: "Test",
            duration: 10,
            type: .seconds,
            isRunning: true
        )
        timer.endTime = Date()
        timer.hasCompleted = true

        let snapshot = TimerSnapshot(from: timer)
        XCTAssertEqual(snapshot?.phase, .exceeded)
        XCTAssertEqual(snapshot?.remainingSeconds(), 0)
    }

    func testTimerWidgetProviderSourceTreatsZeroAsSecondGranularity() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HomeWidgetExtension/TimerWidgetProvider.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertFalse(
            source.contains("guard remaining != 0 else { return false }"),
            "0s must stay on second-granularity timeline"
        )
        XCTAssertTrue(
            source.contains("else if remaining == 0"),
            "coarse timeline must reload 1s after hitting 0"
        )
    }
}

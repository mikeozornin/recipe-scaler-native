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

    func testTimerWidgetProviderPlaceholderIsEmptyNotFigmaStub() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HomeWidgetExtension/TimerWidgetProvider.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(
            source.contains("func placeholder(in context: Context) -> TimerWidgetEntry"),
            "placeholder(in:) must still exist"
        )
        XCTAssertTrue(
            source.contains("TimerWidgetEntry.empty"),
            "placeholder/gallery must use empty, not Figma stub timers"
        )
        XCTAssertFalse(
            source.contains("placeholderSmall()"),
            "runtime provider must not call placeholderSmall()"
        )
        XCTAssertTrue(
            source.contains("if context.isPreview"),
            "getSnapshot must skip App Group in the widget gallery"
        )
    }
}

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

    // MARK: - Precomputed timeline (widget froze once the reload budget ran out)

    private let anchor = Date(timeIntervalSince1970: 1_700_000_000)

    private func running(remaining: TimeInterval, total: TimeInterval) -> TimerSnapshot {
        TimerSnapshot(
            id: "t",
            name: "Step",
            recipeId: nil,
            recipeName: nil,
            endDate: anchor.addingTimeInterval(remaining),
            pausedRemainingSeconds: nil,
            phase: remaining >= 0 ? .running : .exceeded,
            totalDurationSeconds: total
        )
    }

    private func offsets(_ dates: [Date]) -> [Int] {
        dates.map { Int($0.timeIntervalSince(anchor).rounded()) }
    }

    func testLongTimerCoversAnHourWithMinuteEntriesInOneTimeline() {
        let dates = TimerWidgetTimelineSchedule.entryDates(
            for: [running(remaining: 3 * 3600, total: 4 * 3600)],
            now: anchor,
            secondGranularityWindow: 60
        )

        XCTAssertEqual(dates.count, 61, "now + one entry per minute for the next hour")
        XCTAssertEqual(offsets(dates).last, 3600 - 59)
        let ticks = dates.dropFirst()
        XCTAssertTrue(zip(ticks, ticks.dropFirst()).allSatisfy { $1.timeIntervalSince($0) == 60 })
    }

    func testMinuteEntriesLandWhereTheCompactLabelChanges() {
        let timer = running(remaining: 10 * 60 + 30, total: 20 * 60)
        let dates = TimerWidgetTimelineSchedule.entryDates(for: [timer], now: anchor, secondGranularityWindow: 60)

        XCTAssertEqual(Array(offsets(dates).prefix(3)), [0, 31, 91], "10m → 9m at 599s left, 8m at 539s")
        for date in dates.dropFirst() {
            let before = timer.remainingSeconds(now: date.addingTimeInterval(-1))
            let at = timer.remainingSeconds(now: date)
            XCTAssertNotEqual(minuteLabel(before), minuteLabel(at), "entry at remaining \(at)s changes nothing")
        }
    }

    func testLastMinuteTicksEverySecondIntoOverdue() {
        let dates = TimerWidgetTimelineSchedule.entryDates(
            for: [running(remaining: 30, total: 600)],
            now: anchor,
            secondGranularityWindow: 60
        )
        let ticks = offsets(dates)

        XCTAssertEqual(Array(ticks.prefix(91)), Array(0...90), "30s left → per-second through -60s")
        XCTAssertEqual(ticks.dropFirst(91).first, 150, "then -2m at 120s overdue")
    }

    func testPausedOnlyHasSingleEntry() {
        let paused = TimerSnapshot(
            id: "p",
            name: "Step",
            recipeId: nil,
            recipeName: nil,
            endDate: nil,
            pausedRemainingSeconds: 300,
            phase: .paused,
            totalDurationSeconds: 600
        )
        XCTAssertEqual(
            TimerWidgetTimelineSchedule.entryDates(for: [paused], now: anchor, secondGranularityWindow: 60),
            [anchor]
        )
    }

    func testTimerWidgetProviderUsesPrecomputedTimeline() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HomeWidgetExtension/TimerWidgetProvider.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(source.contains("TimerWidgetTimelineSchedule.entryDates"))
        XCTAssertFalse(
            source.contains("nextMinuteBoundary"),
            "one-entry timelines reloading every minute exhaust the WidgetKit budget"
        )
    }

    /// Mirrors `WidgetTimerFormatting.compactRemaining` for minute labels.
    private func minuteLabel(_ seconds: Int) -> String {
        abs(seconds) >= 60 ? "\(seconds / 60)m" : "\(seconds)s"
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

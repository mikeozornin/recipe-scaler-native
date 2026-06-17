//
//  TimerWidgetEntry.swift
//  HomeWidgetExtension
//
//  Spec 030 — Timeline entry shown by `TimerWidgetProvider`.
//

import Foundation
import WidgetKit
import RecipeScalerCore

/// Timeline entry shown by `TimerWidgetProvider`.
struct TimerWidgetEntry: TimelineEntry {
    let date: Date
    let timers: [TimerSnapshot]

    static let empty = TimerWidgetEntry(date: Date(), timers: [])

    // MARK: - Figma copy (107:238 / 107:318)

    private static let figmaRecipeShort = "выпекайте до золотой корочки"
    private static let figmaRecipeLong = "выпекайте до золотой корочки и вообще"

    /// Figma `107:238` — 1 timer, `4m` of 50m, soon (orange).
    static func placeholderOne(now: Date = Date()) -> TimerWidgetEntry {
        TimerWidgetEntry(
            date: now,
            timers: [
                runningSnapshot(
                    id: "stub-1",
                    remainingMinutes: 4,
                    totalMinutes: 50,
                    recipeName: figmaRecipeShort,
                    now: now
                ),
            ]
        )
    }

    /// Figma `107:318` — 2 linear rows (debug wrap scenario + Figma placeholders).
    static func placeholderTwo(now: Date = Date()) -> TimerWidgetEntry {
        TimerWidgetEntry(
            date: now,
            timers: [
                exceededSnapshot(
                    id: "stub-1",
                    overdueMinutes: 16,
                    totalMinutes: 10,
                    recipeName: "10 минут длинное название",
                    now: now
                ),
                runningSnapshot(
                    id: "stub-2",
                    remainingMinutes: 9 * 60 + 45,
                    totalMinutes: 10 * 60,
                    recipeName: "10 часов длинное название",
                    now: now
                ),
            ]
        )
    }

    /// Figma `107:208` — 3 rings: normal / soon / exceeded, all display `4m`.
    static func placeholderThree(now: Date = Date()) -> TimerWidgetEntry {
        TimerWidgetEntry(
            date: now,
            timers: [
                runningSnapshot(id: "stub-1", remainingMinutes: 4, totalMinutes: 10, now: now),
                runningSnapshot(id: "stub-2", remainingMinutes: 4, totalMinutes: 50, now: now),
                exceededSnapshot(id: "stub-3", overdueMinutes: 4, now: now),
            ]
        )
    }

    /// Figma `107:221` — 4 rings: normal / soon / exceeded / exceeded.
    static func placeholderFour(now: Date = Date()) -> TimerWidgetEntry {
        TimerWidgetEntry(
            date: now,
            timers: [
                runningSnapshot(id: "stub-1", remainingMinutes: 4, totalMinutes: 10, now: now),
                runningSnapshot(id: "stub-2", remainingMinutes: 4, totalMinutes: 50, now: now),
                exceededSnapshot(id: "stub-3", overdueMinutes: 4, now: now),
                exceededSnapshot(id: "stub-4", overdueMinutes: 4, now: now),
            ]
        )
    }

    /// Placeholder used by `#Preview(as:)` in `TimerWidget.swift`.
    static func placeholderSmall() -> TimerWidgetEntry {
        placeholderOne()
    }

    // MARK: - Snapshot builders

    private static func runningSnapshot(
        id: String,
        remainingMinutes: Int,
        totalMinutes: Int,
        recipeName: String? = nil,
        now: Date
    ) -> TimerSnapshot {
        TimerSnapshot(
            id: id,
            name: "Step",
            recipeId: nil,
            recipeName: recipeName,
            endDate: now.addingTimeInterval(TimeInterval(remainingMinutes * 60)),
            pausedRemainingSeconds: nil,
            phase: .running,
            totalDurationSeconds: TimeInterval(totalMinutes * 60)
        )
    }

    private static func exceededSnapshot(
        id: String,
        overdueMinutes: Int,
        totalMinutes: Int = 10,
        recipeName: String? = nil,
        now: Date
    ) -> TimerSnapshot {
        TimerSnapshot(
            id: id,
            name: "Step",
            recipeId: nil,
            recipeName: recipeName,
            endDate: now.addingTimeInterval(-TimeInterval(overdueMinutes * 60)),
            pausedRemainingSeconds: nil,
            phase: .exceeded,
            totalDurationSeconds: TimeInterval(totalMinutes * 60)
        )
    }
}

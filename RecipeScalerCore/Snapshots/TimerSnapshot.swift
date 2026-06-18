//
//  TimerSnapshot.swift
//  RecipeScalerCore
//
//  Read-only snapshot of a cooking timer, mirrored into the App Group
//  by the main app and consumed by `HomeWidgetExtension`.
//
//  Spec 030 — TimerWidget: contract is intentionally minimal so the widget
//  extension never depends on SwiftData or the main app's model layer.
//

import Foundation

/// Lifecycle phase of a timer at the moment the snapshot was captured.
public enum TimerSnapshotPhase: String, Codable, Hashable, Sendable {
    case running
    case paused
    case exceeded
}

/// Immutable view of a single cooking timer.
public struct TimerSnapshot: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let recipeId: String?
    public let recipeName: String?

    /// End date for a running timer — drives `Text(timerInterval:)` so the widget
    /// counts down live without its own timer. `nil` when paused.
    public let endDate: Date?

    /// Remaining seconds captured at pause time. `nil` unless `phase == .paused`.
    public let pausedRemainingSeconds: Int?

    public let phase: TimerSnapshotPhase

    /// Original full duration. Used by the widget to compute progress fraction
    /// and resolve the accent (`soon` when remaining < 10%).
    public let totalDurationSeconds: TimeInterval

    public init(
        id: String,
        name: String,
        recipeId: String?,
        recipeName: String?,
        endDate: Date?,
        pausedRemainingSeconds: Int?,
        phase: TimerSnapshotPhase,
        totalDurationSeconds: TimeInterval
    ) {
        self.id = id
        self.name = name
        self.recipeId = recipeId
        self.recipeName = recipeName
        self.endDate = endDate
        self.pausedRemainingSeconds = pausedRemainingSeconds
        self.phase = phase
        self.totalDurationSeconds = totalDurationSeconds
    }

    /// Seconds remaining at `now`. Negative when the timer has overrun (`phase == .exceeded`).
    public func remainingSeconds(now: Date = Date()) -> Int {
        switch phase {
        case .running:
            // TP14 [review #14]: guard NaN/Inf/overflow before Int cast.
            // `totalDurationSeconds` comes from app-internal state (bounded in
            // practice) but defensive guards keep the widget/Live Activity alive
            // if a malformed snapshot slips through.
            guard totalDurationSeconds.isFinite else { return 0 }
            guard let endDate else { return Self.clampingInt(totalDurationSeconds) }
            return Self.clampingInt(endDate.timeIntervalSince(now).rounded())
        case .paused:
            return pausedRemainingSeconds ?? 0
        case .exceeded:
            guard let endDate else { return 0 }
            return Self.clampingInt(endDate.timeIntervalSince(now).rounded())
        }
    }

    /// NaN/Infinity → 0; values outside Int range clamped to the nearest bound.
    /// Local copy of `Int(clampingFinite:)` (Core cannot depend on Native's
    /// `SafeIntCasts.swift`). See review #14.
    private static func clampingInt(_ value: Double) -> Int {
        if value.isNaN || value.isInfinite { return 0 }
        if value >= Double(Int.max) { return Int.max }
        if value <= Double(Int.min) { return Int.min }
        return Int(value)
    }
}

/// Top-level container serialized into the App Group.
public struct TimerSnapshotDocument: Codable, Hashable, Sendable {
    public let timers: [TimerSnapshot]
    public let generatedAt: Date

    public init(timers: [TimerSnapshot], generatedAt: Date) {
        self.timers = timers
        self.generatedAt = generatedAt
    }

    public static let empty = TimerSnapshotDocument(timers: [], generatedAt: .distantPast)
}

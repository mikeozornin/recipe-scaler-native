//
//  TimerSnapshot+ServerActiveTimer.swift
//  RecipeScalerCore
//
//  Spec 030 Phase B3 — map `GET /api/v1/timers/active` payloads into the
//  App Group snapshot consumed by `TimerWidgetProvider` and silent wake.
//

import Foundation

extension TimerSnapshot {
    /// Build a widget snapshot from a server active-timer row.
    public init(from server: ServerActiveTimer, now: Date = Date()) {
        let phase: TimerSnapshotPhase
        let endDate: Date?
        let pausedSeconds: Int?

        if server.isPaused {
            phase = .paused
            endDate = nil
            pausedSeconds = server.remainingSeconds(at: now)
        } else if let endMs = server.endTime {
            let end = Date(timeIntervalSince1970: TimeInterval(endMs) / 1000)
            phase = end > now ? .running : .exceeded
            endDate = end
            pausedSeconds = nil
        } else {
            // No endTime while not paused — treat as running with a synthetic end.
            let remaining = max(0, server.remainingSeconds(at: now))
            phase = remaining > 0 ? .running : .exceeded
            endDate = now.addingTimeInterval(TimeInterval(remaining))
            pausedSeconds = nil
        }

        self.init(
            id: server.timerId,
            name: server.name,
            recipeId: server.recipeId,
            recipeName: nil,
            endDate: endDate,
            pausedRemainingSeconds: pausedSeconds,
            phase: phase,
            totalDurationSeconds: TimeInterval(server.duration)
        )
    }
}

extension TimerSnapshotDocument {
    /// Map server active timers → top-4 snapshot document (TimerOrdering parity).
    public init(from servers: [ServerActiveTimer], now: Date = Date()) {
        let sorted = TimerOrdering.sortActive(
            servers,
            now: now,
            isPaused: { $0.isPaused },
            remainingSeconds: { timer, date in timer.remainingSeconds(at: date) }
        )
        let snapshots = sorted.prefix(4).map { TimerSnapshot(from: $0, now: now) }
        self.init(timers: Array(snapshots), generatedAt: now)
    }
}

/// Pure network-refresh decision helper — unit-testable without WidgetKit.
public enum TimerWidgetNetworkRefresh {
    /// Skip HTTP when App Group snapshot is newer than this (review #3 / #4).
    public static let networkTTL: TimeInterval = 45

    public enum Outcome: Equatable {
        case updated(TimerSnapshotDocument)
        case keptExisting(TimerSnapshotDocument)
        case skippedNoAuth(TimerSnapshotDocument)
        case skippedPendingLocal(TimerSnapshotDocument)
    }

    /// Whether Provider should call `/api/v1/timers/active` at all.
    public static func shouldFetch(
        existing: TimerSnapshotDocument,
        hasPendingLocal: Bool,
        now: Date = Date(),
        ttl: TimeInterval = networkTTL
    ) -> Bool {
        if hasPendingLocal { return false }
        return now.timeIntervalSince(existing.generatedAt) > ttl
    }

    /// Apply fetch result to `existing` without clearing on failure / no auth.
    ///
    /// Even after a successful HTTP response, pending-local Intent writes win
    /// (review finding #1 — optimistic Lock Screen pause must not snap back).
    public static func apply(
        bearer: String?,
        existing: TimerSnapshotDocument,
        fetchResult: Result<[ServerActiveTimer], Error>,
        hasPendingLocal: Bool = false,
        now: Date = Date()
    ) -> Outcome {
        let trimmed = bearer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return .skippedNoAuth(existing)
        }
        if hasPendingLocal {
            return .skippedPendingLocal(existing)
        }
        switch fetchResult {
        case .success(let timers):
            return .updated(TimerSnapshotDocument(from: timers, now: now))
        case .failure:
            return .keptExisting(existing)
        }
    }
}

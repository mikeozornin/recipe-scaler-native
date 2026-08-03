//
//  TimerSnapshotDocumentPatcher.swift
//  RecipeScalerCore
//
// Spec 030 Phase A — Intent (and later Provider) merge a single timer into the
// App Group snapshot without wiping siblings, then keep top-4 ordering.
//

import Foundation

/// Load → patch one timer → top-4 → save for `TimerSnapshotDocument`.
public enum TimerSnapshotDocumentPatcher {
    public static let maxTimers = 4

    /// Pure merge: replace or insert `snapshot` by id, sort, truncate to top-4.
    public static func patching(
        _ document: TimerSnapshotDocument,
        with snapshot: TimerSnapshot,
        now: Date = Date()
    ) -> TimerSnapshotDocument {
        var timers = document.timers.filter { $0.id != snapshot.id }
        timers.append(snapshot)
        let sorted = TimerOrdering.sortActive(
            timers,
            now: now,
            isPaused: { $0.phase == .paused },
            remainingSeconds: { timer, date in timer.remainingSeconds(now: date) }
        )
        let top = Array(sorted.prefix(maxTimers))
        return TimerSnapshotDocument(timers: top, generatedAt: now)
    }

    /// Load existing document, patch, save. Injectable load/save for unit tests.
    @discardableResult
    public static func applyAndSave(
        snapshot: TimerSnapshot,
        now: Date = Date(),
        load: () -> TimerSnapshotDocument = { TimerSnapshotStore.load() },
        save: (TimerSnapshotDocument) -> Void = { TimerSnapshotStore.save($0) }
    ) -> TimerSnapshotDocument {
        let next = patching(load(), with: snapshot, now: now)
        save(next)
        return next
    }
}

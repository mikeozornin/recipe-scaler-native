//
//  TimerSnapshotStore.swift
//  RecipeScalerCore
//
//  App Group bridge between the main app (writer) and `HomeWidgetExtension` (reader).
//
//  Spec 030 — the writer side is invoked by `TimerManager` on every timer mutation;
//  the reader side is invoked by `TimerWidgetProvider` on every timeline reload.
//

import Foundation

public enum TimerSnapshotStore {
    /// UserDefaults key under the shared App Group suite.
    private static let key = "widgets.timerSnapshot"

    private static var defaults: UserDefaults? {
        AppGroup.userDefaults
    }

    /// Persist a snapshot document. Writes propagate to every process in the App Group.
    public static func save(_ document: TimerSnapshotDocument) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(document) else { return }
        defaults?.set(data, forKey: key)
    }

    /// Read the latest snapshot, or `.empty` when no data is present or decoding fails.
    ///
    /// Decoding is intentionally defensive: any schema drift or corruption yields `.empty`,
    /// mirroring the pattern in `ShoppingListSnapshotStore`.
    public static func load() -> TimerSnapshotDocument {
        guard let data = defaults?.data(forKey: key) else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(TimerSnapshotDocument.self, from: data)) ?? .empty
    }

    /// Remove the stored snapshot (e.g. on sign-out).
    public static func clear() {
        defaults?.removeObject(forKey: key)
    }
}

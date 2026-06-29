//
//  WatchFeatureAdoptionReporter.swift
//  RecipeScalerNativeWatch Watch App
//
//  Client-reported `installed_watch_app` flag (spec 038 extension).
//  Fires once when the watch app opens with an active session.
//

import Foundation
import RecipeScalerCore

enum WatchFeatureAdoptionReporter {
    private static let featureKey = "installed_watch_app"
    private static let reportedKeyPrefix = "feature-adoption.watch-app-opened-reported."

    private static let lock = NSLock()
    private static var inFlightUserIds = Set<String>()

    /// Idempotent POST to `/api/users/me/feature-adoption`. Retries on next open
    /// if the network call fails before the per-user reported flag is set.
    static func reportFirstOpenIfNeeded() {
        guard let reportingUserId = WatchCredentialsStore.userId else { return }
        let reportedKey = reportedKey(for: reportingUserId)
        guard !UserDefaults.standard.bool(forKey: reportedKey) else { return }

        lock.lock()
        guard !inFlightUserIds.contains(reportingUserId) else {
            lock.unlock()
            return
        }
        inFlightUserIds.insert(reportingUserId)
        lock.unlock()

        Task {
            defer {
                lock.lock()
                inFlightUserIds.remove(reportingUserId)
                lock.unlock()
            }

            guard WatchCredentialsStore.userId == reportingUserId else { return }

            do {
                try await FeatureAdoptionAPI.markFeatureAdoption(featureKey)
                guard WatchCredentialsStore.userId == reportingUserId else { return }
                UserDefaults.standard.set(true, forKey: reportedKey)
            } catch {
                // Leave reportedKey unset; retry on next bootstrap / userId delivery.
            }
        }
    }

    /// Clears the local idempotency flag when iPhone sends a credential purge.
    static func clearLocalReport(for userId: String) {
        UserDefaults.standard.removeObject(forKey: reportedKey(for: userId))
        lock.lock()
        inFlightUserIds.remove(userId)
        lock.unlock()
    }

    private static func reportedKey(for userId: String) -> String {
        reportedKeyPrefix + userId
    }
}

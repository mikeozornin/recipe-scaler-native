//
//  WatchFeatureAdoptionReporter.swift
//  RecipeScalerNativeWatch Watch App
//
//  Client-reported `installed_watch_app` flag (spec 038 extension).
//  Fires once when the watch app opens with an active session.
//

import Foundation
import os
import RecipeScalerCore

enum WatchFeatureAdoptionReporter {
    private static let feature: FeatureAdoptionClientFeature = .installedWatchApp
    private static let reportedKeyPrefix = "feature-adoption.watch-app-opened-reported."
    private static let logger = Logger(subsystem: "com.recipescaler.watch", category: "FeatureAdoption")

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

        Task(priority: .utility) {
            defer {
                lock.lock()
                inFlightUserIds.remove(reportingUserId)
                lock.unlock()
            }

            guard WatchCredentialsStore.userId == reportingUserId else { return }

            do {
                try await FeatureAdoptionAPI.markFeatureAdoption(
                    feature,
                    userId: reportingUserId
                )
                guard WatchCredentialsStore.userId == reportingUserId else { return }
                UserDefaults.standard.set(true, forKey: reportedKey)
            } catch {
                logger.error(
                    "installed_watch_app POST failed: \(error.localizedDescription, privacy: .public)"
                )
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

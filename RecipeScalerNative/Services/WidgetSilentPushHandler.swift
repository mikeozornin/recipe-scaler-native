//
//  WidgetSilentPushHandler.swift
//  RecipeScalerNative
//
//  Spec 030 Phase B4 — silent `content-available` wake → fetch active timers →
//  snapshot save → reloadTimelines. Must not interfere with alert push (023).
//

import Foundation
import WidgetKit
import RecipeScalerCore

enum WidgetSilentPushHandler {
    /// Reasons accepted in the silent payload data dictionary (contract widget-push.md).
    static let refreshReasons: Set<String> = ["timers", "widget-refresh"]

    /// Whether this remote notification should trigger a widget snapshot refresh.
    ///
    /// - Pure silent (`content-available` without `alert`) → yes.
    /// - Explicit `reason: timers|widget-refresh` → yes (even if alert also present).
    /// - Alert-only timer-completed (023) without content-available → no
    ///   (system + UNUserNotificationCenter handle presentation; we do not touch it).
    static func shouldRefreshWidget(userInfo: [AnyHashable: Any]) -> Bool {
        let reason = (userInfo["reason"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let reason, refreshReasons.contains(reason) {
            return true
        }

        guard let aps = userInfo["aps"] as? [String: Any] else { return false }
        let contentAvailable =
            (aps["content-available"] as? Int) == 1
            || (aps["content-available"] as? Bool) == true
        guard contentAvailable else { return false }

        // Pure silent — no alert payload.
        return aps["alert"] == nil
    }

    /// Fetch active timers, save snapshot, reload TimerWidget timelines.
    /// Returns whether new data was written (for `UIBackgroundFetchResult`).
    ///
    /// Honours the same `pendingLocal` + `apply` gate as `TimerWidgetProvider`
    /// so a silent wake during the Intent → TimerManager drain window cannot
    /// overwrite an optimistic Lock Screen pause (review finding #1).
    @MainActor
    static func refreshSnapshotFromServer() async -> Bool {
        guard let bearer = SharedAuthStore.token?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bearer.isEmpty else {
            AppLog.notice(.push, "widget_silent_refresh_skipped_no_auth")
            return false
        }

        if TimerSnapshotStore.hasPendingLocalMutation() {
            AppLog.info(.push, "widget_silent_refresh_skipped_pending_local")
            return false
        }

        APIClient.shared.configure(authToken: bearer)
        if let userId = SharedAuthStore.userId, !userId.isEmpty {
            APIClient.shared.configure(userId: userId)
        }

        let existing = TimerSnapshotStore.load()
        let fetchResult: Result<[ServerActiveTimer], Error>
        do {
            let response: ActiveTimersResponse = try await APIClient.shared.performDecodable(
                path: "/api/v1/timers/active"
            )
            guard response.success, let timers = response.data?.timers else {
                AppLog.notice(.push, "widget_silent_refresh_empty_payload")
                return false
            }
            fetchResult = .success(timers)
        } catch {
            fetchResult = .failure(error)
        }

        let applyNow = Date()
        switch TimerWidgetNetworkRefresh.apply(
            bearer: bearer,
            existing: existing,
            fetchResult: fetchResult,
            hasPendingLocal: TimerSnapshotStore.hasPendingLocalMutation(now: applyNow),
            now: applyNow
        ) {
        case .updated(let document):
            TimerSnapshotStore.save(document)
            WidgetCenter.shared.reloadTimelines(ofKind: TimerWidgetKind.id)
            AppLog.info(.push, "widget_silent_refresh_ok", data: [
                "timerCount": "\(document.timers.count)",
                "previousCount": "\(existing.timers.count)"
            ])
            return true
        case .keptExisting:
            if case .failure(let error) = fetchResult {
                AppLog.notice(.push, "widget_silent_refresh_failed", data: [
                    "error": error.localizedDescription
                ])
            }
            return false
        case .skippedNoAuth(existing: _):
            AppLog.notice(.push, "widget_silent_refresh_skipped_no_auth_apply")
            return false
        case .skippedPendingLocal(existing: _):
            AppLog.info(.push, "widget_silent_refresh_skipped_pending_local_apply")
            return false
        }
    }
}

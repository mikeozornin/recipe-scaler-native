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

    /// Outcome of a silent-push snapshot refresh, mapped 1:1 to
    /// `UIBackgroundFetchResult` by `AppDelegate`:
    /// - `.newData` → `.newData` (snapshot changed; tells iOS the wake was useful)
    /// - `.noData`  → `.noData`  (intentional skip: signed out, pending-local,
    ///   empty payload, or no change — NOT a failure, do not ask APNs to retry)
    /// - `.transientFailure` → `.failed` (transport/decode error; a retry is useful)
    ///
    /// Reporting `.noData` (not `.failed`) for intentional skips matters: iOS
    /// treats `.failed` as "deliver again with exponential backoff", which
    /// loops forever on signed-out devices and during the 15-s pending-local
    /// window, drains battery, and reduces the system's willingness to deliver
    /// future silent pushes to this install. Code review 2026-08-05, finding #2.
    enum RefreshOutcome {
        case newData
        case noData
        case transientFailure
    }

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
    ///
    /// Honours the same `pendingLocal` + `apply` gate as `TimerWidgetProvider`
    /// so a silent wake during the Intent → TimerManager drain window cannot
    /// overwrite an optimistic Lock Screen pause (review finding #1).
    @MainActor
    static func refreshSnapshotFromServer() async -> RefreshOutcome {
        guard let bearer = SharedAuthStore.token?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bearer.isEmpty else {
            AppLog.notice(.push, "widget_silent_refresh_skipped_no_auth")
            return .noData
        }

        if TimerSnapshotStore.hasPendingLocalMutation() {
            AppLog.info(.push, "widget_silent_refresh_skipped_pending_local")
            return .noData
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
                return .noData
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
            return .newData
        case .keptExisting:
            if case .failure(let error) = fetchResult {
                AppLog.notice(.push, "widget_silent_refresh_failed", data: [
                    "error": error.localizedDescription
                ])
                return .transientFailure
            }
            // Server returned a valid payload that matched the cached snapshot
            // — nothing changed, this is not a failure.
            return .noData
        case .skippedNoAuth(existing: _):
            AppLog.notice(.push, "widget_silent_refresh_skipped_no_auth_apply")
            return .noData
        case .skippedPendingLocal(existing: _):
            AppLog.info(.push, "widget_silent_refresh_skipped_pending_local_apply")
            return .noData
        }
    }
}

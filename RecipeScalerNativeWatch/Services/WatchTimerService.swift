//
//  WatchTimerService.swift
//  RecipeScalerNativeWatch Watch App
//
//  Spec 039 — timer data source for the watch. Talks directly to
//  `/api/v1/timers/active` and `/api/v1/timers/sync` using the stored
//  `userId` (configured on `APIClient.shared`).
//
//  No WebSocket subscription in v1 — after each mutation we re-fetch
//  active timers (debounced via 500ms delay) for cross-device consistency.
//

import Foundation
import RecipeScalerCore

@MainActor
final class WatchTimerService: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded([WatchTimer])
        case empty
        case error
        case notAuthorized
    }

    @Published private(set) var state: LoadState = .idle

    private let api = APIClient.shared

    func refresh() async {
        guard WatchCredentialsStore.userId != nil else {
            state = .notAuthorized
            return
        }
        state = (state.temporaryForLoading)
        do {
            let response: ActiveTimersResponse = try await api.performDecodable(
                path: "/api/v1/timers/active"
            )
            guard response.success, let timers = response.data?.timers else {
                state = .error
                return
            }
            let mapped = Self.sorted(timers.map(WatchTimer.init(server:)))
            state = mapped.isEmpty ? .empty : .loaded(mapped)
        } catch {
            state = .error
        }
    }

    func pause(timerId: String, remaining: Int) async {
        await postEvent(
            type: "timer_paused",
            timerId: timerId,
            data: ["type": "timer_paused", "timerId": timerId, "remaining": remaining]
        )
    }

    func resume(timerId: String) async {
        await postEvent(
            type: "timer_resumed",
            timerId: timerId,
            data: ["type": "timer_resumed", "timerId": timerId]
        )
    }

    func delete(timerId: String) async {
        await postEvent(
            type: "timer_deleted",
            timerId: timerId,
            data: ["type": "timer_deleted", "timerId": timerId]
        )
    }

    /// Optimistic update: flip the matching timer in `state.loaded` before
    /// the POST lands. Caller invokes this immediately, then awaits `pause`.
    func optimisticToggle(timerId: String, now: Date = Date()) {
        guard case var .loaded(timers) = state else { return }
        guard let idx = timers.firstIndex(where: { $0.id == timerId }) else { return }
        var t = timers[idx]
        if t.isPaused {
            t.isPaused = false
            t.pausedRemainingSeconds = nil
        } else {
            t.pausedRemainingSeconds = t.remainingSeconds(now: now)
            t.isPaused = true
            t.endDate = nil
        }
        timers[idx] = t
        state = .loaded(Self.sorted(timers))
    }

    func optimisticRemove(timerId: String) {
        guard case var .loaded(timers) = state else { return }
        timers.removeAll { $0.id == timerId }
        state = timers.isEmpty ? .empty : .loaded(Self.sorted(timers))
    }

    /// Clear local state (logout). UI flips to `.notAuthorized`.
    func clear() {
        state = .notAuthorized
    }

    // MARK: - Internals

    private static func sorted(_ timers: [WatchTimer], now: Date = Date()) -> [WatchTimer] {
        TimerOrdering.sortActive(
            timers,
            now: now,
            isPaused: { $0.isPaused },
            remainingSeconds: { $0.remainingSeconds(now: $1) }
        )
    }

    private func postEvent(
        type: String,
        timerId: String,
        data: [String: Any]
    ) async {
        guard WatchCredentialsStore.userId != nil else { return }

        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        // Body parity with `TimerSyncService.syncPendingEvents` — server expects
        // `data`, not `payload`; iPhone reads `data.remaining` from WebSocket.
        let event: [String: Any] = [
            "timestamp": timestamp,
            "type": type,
            "timerId": timerId,
            "data": data,
        ]
        let body: [String: Any] = [
            "deviceId": Self.storedDeviceId(),
            "events": [event],
            "lastSyncTimestamp": timestamp,
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return }

        do {
            let _: TimerSyncHTTPResponse = try await api.performDecodable(
                path: "/api/v1/timers/sync",
                method: "POST",
                body: bodyData
            )
            // Cross-device consistency: re-fetch after a short delay so the
            // iPhone's WebSocket handler has had time to apply the event.
            try? await Task.sleep(nanoseconds: 500_000_000)
            await refresh()
        } catch {
            // In v1, network failures are silent: optimistic UI remains.
            // A future iteration could surface an inline retry.
        }
    }

    static func storedDeviceId() -> String {
        let key = "watchDeviceId"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: key)
        return new
    }
}

extension WatchTimerService.LoadState {
    /// Preserve loaded content during a refresh (avoids fl.icker to `.loading`).
    var temporaryForLoading: WatchTimerService.LoadState {
        switch self {
        case .loaded, .empty: return self
        default: return .loading
        }
    }
}

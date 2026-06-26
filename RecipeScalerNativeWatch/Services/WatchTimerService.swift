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
            let mapped = timers.map(WatchTimer.init(server:))
            state = mapped.isEmpty ? .empty : .loaded(mapped)
        } catch {
            state = .error
        }
    }

    func pause(timerId: String, remaining: Int) async {
        await postEvent(type: "timer_paused", timerId: timerId, payload: ["remaining": remaining])
    }

    func resume(timerId: String) async {
        await postEvent(type: "timer_resumed", timerId: timerId, payload: [:])
    }

    func delete(timerId: String) async {
        await postEvent(type: "timer_deleted", timerId: timerId, payload: [:])
    }

    /// Optimistic update: flip the matching timer in `state.loaded` before
    /// the POST lands. Caller invokes this immediately, then awaits `pause`.
    func optimisticToggle(timerId: String) {
        guard case var .loaded(timers) = state else { return }
        guard let idx = timers.firstIndex(where: { $0.id == timerId }) else { return }
        var t = timers[idx]
        t.isPaused.toggle()
        // Clearing `endTime` on pause matches the server contract; on resume
        // we leave it nil — the next `refresh()` will populate the new end.
        if t.isPaused { t.endDate = nil }
        timers[idx] = t
        state = .loaded(timers)
    }

    func optimisticRemove(timerId: String) {
        guard case var .loaded(timers) = state else { return }
        timers.removeAll { $0.id == timerId }
        state = timers.isEmpty ? .empty : .loaded(timers)
    }

    /// Clear local state (logout). UI flips to `.notAuthorized`.
    func clear() {
        state = .notAuthorized
    }

    // MARK: - Internals

    private func postEvent(
        type: String,
        timerId: String,
        payload: [String: Any]
    ) async {
        guard WatchCredentialsStore.userId != nil else { return }

        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let event: [String: Any] = [
            "id": "evt_\(timestamp)_\(UUID().uuidString.prefix(8))",
            "timestamp": timestamp,
            "type": type,
            "timerId": timerId,
            "payload": payload,
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

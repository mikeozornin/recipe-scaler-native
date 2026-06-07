//
//  TimerSyncService.swift
//  RecipeScalerNative
//
//  Cross-device timer sync — parity with web `timer-sync-service.ts`.
//

import Foundation
import OSLog
import RecipeScalerCore

// MARK: - Sync event types

enum SyncedTimerEventType: String, Codable {
    case timerCreated = "timer_created"
    case timerStarted = "timer_started"
    case timerPaused = "timer_paused"
    case timerResumed = "timer_resumed"
    case timerDeleted = "timer_deleted"
}

struct TimerSyncQueuedEvent: Codable {
    let id: String
    let timestamp: Int64
    let type: SyncedTimerEventType
    let timerId: String
    let payloadJSON: Data
    var synced: Bool
}

struct TimerSyncPersistedState: Codable {
    var lastSyncAt: Int64
    var pendingEvents: [TimerSyncQueuedEvent]
}

struct ActiveTimersResponse: Decodable {
    struct Payload: Decodable {
        let timers: [ServerActiveTimer]
    }

    let success: Bool
    let data: Payload?
}

struct ServerActiveTimer: Decodable {
    let timerId: String
    let name: String
    let duration: Int
    let endTime: Int64?
    let isPaused: Bool
    let pausedDuration: Int?
    let createdAt: Int64
    let lastUpdated: Int64
    let startedAt: Int64?
    let pausedAt: Int64?
    let recipeId: String?
}

struct TimerSyncHTTPResponse: Decodable {
    struct Payload: Decodable {
        let syncedEvents: [String]?
    }

    let success: Bool
    let data: Payload?
}

// MARK: - Service

@MainActor
final class TimerSyncService {
    static let shared = TimerSyncService()

    private let logger = Logger(subsystem: "com.recipescaler.native", category: "TimerSync")
    private let storageKey = "timer_sync_state"
    private let minSyncInterval: TimeInterval = 2
    private let minLoadInterval: TimeInterval = 2
    private let maxProcessedEvents = 200

    private var state = TimerSyncPersistedState(lastSyncAt: 0, pendingEvents: [])
    private var userId: String?
    private var deviceId: String = ""
    private var lastSyncTime: Date = .distantPast
    private var lastLoadTime: Date = .distantPast
    private var isLoadingTimers = false
    private var syncTask: Task<Void, Never>?
    private var processedEventKeys = Set<String>()

    weak var timerManager: TimerManager?
    var sendTimerEvent: ((SyncedTimerEventType, String, [String: Any]) async -> Bool)?

    private init() {
        loadState()
        deviceId = Self.storedDeviceId()
    }

    static func storedDeviceId() -> String {
        if let existing = UserDefaults.standard.string(forKey: "deviceId"), !existing.isEmpty {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: "deviceId")
        return newId
    }

    func configure(userId: String?, deviceId: String, timerManager: TimerManager) {
        self.userId = userId
        self.deviceId = deviceId
        self.timerManager = timerManager
    }

    func initializeAfterAuth() {
        Task { await loadActiveTimersFromServer() }
    }

    func handleWebSocketPayload(_ payload: [String: Any]) {
        guard let remoteDeviceId = payload["deviceId"] as? String else { return }
        guard remoteDeviceId != deviceId else { return }

        guard let eventTypeRaw = payload["eventType"] as? String,
              let eventType = SyncedTimerEventType(rawValue: eventTypeRaw),
              let timerId = payload["timerId"] as? String
        else { return }

        let timestamp = (payload["timestamp"] as? NSNumber)?.int64Value ?? Int64(Date().timeIntervalSince1970 * 1000)
        let eventKey = "\(timerId)-\(eventTypeRaw)-\(timestamp)"
        guard !processedEventKeys.contains(eventKey) else { return }
        processedEventKeys.insert(eventKey)
        if processedEventKeys.count > maxProcessedEvents {
            processedEventKeys.removeAll()
        }

        let data = payload["data"] as? [String: Any] ?? [:]
        applyRemoteEvent(type: eventType, timerId: timerId, timestamp: timestamp, data: data)
    }

    // MARK: - Outbound queue

    func enqueue(type: SyncedTimerEventType, timerId: String, payload: [String: Any]) {
        guard let encoded = try? JSONSerialization.data(withJSONObject: payload) else { return }

        let queued = TimerSyncQueuedEvent(
            id: "event_\(Int64(Date().timeIntervalSince1970 * 1000))_\(UUID().uuidString.prefix(8))",
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            type: type,
            timerId: timerId,
            payloadJSON: encoded,
            synced: false
        )
        state.pendingEvents.append(queued)
        saveState()

        Task {
            if let sendTimerEvent, await sendTimerEvent(type, timerId, payload) {
                state.pendingEvents.removeAll { $0.id == queued.id }
                saveState()
                return
            }
            await syncPendingEvents()
        }
    }

    func timerCreatedPayload(for timer: RecipeTimer) -> [String: Any] {
        var timerDict: [String: Any] = [
            "id": timer.id,
            "name": timer.name,
            "duration": Int(timer.duration),
            "isRunning": timer.isRunning,
            "isPaused": timer.isPaused,
            "createdAt": ISO8601DateFormatter().string(from: timer.createdAt),
            "type": timer.type.rawValue,
            "lastUpdated": Int64(timer.lastUpdated.timeIntervalSince1970 * 1000),
        ]
        if let recipeId = timer.recipeId { timerDict["recipeId"] = recipeId }
        if let endMs = timer.endTime.map({ Int64($0.timeIntervalSince1970 * 1000) }) {
            timerDict["endTime"] = endMs
        }
        if let startedMs = timer.startedAt.map({ Int64($0.timeIntervalSince1970 * 1000) }) {
            timerDict["startedAt"] = startedMs
        }
        if let remaining = timer.remainingTime { timerDict["remainingTime"] = Int(remaining) }

        return [
            "type": SyncedTimerEventType.timerCreated.rawValue,
            "timerId": timer.id,
            "timer": timerDict,
        ]
    }

    // MARK: - HTTP

    func loadActiveTimersFromServer() async {
        guard userId != nil else { return }
        guard !isLoadingTimers else { return }
        let elapsed = Date().timeIntervalSince(lastLoadTime)
        guard elapsed >= minLoadInterval else { return }

        isLoadingTimers = true
        lastLoadTime = Date()
        defer { isLoadingTimers = false }

        do {
            let response: ActiveTimersResponse = try await APIClient.shared.performDecodable(
                path: "/api/v1/timers/active"
            )
            guard response.success, let timers = response.data?.timers else { return }

            let pendingDeletes = Set(
                state.pendingEvents
                    .filter { $0.type == .timerDeleted && !$0.synced }
                    .map(\.timerId)
            )
            let mapped = timers
                .filter { !pendingDeletes.contains($0.timerId) }
                .map { Self.recipeTimer(from: $0) }

            timerManager?.replaceTimersFromServer(mapped)
            logger.info("Loaded \(mapped.count) active timer(s) from server")
        } catch {
            logger.warning("Failed to load active timers: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func syncPendingEvents() async {
        guard userId != nil else { return }
        let pending = state.pendingEvents.filter { !$0.synced }
        guard !pending.isEmpty else { return }

        let elapsed = Date().timeIntervalSince(lastSyncTime)
        guard elapsed >= minSyncInterval else {
            scheduleSyncDebounced()
            return
        }
        lastSyncTime = Date()

        var bodyEvents: [[String: Any]] = []
        for event in pending {
            guard let object = try? JSONSerialization.jsonObject(with: event.payloadJSON) as? [String: Any] else {
                continue
            }
            if event.type == .timerCreated {
                let timerPayload = object["timer"] as? [String: Any] ?? object
                bodyEvents.append([
                    "type": event.type.rawValue,
                    "timerId": event.timerId,
                    "timestamp": event.timestamp,
                    "data": ["timer": timerPayload],
                ])
            } else {
                bodyEvents.append([
                    "type": event.type.rawValue,
                    "timerId": event.timerId,
                    "timestamp": event.timestamp,
                    "data": object,
                ])
            }
        }
        guard !bodyEvents.isEmpty else { return }

        let body: [String: Any] = [
            "deviceId": deviceId,
            "events": bodyEvents,
            "lastSyncTimestamp": state.lastSyncAt,
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return }

        do {
            let response: TimerSyncHTTPResponse = try await APIClient.shared.performDecodable(
                path: "/api/v1/timers/sync",
                method: "POST",
                body: bodyData
            )
            if response.success, let synced = response.data?.syncedEvents {
                let syncedSet = Set(synced)
                state.pendingEvents.removeAll { event in
                    syncedSet.contains(event.timerId)
                }
                state.lastSyncAt = Int64(Date().timeIntervalSince1970 * 1000)
                saveState()
            }
        } catch {
            logger.warning("Timer sync HTTP failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleSyncDebounced() {
        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(minSyncInterval * 1_000_000_000))
            await syncPendingEvents()
        }
    }

    // MARK: - Remote apply

    private func applyRemoteEvent(
        type: SyncedTimerEventType,
        timerId: String,
        timestamp: Int64,
        data: [String: Any]
    ) {
        guard let manager = timerManager else { return }

        switch type {
        case .timerCreated:
            let timerData = (data["timer"] as? [String: Any]) ?? data
            guard let timer = Self.recipeTimer(fromWebPayload: timerData, timerId: timerId) else { return }
            if let existing = manager.timer(id: timerId),
               Int64(existing.lastUpdated.timeIntervalSince1970 * 1000) > timestamp {
                return
            }
            manager.upsertTimerFromSync(timer)
            if timer.isRunning, !timer.isPaused {
                manager.ensureUpdateLoopRunning()
            }

        case .timerStarted:
            guard var timer = manager.timer(id: timerId) else { return }
            if Int64(timer.lastUpdated.timeIntervalSince1970 * 1000) > timestamp { return }
            let now = Date()
            timer.isRunning = true
            timer.isPaused = false
            timer.startedAt = now
            timer.lastUpdated = now
            timer.pausedAt = nil
            timer.remainingTime = nil
            if let endMs = data["endTime"] as? NSNumber {
                timer.endTime = Date(timeIntervalSince1970: endMs.doubleValue / 1000)
            } else {
                timer.endTime = now.addingTimeInterval(timer.duration)
            }
            manager.upsertTimerFromSync(timer)
            manager.ensureUpdateLoopRunning()

        case .timerPaused:
            guard let timer = manager.timer(id: timerId), timer.isRunning, !timer.isPaused else { return }
            if Int64(timer.lastUpdated.timeIntervalSince1970 * 1000) > timestamp { return }
            let remaining: TimeInterval
            if let rem = data["remaining"] as? NSNumber {
                remaining = rem.doubleValue
            } else {
                remaining = TimeInterval(TimerUtils.remainingSeconds(for: timer))
            }
            timer.pause()
            timer.remainingTime = remaining
            timer.lastUpdated = Date()
            manager.upsertTimerFromSync(timer)
            manager.stopUpdateLoopIfIdle()

        case .timerResumed:
            guard let timer = manager.timer(id: timerId), timer.isPaused else { return }
            if Int64(timer.lastUpdated.timeIntervalSince1970 * 1000) > timestamp { return }
            let now = Date()
            let remaining = timer.remainingTime ?? TimeInterval(TimerUtils.remainingSeconds(for: timer))
            guard remaining > 0 else { return }
            timer.isRunning = true
            timer.isPaused = false
            timer.startedAt = now
            timer.lastUpdated = now
            timer.pausedAt = nil
            if let endMs = data["endTime"] as? NSNumber {
                timer.endTime = Date(timeIntervalSince1970: endMs.doubleValue / 1000)
            } else {
                timer.endTime = now.addingTimeInterval(remaining)
            }
            timer.remainingTime = nil
            manager.upsertTimerFromSync(timer)
            manager.ensureUpdateLoopRunning()

        case .timerDeleted:
            manager.removeTimerFromSync(id: timerId)
        }
    }

    // MARK: - Mapping

    static func recipeTimer(from server: ServerActiveTimer) -> RecipeTimer {
        let isRunning = !server.isPaused && server.startedAt != nil
        let timer = RecipeTimer(
            id: server.timerId,
            name: server.name,
            duration: TimeInterval(server.duration),
            type: .minutes,
            isRunning: isRunning,
            isPaused: server.isPaused,
            createdAt: dateFromMillis(server.createdAt),
            endTime: server.endTime.map { dateFromMillis($0) },
            remainingTime: nil,
            recipeId: server.recipeId,
            lastUpdated: dateFromMillis(server.lastUpdated),
            startedAt: server.startedAt.map { dateFromMillis($0) },
            pausedAt: server.pausedAt.map { dateFromMillis($0) },
            hasCompleted: false
        )
        if server.isPaused, let end = timer.endTime {
            timer.remainingTime = max(0, end.timeIntervalSince(Date()))
        }
        return timer
    }

    static func recipeTimer(fromWebPayload payload: [String: Any], timerId: String) -> RecipeTimer? {
        let name = payload["name"] as? String ?? "Timer"
        let duration = (payload["duration"] as? NSNumber)?.doubleValue ?? 0
        guard duration > 0 else { return nil }

        let typeRaw = payload["type"] as? String ?? "minutes"
        let type = RecipeTimer.TimerType(rawValue: typeRaw) ?? .minutes
        let isRunning = payload["isRunning"] as? Bool ?? false
        let isPaused = payload["isPaused"] as? Bool ?? false

        let createdAt: Date
        if let iso = payload["createdAt"] as? String {
            createdAt = ISO8601DateFormatter().date(from: iso) ?? Date()
        } else {
            createdAt = Date()
        }

        let lastUpdatedMs = (payload["lastUpdated"] as? NSNumber)?.doubleValue
            ?? Date().timeIntervalSince1970 * 1000

        let timer = RecipeTimer(
            id: timerId,
            name: name,
            duration: duration,
            type: type,
            isRunning: isRunning,
            isPaused: isPaused,
            createdAt: createdAt,
            endTime: millisDate(payload["endTime"]),
            remainingTime: (payload["remainingTime"] as? NSNumber).map { $0.doubleValue },
            recipeId: payload["recipeId"] as? String,
            lastUpdated: Date(timeIntervalSince1970: lastUpdatedMs / 1000),
            startedAt: millisDate(payload["startedAt"]),
            pausedAt: millisDate(payload["pausedAt"]),
            hasCompleted: payload["hasCompleted"] as? Bool ?? false
        )
        return timer
    }

    private static func millisDate(_ value: Any?) -> Date? {
        guard let ms = value as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: ms.doubleValue / 1000)
    }

    private static func dateFromMillis(_ ms: Int64) -> Date {
        Date(timeIntervalSince1970: Double(ms) / 1000)
    }

    // MARK: - Persistence

    private func loadState() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(TimerSyncPersistedState.self, from: data)
        else { return }
        state = decoded
    }

    private func saveState() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

// MARK: - APIClient helper

extension APIClient {
    func performDecodable<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> T {
        let request = try buildRequest(path: path, method: method, body: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
//
//  ServerActiveTimer.swift
//  RecipeScalerCore
//
//  Spec 039 — watchOS Timers: server-side timer contract shared between
//  the main app (`TimerSyncService`), watchOS app, and future surfaces.
//
//  Moved out of `RecipeScalerNative/Services/TimerSyncService.swift` so
//  watchOS can decode `/api/v1/timers/active` and `/api/v1/timers/sync`
//  responses without depending on the main app target.
//

import Foundation

/// Active timer payload returned by `GET /api/v1/timers/active`.
///
/// Field naming matches the JSON contract 1:1 (snake/camel as serialized
/// by the server). Field-level docs — see
/// `specs/039-watchos-timers/contracts/timer-api.md`.
public struct ServerActiveTimer: Decodable, Sendable {
    public let timerId: String
    public let name: String
    public let duration: Int
    public let endTime: Int64?
    public let isPaused: Bool
    public let pausedDuration: Int?
    public let createdAt: Int64
    public let lastUpdated: Int64
    public let startedAt: Int64?
    public let pausedAt: Int64?
    public let recipeId: String?

    public init(
        timerId: String,
        name: String,
        duration: Int,
        endTime: Int64?,
        isPaused: Bool,
        pausedDuration: Int?,
        createdAt: Int64,
        lastUpdated: Int64,
        startedAt: Int64?,
        pausedAt: Int64?,
        recipeId: String?
    ) {
        self.timerId = timerId
        self.name = name
        self.duration = duration
        self.endTime = endTime
        self.isPaused = isPaused
        self.pausedDuration = pausedDuration
        self.createdAt = createdAt
        self.lastUpdated = lastUpdated
        self.startedAt = startedAt
        self.pausedAt = pausedAt
        self.recipeId = recipeId
    }
}

/// `GET /api/v1/timers/active` envelope: `{ "success": Bool, "data": { "timers": [...] } }`.
public struct ActiveTimersResponse: Decodable, Sendable {
    public struct Payload: Decodable, Sendable {
        public let timers: [ServerActiveTimer]
    }

    public let success: Bool
    public let data: Payload?
}

/// `POST /api/v1/timers/sync` envelope: `{ "success": Bool, "data": { "syncedEvents": [...] } }`.
public struct TimerSyncHTTPResponse: Decodable, Sendable {
    public struct Payload: Decodable, Sendable {
        public let syncedEvents: [String]?
    }

    public let success: Bool
    public let data: Payload?
}

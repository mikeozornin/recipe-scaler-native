//
//  RecipeTimer.swift
//  RecipeScalerNative
//
//

import Foundation
import SwiftData

@Model
final class RecipeTimer {
    @Attribute(.unique) var id: String
    var name: String
    var duration: TimeInterval // in seconds
    var type: TimerType
    var isRunning: Bool
    var isPaused: Bool
    var createdAt: Date
    var endTime: Date?
    var remainingTime: TimeInterval?
    var recipeId: String?
    var lastUpdated: Date
    var startedAt: Date?
    var pausedAt: Date?
    var hasCompleted: Bool

    enum TimerType: String, Codable {
        case hours
        case minutes
        case seconds
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        duration: TimeInterval,
        type: TimerType = .minutes,
        isRunning: Bool = false,
        isPaused: Bool = false,
        createdAt: Date = Date(),
        endTime: Date? = nil,
        remainingTime: TimeInterval? = nil,
        recipeId: String? = nil,
        lastUpdated: Date = Date(),
        startedAt: Date? = nil,
        pausedAt: Date? = nil,
        hasCompleted: Bool = false
    ) {
        self.id = id
        self.name = name
        self.duration = duration
        self.type = type
        self.isRunning = isRunning
        self.isPaused = isPaused
        self.createdAt = createdAt
        self.endTime = endTime
        self.remainingTime = remainingTime
        self.recipeId = recipeId
        self.lastUpdated = lastUpdated
        self.startedAt = startedAt
        self.pausedAt = pausedAt
        self.hasCompleted = hasCompleted
    }
}

// MARK: - Timer Controls
extension RecipeTimer {
    func start() {
        isRunning = true
        isPaused = false
        startedAt = Date()
        endTime = Date().addingTimeInterval(duration)
        remainingTime = duration
        lastUpdated = Date()
    }

    func pause() {
        guard isRunning else { return }
        isPaused = true
        isRunning = false
        pausedAt = Date()

        if let endTime = endTime {
            remainingTime = endTime.timeIntervalSince(Date())
        }
        lastUpdated = Date()
    }

    func resume() {
        guard isPaused, let remaining = remainingTime else { return }
        isRunning = true
        isPaused = false
        endTime = Date().addingTimeInterval(remaining)
        lastUpdated = Date()
    }

    func stop() {
        isRunning = false
        isPaused = false
        endTime = nil
        remainingTime = nil
        lastUpdated = Date()
    }

    func complete() {
        hasCompleted = true
        isRunning = false
        isPaused = false
        endTime = nil
        remainingTime = 0
        lastUpdated = Date()
    }
}

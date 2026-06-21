//
//  TimerNotificationSmokeTest.swift
//  RecipeScalerNative
//
//  DEBUG simulator smoke: exercises +1 / +5 / delete paths used by UN notification actions.
//

import Foundation
import UserNotifications

#if DEBUG
enum TimerNotificationSmokeTest {
    struct Result: Codable {
        var passed: Bool
        var finished: Bool
        var steps: [String: Bool]
        var error: String?
    }

    static var shouldRun: Bool {
        #if targetEnvironment(simulator)
        for arg in ProcessInfo.processInfo.arguments {
            if arg == "-TimerNotificationSmokeTest" || arg == "-TimerNotificationSmokeTest=1" { return true }
            if arg.hasPrefix("-TimerNotificationSmokeTest=") {
                let value = String(arg.dropFirst("-TimerNotificationSmokeTest=".count))
                return value == "1" || value.lowercased() == "true"
            }
        }
        #endif
        return false
    }

    @MainActor
    enum Launcher {
        private static var didStart = false

        static func launchIfNeeded(timerManager: TimerManager) {
            guard shouldRun, !didStart else { return }
            didStart = true
            Task { await run(timerManager: timerManager) }
        }
    }

    @MainActor
    private static var didFinish = false

    @MainActor
    private static func run(timerManager: TimerManager) async {
        var steps: [String: Bool] = [:]
        var lastError: String?

        defer {
            if !didFinish {
                writeResult(
                    Result(
                        passed: false,
                        finished: true,
                        steps: steps.merging(["aborted": true]) { $1 },
                        error: lastError ?? "smoke_task_cancelled"
                    )
                )
            }
        }

        let categories = await UNUserNotificationCenter.current().notificationCategories()
        let timerCategory = categories.first { $0.identifier == TimerManager.timerCompleteCategoryIdentifier }
        let actionIds = Set(timerCategory?.actions.map(\.identifier) ?? [])
        steps["categoryRegistered"] = actionIds.contains(TimerManager.addActionOneMinuteIdentifier)
            && actionIds.contains(TimerManager.addActionFiveMinutesIdentifier)
            && actionIds.contains(TimerManager.deleteTimerIdentifier)
        writeProgress(steps: steps)

        let timer = timerManager.createAndStartTimer(
            name: "Notif QA",
            duration: 3,
            type: .seconds
        )
        steps["timerCreated"] = timerManager.activeTimers.contains { $0.id == timer.id }
        writeProgress(steps: steps)

        // Wait for natural completion when the update loop ticks; fall back to the
        // post-completion state notification actions see (zero remaining, completed).
        for _ in 0..<24 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if timer.hasCompleted { break }
        }
        if !timer.hasCompleted, let end = timer.endTime, end.timeIntervalSinceNow <= 0 {
            timer.hasCompleted = true
            timer.isRunning = false
            timer.remainingTime = 0
        }
        steps["timerCompleted"] = timer.hasCompleted
        writeProgress(steps: steps)

        guard timer.hasCompleted else {
            lastError = "timer did not reach completed state within 12s"
            didFinish = true
            writeResult(Result(passed: false, finished: true, steps: steps, error: lastError))
            return
        }

        let beforeOne = timer.remainingTime ?? 0
        timerManager.addTime(id: timer.id, minutes: 1)
        guard let afterAddOne = timerManager.timers.first(where: { $0.id == timer.id }) else {
            lastError = "timer missing after addOneMinute"
            didFinish = true
            writeResult(Result(passed: false, finished: true, steps: steps, error: lastError))
            return
        }
        let afterOne = afterAddOne.remainingTime ?? 0
        steps["addOneMinute"] = !afterAddOne.hasCompleted
            && afterAddOne.isRunning
            && afterOne > beforeOne
            && timerManager.activeTimers.contains { $0.id == timer.id }
        writeProgress(steps: steps)

        let beforeFive = afterAddOne.remainingTime ?? 0
        timerManager.addTime(id: timer.id, minutes: 5)
        guard let afterAddFive = timerManager.timers.first(where: { $0.id == timer.id }) else {
            lastError = "timer missing after addFiveMinutes"
            didFinish = true
            writeResult(Result(passed: false, finished: true, steps: steps, error: lastError))
            return
        }
        let afterFive = afterAddFive.remainingTime ?? 0
        steps["addFiveMinutes"] = !afterAddFive.hasCompleted
            && (afterFive - beforeFive) >= 290
        writeProgress(steps: steps)

        timerManager.deleteTimer(id: timer.id)
        steps["deleteTimer"] = !timerManager.activeTimers.contains { $0.id == timer.id }

        let passed = steps["categoryRegistered"] == true
            && steps["timerCreated"] == true
            && steps["timerCompleted"] == true
            && steps["addOneMinute"] == true
            && steps["addFiveMinutes"] == true
            && steps["deleteTimer"] == true

        didFinish = true
        writeResult(Result(passed: passed, finished: true, steps: steps, error: lastError))
    }

    private static func writeProgress(steps: [String: Bool]) {
        writeResult(Result(passed: false, finished: false, steps: steps, error: nil))
    }

    static func writeResult(_ result: Result) {
        guard let data = try? JSONEncoder().encode(result) else { return }
        let url = resultURL()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    static func resultURL() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("timer-notification-smoke-result.json")
    }
}
#endif

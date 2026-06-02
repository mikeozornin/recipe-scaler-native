//
//  TimerManager.swift
//  RecipeScalerNative
//
//

import Foundation
import UIKit
import UserNotifications
import BackgroundTasks
import SwiftData

// MARK: - Timer Manager
@MainActor
final class TimerManager: NSObject, ObservableObject {
    static let shared = TimerManager()

    // MARK: - Properties
    @Published private(set) var timers: [RecipeTimer] = []
    @Published private(set) var activeTimers: [RecipeTimer] = []

    private let modelContext: ModelContext?
    private var updateTimer: Timer?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var backgroundTask: BackgroundTask?

    private let notificationCenter = UNUserNotificationCenter.current()
    private let timerUpdateInterval: TimeInterval = 0.5 // Update UI every 0.5 seconds

    private static let backgroundTaskIdentifier = "com.recipescaler.timerUpdate"
    private static var didRegisterBackgroundTasks = false

    /// Must run from `RecipeScalerNativeApp.init()` before the app finishes launching.
    static func registerBackgroundTasksIfNeeded() {
        guard !didRegisterBackgroundTasks else { return }
        didRegisterBackgroundTasks = true
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { task in
            Task { @MainActor in
                shared.handleBackgroundTask(task as! BGProcessingTask)
            }
        }
    }

    // MARK: - Initialization
    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
        super.init()
        setupNotifications()
        loadTimers()
    }

    // MARK: - Setup Methods
    private func setupNotifications() {
        // Request authorization but don't register for remote notifications during init
        // Remote notifications should be registered after app fully launches
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error.localizedDescription)")
            }
        }

        // Handle notification taps
        notificationCenter.delegate = self
    }

    private func loadTimers() {
        guard let modelContext = modelContext else { return }

        do {
            let descriptor = FetchDescriptor<RecipeTimer>(
                predicate: #Predicate { !$0.hasCompleted }
            )
            let loadedTimers = try modelContext.fetch(descriptor)
            self.timers = loadedTimers
            updateActiveTimers()
        } catch {
            print("Error loading timers: \(error.localizedDescription)")
        }
    }

    // MARK: - Timer Creation
    func createTimer(name: String, duration: TimeInterval, type: RecipeTimer.TimerType) -> RecipeTimer {
        let timer = RecipeTimer(
            name: name,
            duration: duration,
            type: type
        )

        timers.append(timer)
        saveTimer(timer)
        return timer
    }

    // MARK: - Timer Controls
    func startTimer(id: String) {
        guard let timer = timers.first(where: { $0.id == id }) else { return }

        timer.start()
        saveTimer(timer)
        updateActiveTimers()
        startUpdateTimer()

        // Schedule background task
        scheduleBackgroundTask()
    }

    func pauseTimer(id: String) {
        guard let timer = timers.first(where: { $0.id == id }) else { return }

        timer.pause()
        saveTimer(timer)
        updateActiveTimers()

        if activeTimers.isEmpty {
            stopUpdateTimer()
        }
    }

    func resumeTimer(id: String) {
        guard let timer = timers.first(where: { $0.id == id }) else { return }

        timer.resume()
        saveTimer(timer)
        updateActiveTimers()
        startUpdateTimer()

        // Schedule background task
        scheduleBackgroundTask()
    }

    func deleteTimer(id: String) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }

        let timer = timers[index]
        timers.remove(at: index)

        // Cancel notification if scheduled
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [timer.id])

        deleteTimer(timer)
        updateActiveTimers()

        if activeTimers.isEmpty {
            stopUpdateTimer()
        }
    }

    func resetTimer(id: String) {
        guard let timer = timers.first(where: { $0.id == id }) else { return }

        timer.stop()
        saveTimer(timer)
        updateActiveTimers()

        if activeTimers.isEmpty {
            stopUpdateTimer()
        }
    }

    // MARK: - Active Timers Management
    private func updateActiveTimers() {
        let active = timers.filter { $0.isRunning }
        self.activeTimers = active
    }

    // MARK: - Timer Update Loop
    private func startUpdateTimer() {
        guard updateTimer == nil else { return }

        updateTimer = Timer.scheduledTimer(withTimeInterval: timerUpdateInterval, repeats: true) { [weak self] _ in
            self?.updateRunningTimers()
        }
    }

    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func updateRunningTimers() {
        let now = Date()

        for timer in activeTimers {
            guard timer.isRunning, let endTime = timer.endTime else { continue }

            let remaining = endTime.timeIntervalSince(now)

            if remaining <= 0 {
                completeTimer(timer)
            } else {
                timer.remainingTime = remaining
            }
        }

        objectWillChange.send()
    }

    // MARK: - Timer Completion
    private func completeTimer(_ timer: RecipeTimer) {
        timer.complete()
        saveTimer(timer)
        updateActiveTimers()

        // Send notification
        sendCompletionNotification(for: timer)

        // Stop update timer if no more active timers
        if activeTimers.isEmpty {
            stopUpdateTimer()
        }
    }

    // MARK: - Notifications
    private func sendCompletionNotification(for timer: RecipeTimer) {
        let content = UNMutableNotificationContent()
        content.title = "Timer Complete"
        content.body = "\(timer.name) has finished"
        content.sound = .default
        content.badge = NSNumber(value: UIApplication.shared.applicationIconBadgeNumber + 1)

        // Add custom data
        content.userInfo = [
            "timerId": timer.id,
            "timerName": timer.name
        ]

        // Add action buttons
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_ACTION",
            title: "Snooze 5 min",
            options: []
        )
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS_ACTION",
            title: "Dismiss",
            options: [.destructive]
        )

        let category = UNNotificationCategory(
            identifier: "TIMER_COMPLETE",
            actions: [snoozeAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        notificationCenter.setNotificationCategories([category])
        content.categoryIdentifier = "TIMER_COMPLETE"

        // Schedule notification to show immediately
        let request = UNNotificationRequest(
            identifier: timer.id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )

        notificationCenter.add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Background Task Management
    private func scheduleBackgroundTask() {
        let request = BGProcessingTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Error scheduling background task: \(error.localizedDescription)")
        }
    }

    private func handleBackgroundTask(_ task: BGProcessingTask) {
        // Start background task
        let backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }

        self.backgroundTaskID = backgroundTaskID

        // Update running timers
        updateRunningTimers()

        // Reschedule if there are active timers
        if !activeTimers.isEmpty {
            scheduleBackgroundTask()
        }

        // End background task
        task.setTaskCompleted(success: true)
        endBackgroundTask()
    }

    private func endBackgroundTask() {
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    // MARK: - Data Persistence
    private func saveTimer(_ timer: RecipeTimer) {
        guard let modelContext = modelContext else { return }

        do {
            try modelContext.save()
        } catch {
            print("Error saving timer: \(error.localizedDescription)")
        }
    }

    private func deleteTimer(_ timer: RecipeTimer) {
        guard let modelContext = modelContext else { return }

        do {
            modelContext.delete(timer)
            try modelContext.save()
        } catch {
            print("Error deleting timer: \(error.localizedDescription)")
        }
    }

    // MARK: - Cleanup
    nonisolated deinit {
        Task { @MainActor in
            stopUpdateTimer()
        }
    }
}

// MARK: - UNUserNotificationCenter Delegate
extension TimerManager: UNUserNotificationCenterDelegate {
    // Handle notifications when app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification actions
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        guard let timerId = userInfo["timerId"] as? String else {
            completionHandler()
            return
        }

        switch response.actionIdentifier {
        case "SNOOZE_ACTION":
            Task { @MainActor in
                self.snoozeTimer(id: timerId)
            }
        case "DISMISS_ACTION":
            Task { @MainActor in
                self.deleteTimer(id: timerId)
            }
        case UNNotificationDefaultActionIdentifier:
            // User tapped notification
            Task { @MainActor in
                self.objectWillChange.send()
            }
        default:
            break
        }

        completionHandler()
    }

    // Snooze timer for 5 minutes
    private func snoozeTimer(id: String) {
        guard let timer = timers.first(where: { $0.id == id }) else { return }

        timer.remainingTime = 5 * 60 // 5 minutes in seconds
        timer.endTime = Date().addingTimeInterval(5 * 60)
        timer.isRunning = true
        timer.hasCompleted = false

        saveTimer(timer)
        updateActiveTimers()
        startUpdateTimer()
        scheduleBackgroundTask()
    }
}

// MARK: - Background Task Wrapper (for structured concurrency support)
private final class BackgroundTask {
    private var id: UIBackgroundTaskIdentifier = .invalid

    init() {
        id = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.end()
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }

    deinit {
        end()
    }
}

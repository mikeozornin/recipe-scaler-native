//
//  TimerManager.swift
//  RecipeScalerNative
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

    @Published private(set) var timers: [RecipeTimer] = []
    /// All timers for the mobile panel (sorted like web `TimerPanel`).
    @Published private(set) var activeTimers: [RecipeTimer] = []

    private var modelContext: ModelContext?
    private var updateTimer: Timer?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private let notificationCenter = UNUserNotificationCenter.current()
    private let timerUpdateInterval: TimeInterval = 0.5

    private var serverScheduledPushTimerIds: Set<String> = []

    private static let backgroundTaskIdentifier = "com.recipescaler.timerUpdate"
    private static var didRegisterBackgroundTasks = false

    static func registerBackgroundTasksIfNeeded() {
        guard !didRegisterBackgroundTasks else { return }
        didRegisterBackgroundTasks = true
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { task in
            Task { @MainActor in
                guard let processingTask = task as? BGProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                shared.handleBackgroundTask(processingTask)
            }
        }
    }

    override init() {
        super.init()
        notificationCenter.delegate = self
        registerNotificationCategories()
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadTimers()
        TimerSyncService.shared.timerManager = self
    }

    func notificationAuthorizationStatus() async -> UNAuthorizationStatus {
        await notificationCenter.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestNotificationAuthorization() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
            return granted
        } catch {
            print("Notification authorization error: \(error.localizedDescription)")
            return false
        }
    }

    private func loadTimers() {
        guard let modelContext else { return }
        do {
            let descriptor = FetchDescriptor<RecipeTimer>(
                predicate: #Predicate { !$0.hasCompleted }
            )
            timers = try modelContext.fetch(descriptor)
            refreshPanelTimers()
            if timers.contains(where: \.isRunning) {
                startUpdateTimer()
            }
        } catch {
            print("Error loading timers: \(error.localizedDescription)")
        }
    }

    func timer(id: String) -> RecipeTimer? {
        timers.first { $0.id == id }
    }

    // MARK: - Creation

    @discardableResult
    func createTimer(
        name: String,
        duration: TimeInterval,
        type: RecipeTimer.TimerType = .minutes,
        recipeId: String? = nil
    ) -> RecipeTimer {
        let timer = RecipeTimer(
            id: Self.makeTimerId(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            duration: duration,
            type: type,
            recipeId: recipeId
        )
        insertTimer(timer)
        syncEnqueue(.timerCreated, timer: timer)
        return timer
    }

    @discardableResult
    func createAndStartTimer(
        name: String,
        duration: TimeInterval,
        type: RecipeTimer.TimerType = .minutes,
        recipeId: String? = nil
    ) -> RecipeTimer {
        let timer = RecipeTimer(
            id: Self.makeTimerId(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            duration: duration,
            type: type,
            recipeId: recipeId
        )
        timer.start()
        insertTimer(timer)
        syncEnqueue(.timerCreated, timer: timer)
        startUpdateTimer()
        scheduleBackgroundTask()
        pushSchedule(timer)
        return timer
    }

    // MARK: - Controls

    func startTimer(id: String) {
        guard let timer = timers.first(where: { $0.id == id }), !timer.isRunning else { return }
        timer.start()
        persist(timer)
        refreshPanelTimers()
        startUpdateTimer()
        scheduleBackgroundTask()
        syncEnqueue(.timerStarted, timer: timer, extra: ["endTime": millis(timer.endTime)])
        pushSchedule(timer)
    }

    func pauseTimer(id: String) {
        guard let timer = timers.first(where: { $0.id == id }), timer.isRunning, !timer.isPaused else { return }
        let remaining = TimeInterval(TimerUtils.remainingSeconds(for: timer))
        guard remaining >= 0 else { return }
        timer.pause()
        timer.remainingTime = remaining
        persist(timer)
        refreshPanelTimers()
        stopUpdateLoopIfIdle()
        syncEnqueue(.timerPaused, timer: timer, extra: ["remaining": remaining])
        pushCancel(timer.id)
    }

    func resumeTimer(id: String) {
        guard let timer = timers.first(where: { $0.id == id }), timer.isPaused,
              let remaining = timer.remainingTime, remaining > 0 else { return }
        timer.resume()
        persist(timer)
        refreshPanelTimers()
        startUpdateTimer()
        scheduleBackgroundTask()
        syncEnqueue(.timerResumed, timer: timer, extra: ["endTime": millis(timer.endTime)])
        pushSchedule(timer)
    }

    func deleteTimer(id: String) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        let timer = timers[index]
        timers.remove(at: index)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [timer.id])
        deleteFromStore(timer)
        refreshPanelTimers()
        stopUpdateLoopIfIdle()
        syncEnqueue(.timerDeleted, timer: timer)
        pushCancel(timer.id)
    }

    func resetTimer(id: String) {
        guard let timer = timers.first(where: { $0.id == id }) else { return }
        timer.stop()
        timer.hasCompleted = false
        persist(timer)
        refreshPanelTimers()
        stopUpdateLoopIfIdle()
        pushCancel(timer.id)
    }

    // MARK: - Sync (TimerSyncService)

    func replaceTimersFromServer(_ serverTimers: [RecipeTimer]) {
        guard let modelContext else {
            timers = serverTimers
            refreshPanelTimers()
            if timers.contains(where: \.isRunning) { startUpdateTimer() }
            return
        }
        do {
            let existing = try modelContext.fetch(FetchDescriptor<RecipeTimer>())
            for item in existing {
                modelContext.delete(item)
            }
            timers = []
            for timer in serverTimers {
                modelContext.insert(timer)
                timers.append(timer)
            }
            try modelContext.save()
            refreshPanelTimers()
            if timers.contains(where: \.isRunning) {
                startUpdateTimer()
            } else {
                stopUpdateLoopIfIdle()
            }
        } catch {
            print("Error replacing timers from server: \(error.localizedDescription)")
            timers = serverTimers
            refreshPanelTimers()
        }
    }

    func upsertTimerFromSync(_ timer: RecipeTimer) {
        if let index = timers.firstIndex(where: { $0.id == timer.id }) {
            timers[index] = timer
            persist(timer)
        } else {
            insertTimer(timer, skipSync: true)
        }
        refreshPanelTimers()
    }

    func removeTimerFromSync(id: String) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        let timer = timers[index]
        timers.remove(at: index)
        deleteFromStore(timer)
        refreshPanelTimers()
        stopUpdateLoopIfIdle()
    }

    func ensureUpdateLoopRunning() {
        startUpdateTimer()
        scheduleBackgroundTask()
    }

    func stopUpdateLoopIfIdle() {
        if !timers.contains(where: \.isRunning) {
            stopUpdateTimer()
        }
    }

    // MARK: - Panel

    private func refreshPanelTimers() {
        activeTimers = TimerUtils.sortTimers(timers)
    }

    // MARK: - Update loop

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
        var didChange = false
        for timer in timers where timer.isRunning {
            guard let endTime = timer.endTime else { continue }
            let remaining = endTime.timeIntervalSinceNow
            timer.remainingTime = remaining
            if remaining <= 0, !timer.hasCompleted {
                handleTimerReachedZero(timer)
            }
            didChange = true
        }
        if didChange {
            refreshPanelTimers()
            objectWillChange.send()
        }
    }

    private func handleTimerReachedZero(_ timer: RecipeTimer) {
        guard !timer.hasCompleted else { return }
        timer.hasCompleted = true
        persist(timer)
        sendCompletionNotification(for: timer)
    }

    // MARK: - Push schedule helpers

    private func pushSchedule(_ timer: RecipeTimer) {
        let timerId = timer.id
        let name = timer.name
        let recipeId = timer.recipeId
        let durationSeconds: Int
        if let endTime = timer.endTime, timer.isRunning {
            durationSeconds = Int(max(1, endTime.timeIntervalSinceNow))
        } else {
            durationSeconds = Int(timer.duration)
        }
        Task {
            let ok = await PushScheduleService.shared.schedule(
                timerId: timerId,
                name: name,
                durationSeconds: durationSeconds,
                recipeId: recipeId
            )
            if ok { serverScheduledPushTimerIds.insert(timerId) }
        }
    }

    private func pushCancel(_ timerId: String) {
        serverScheduledPushTimerIds.remove(timerId)
        Task { await PushScheduleService.shared.cancel(timerId: timerId) }
    }

    // MARK: - Notifications

    private func registerNotificationCategories() {
        let snooze = UNNotificationAction(identifier: "SNOOZE_ACTION", title: "Snooze 5 min", options: [])
        let dismiss = UNNotificationAction(identifier: "DISMISS_ACTION", title: "Dismiss", options: [.destructive])
        let timerComplete = UNNotificationCategory(
            identifier: "TIMER_COMPLETE",
            actions: [snooze, dismiss],
            intentIdentifiers: [],
            options: []
        )
        notificationCenter.setNotificationCategories([timerComplete])
    }

    private func sendCompletionNotification(for timer: RecipeTimer) {
        guard TimerNotificationPreferences.isEnabled else { return }
        Task { @MainActor in
            let status = await notificationAuthorizationStatus()
            guard status == .authorized else { return }
            deliverCompletionNotification(for: timer)
        }
    }

    private func deliverCompletionNotification(for timer: RecipeTimer) {
        // Skip local notification when server push was successfully scheduled — it will arrive via APNs.
        if serverScheduledPushTimerIds.contains(timer.id) {
            serverScheduledPushTimerIds.remove(timer.id)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Timer Complete"
        content.body = "\(timer.name) has finished"
        content.sound = .default
        content.userInfo = ["timerId": timer.id, "timerName": timer.name]
        content.categoryIdentifier = "TIMER_COMPLETE"

        let request = UNNotificationRequest(
            identifier: "\(timer.id)-complete",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        notificationCenter.add(request)
    }

    // MARK: - Background

    private func scheduleBackgroundTask() {
        let request = BGProcessingTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleBackgroundTask(_ task: BGProcessingTask) {
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
        updateRunningTimers()
        if timers.contains(where: \.isRunning) {
            scheduleBackgroundTask()
        }
        task.setTaskCompleted(success: true)
        endBackgroundTask()
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    // MARK: - Persistence

    private func insertTimer(_ timer: RecipeTimer, skipSync: Bool = false) {
        modelContext?.insert(timer)
        timers.append(timer)
        persist(timer)
        refreshPanelTimers()
        if skipSync { return }
    }

    private func persist(_ timer: RecipeTimer) {
        guard let modelContext else { return }
        do {
            try modelContext.save()
        } catch {
            print("Error saving timer: \(error.localizedDescription)")
        }
    }

    private func deleteFromStore(_ timer: RecipeTimer) {
        guard let modelContext else { return }
        do {
            modelContext.delete(timer)
            try modelContext.save()
        } catch {
            print("Error deleting timer: \(error.localizedDescription)")
        }
    }

    // MARK: - Sync helpers

    private func syncEnqueue(
        _ type: SyncedTimerEventType,
        timer: RecipeTimer,
        extra: [String: Any] = [:]
    ) {
        var payload: [String: Any]
        switch type {
        case .timerCreated:
            payload = TimerSyncService.shared.timerCreatedPayload(for: timer)
        case .timerStarted, .timerResumed, .timerPaused, .timerDeleted:
            payload = ["type": type.rawValue, "timerId": timer.id]
        }
        for (key, value) in extra {
            payload[key] = value
        }
        TimerSyncService.shared.enqueue(type: type, timerId: timer.id, payload: payload)
    }

    private static func makeTimerId() -> String {
        "timer_\(Int64(Date().timeIntervalSince1970 * 1000))_\(UUID().uuidString.prefix(9).lowercased())"
    }

    private func millis(_ date: Date?) -> Int64? {
        guard let date else { return nil }
        return Int64(date.timeIntervalSince1970 * 1000)
    }

    nonisolated deinit {
        Task { @MainActor in
            stopUpdateTimer()
        }
    }
}

enum TimerNotificationPreferences {
    private static let enabledKey = "timerNotificationsEnabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
}

// MARK: - UNUserNotificationCenter Delegate

extension TimerManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let timerId = userInfo["timerId"] as? String
        let recipeId = userInfo["recipeId"] as? String

        if let timerId {
            switch response.actionIdentifier {
            case "SNOOZE_ACTION":
                Task { @MainActor in self.snoozeTimer(id: timerId) }
            case "DISMISS_ACTION":
                Task { @MainActor in self.deleteTimer(id: timerId) }
            default:
                break
            }
        }

        // Deep link to recipe on notification tap (works for both local and APNs notifications).
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let recipeId, !recipeId.isEmpty {
            NotificationCenter.default.post(
                name: .openRecipe,
                object: nil,
                userInfo: ["recipeId": recipeId]
            )
        }

        completionHandler()
    }

    private func snoozeTimer(id: String) {
        guard let timer = timers.first(where: { $0.id == id }) else { return }
        timer.remainingTime = 5 * 60
        timer.endTime = Date().addingTimeInterval(5 * 60)
        timer.isRunning = true
        timer.isPaused = false
        timer.hasCompleted = false
        persist(timer)
        refreshPanelTimers()
        startUpdateTimer()
        scheduleBackgroundTask()
    }
}
//
//  TimerManager.swift
//  RecipeScalerNative
//

import Foundation
import UIKit
import UserNotifications
import BackgroundTasks
import SwiftData
import WidgetKit
import RecipeScalerCore

// MARK: - Timer Manager
@MainActor
@Observable
final class TimerManager: NSObject {
    /// Shim: returns `AppContainer.shared.timer` when the container is
    /// constructed, otherwise a stand-alone instance.
    static var shared: TimerManager {
        if let container = AppContainer.shared {
            return container.timer
        }
        return Standalone
    }

    private static let Standalone: TimerManager = {
        // Stand-alone instance keeps legacy behaviour for non-app contexts
        // (DEBUG previews, tests). Does not wire timerSync back-references —
        // those happen via AppContainer only.
        let timerSync = TimerSyncService.shared
        return TimerManager(
            timerSync: timerSync,
            liveActivity: TimerLiveActivityCoordinator.shared,
            pushSchedule: PushScheduleService.shared,
            modelContext: ModelContext(RecipeScalerNativeApp.sharedModelContainer)
        )
    }()

    private(set) var timers: [RecipeTimer] = []
    /// All timers for the mobile panel (sorted like web `TimerPanel`).
    private(set) var activeTimers: [RecipeTimer] = []

    /// When `true`, `AppShellView` omits the tab-root timer panel safe-area inset so
    /// nested screens (e.g. description formatting bar) can occupy that slot.
    private(set) var suppressPanelSafeAreaInset = false

    private var modelContext: ModelContext?
    private var updateTimer: Timer?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private let notificationCenter = UNUserNotificationCenter.current()
    private let timerUpdateInterval: TimeInterval = 1.0

    private let timerSync: TimerSyncService
    private let liveActivity: TimerLiveActivityCoordinator
    private let pushSchedule: PushScheduleService

    private var serverScheduledPushTimerIds: Set<String> = []

    private static let backgroundTaskIdentifier = "com.recipescaler.timerUpdate"
    private static var didRegisterBackgroundTasks = false

    // MARK: - Notification identifiers

    static let timerCompleteCategoryIdentifier = "TIMER_COMPLETE"
    static let addActionOneMinuteIdentifier = "ADD_ONE_MINUTE"
    static let addActionFiveMinutesIdentifier = "ADD_FIVE_MINUTES"
    static let deleteTimerIdentifier = "DELETE_TIMER"

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

    init(
        timerSync: TimerSyncService,
        liveActivity: TimerLiveActivityCoordinator,
        pushSchedule: PushScheduleService,
        modelContext: ModelContext
    ) {
        self.timerSync = timerSync
        self.liveActivity = liveActivity
        self.pushSchedule = pushSchedule
        self.modelContext = modelContext
        super.init()
        notificationCenter.delegate = self
        registerNotificationCategories()
        // Cross-reference back to TimerSyncService (formerly done in `configure(modelContext:)`).
        timerSync.timerManager = self
        loadTimers()
        installLiveActivitySupport()
    }

    /// Backwards-compatible one-arg configure. Kept because `RecipeScalerNativeApp`
    /// still calls it from `RecipeScalerNativeApp.init`-level SwiftData setup in
    /// some legacy paths. When the container owns the instance, this is a no-op
    /// (modelContext was already passed to `init`).
    func configure(modelContext: ModelContext) {
        if self.modelContext == nil {
            self.modelContext = modelContext
            loadTimers()
        }
        timerSync.timerManager = self
        installLiveActivitySupport()
    }

    /// Called from App Intent `perform()` when the app process was launched headlessly
    /// and ContentView hasn't appeared yet. Opens the same on-disk SwiftData store.
    static func configureForIntentIfNeeded() {
        guard shared.modelContext == nil else { return }
        let context = ModelContext(RecipeScalerNativeApp.sharedModelContainer)
        shared.configure(modelContext: context)
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
            AppLog.error(.timer, "Notification authorization error: \(error.localizedDescription)")
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
            AppLog.error(.timer, "Error loading timers: \(error.localizedDescription)")
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
        recipeId: String? = nil,
        recipeDisplayName: String? = nil
    ) -> RecipeTimer {
        let timer = RecipeTimer(
            id: Self.makeTimerId(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            duration: duration,
            type: type,
            recipeId: recipeId,
            recipeDisplayName: recipeDisplayName
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
        recipeId: String? = nil,
        recipeDisplayName: String? = nil
    ) -> RecipeTimer {
        // Lazily request notification authorization the first time a user starts
        // a timer (if we don't yet know the system answer). Without this the
        // default-on `TimerNotificationPreferences.isEnabled` is meaningless:
        // system status stays `.notDetermined` and no UN is ever delivered.
        Task { @MainActor in
            let status = await notificationAuthorizationStatus()
            if status == .notDetermined {
                _ = await requestNotificationAuthorization()
            }
        }
        let timer = RecipeTimer(
            id: Self.makeTimerId(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            duration: duration,
            type: type,
            recipeId: recipeId,
            recipeDisplayName: recipeDisplayName
        )
        timer.start()
        insertTimer(timer)
        syncEnqueue(.timerCreated, timer: timer)
        startUpdateTimer()
        scheduleBackgroundTask()
        pushSchedule(timer)
        syncLiveActivity(for: timer)
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
        syncLiveActivity(for: timer)
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
        syncLiveActivity(for: timer)
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
        syncLiveActivity(for: timer)
    }

    /// Adds `minutes * 60` seconds to a running or completed timer.
    ///
    /// Used by notification action buttons (`ADD_ONE_MINUTE`, `ADD_FIVE_MINUTES`).
    /// Syncs via `timer_started` with explicit `endTime` — the server ignores
    /// `endTime` on `timer_resumed` and would otherwise revert the extension.
    func addTime(id: String, minutes: Int) {
        guard minutes > 0 else { return }
        guard let timer = timers.first(where: { $0.id == id }) else { return }
        let now = Date()
        let extra = TimeInterval(minutes * 60)
        let endIsPast = timer.endTime.map { $0 <= now } ?? true
        let baseEnd = (timer.hasCompleted || endIsPast) ? now : (timer.endTime ?? now)
        timer.endTime = baseEnd.addingTimeInterval(extra)
        timer.remainingTime = (timer.hasCompleted || endIsPast ? 0 : (timer.remainingTime ?? max(0, baseEnd.timeIntervalSinceNow))) + extra
        timer.isRunning = true
        timer.isPaused = false
        timer.hasCompleted = false
        timer.startedAt = now
        timer.lastUpdated = now
        persist(timer)
        refreshPanelTimers()
        startUpdateTimer()
        scheduleBackgroundTask()
        syncEnqueue(.timerStarted, timer: timer, extra: ["endTime": millis(timer.endTime) as Any])
        Task { await timerSync.flushPendingSyncImmediately() }
        pushSchedule(timer)
        syncLiveActivity(for: timer)
    }

    func deleteTimer(id: String) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        let timer = timers[index]
        timers.remove(at: index)
        let completeRequestId = "\(timer.id)-complete"
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [timer.id, completeRequestId])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [timer.id, completeRequestId])
        deleteFromStore(timer)
        refreshPanelTimers()
        stopUpdateLoopIfIdle()
        syncEnqueue(.timerDeleted, timer: timer)
        pushCancel(timer.id)
        endLiveActivity(timerId: timer.id)
    }

    func resetTimer(id: String) {
        guard let timer = timers.first(where: { $0.id == id }) else { return }
        timer.stop()
        timer.hasCompleted = false
        persist(timer)
        refreshPanelTimers()
        stopUpdateLoopIfIdle()
        pushCancel(timer.id)
        endLiveActivity(timerId: timer.id)
    }

    // MARK: - Sync (TimerSyncService)

    func replaceTimersFromServer(_ serverTimers: [RecipeTimer]) {
        let localById = Dictionary(uniqueKeysWithValues: timers.map { ($0.id, $0) })
        let merged = serverTimers.map { serverTimer -> RecipeTimer in
            guard let local = localById[serverTimer.id] else { return serverTimer }
            let localMs = Int64(local.lastUpdated.timeIntervalSince1970 * 1000)
            let serverMs = Int64(serverTimer.lastUpdated.timeIntervalSince1970 * 1000)
            return localMs > serverMs ? local : serverTimer
        }

        guard let modelContext else {
            timers = merged
            refreshPanelTimers()
            if timers.contains(where: \.isRunning) { startUpdateTimer() }
            reconcileLiveActivities()
            return
        }
        do {
            let existing = try modelContext.fetch(FetchDescriptor<RecipeTimer>())
            for item in existing {
                modelContext.delete(item)
            }
            timers = []
            for timer in merged {
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
            reconcileLiveActivities()
        } catch {
            AppLog.error(.timer, "Error replacing timers from server: \(error.localizedDescription)")
            timers = merged
            refreshPanelTimers()
            reconcileLiveActivities()
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
        syncLiveActivity(for: timer)
    }

    func removeTimerFromSync(id: String) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        let timer = timers[index]
        timers.remove(at: index)
        deleteFromStore(timer)
        refreshPanelTimers()
        stopUpdateLoopIfIdle()
        endLiveActivity(timerId: id)
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

    func setSuppressPanelSafeAreaInset(_ suppress: Bool) {
        guard suppressPanelSafeAreaInset != suppress else { return }
        suppressPanelSafeAreaInset = suppress
    }

    private func refreshPanelTimers() {
        activeTimers = TimerUtils.sortTimers(timers)
        persistTimerSnapshot()
    }

    // MARK: - Widget snapshot

    /// Debounced write of the active timers into the App Group so that
    /// `HomeWidgetExtension` can render `TimerWidget` without touching SwiftData.
    private var snapshotWriteWorkItem: DispatchWorkItem?

    private func persistTimerSnapshot() {
        snapshotWriteWorkItem?.cancel()
        let work = DispatchWorkItem {
            let document = self.timers.timerSnapshotDocument()
            TimerSnapshotStore.save(document)
            WidgetCenter.shared.reloadTimelines(ofKind: TimerWidgetKind.id)
        }
        snapshotWriteWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
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

    private var lastLiveActivityProgressSync: [String: Date] = [:]

    /// Tick: discovers completion and refreshes Live Activity. Does NOT mutate
    /// `remainingTime` (UI countdown is driven by `TimelineView` in
    /// `MobileTimerPanel`) and does NOT reassign `activeTimers` (which would
    /// invalidate `safeAreaInset` on every tab root every second).
    private func updateRunningTimers() {
        for timer in timers where timer.isRunning {
            guard let endTime = timer.endTime else { continue }
            let remaining = endTime.timeIntervalSinceNow
            if remaining <= 0, !timer.hasCompleted {
                handleTimerReachedZero(timer)
            } else if remaining <= 0 {
                syncLiveActivityIfOverdue(timer)
            } else {
                syncLiveActivityProgress(timer)
            }
        }
    }

    private func syncLiveActivityProgress(_ timer: RecipeTimer) {
        let now = Date()
        if let last = lastLiveActivityProgressSync[timer.id], now.timeIntervalSince(last) < 3 {
            return
        }
        lastLiveActivityProgressSync[timer.id] = now
        syncLiveActivity(for: timer)
    }

    private var lastOverdueLiveActivitySync: [String: Date] = [:]

    /// Keeps exceeded Live Activity phase/content fresh while the app stays in memory.
    private func syncLiveActivityIfOverdue(_ timer: RecipeTimer) {
        let now = Date()
        if let last = lastOverdueLiveActivitySync[timer.id], now.timeIntervalSince(last) < 5 {
            return
        }
        lastOverdueLiveActivitySync[timer.id] = now
        syncLiveActivity(for: timer)
    }

    private func handleTimerReachedZero(_ timer: RecipeTimer) {
        guard !timer.hasCompleted else { return }
        timer.hasCompleted = true
        persist(timer)
        refreshPanelTimers()
        sendCompletionNotification(for: timer)
        syncLiveActivity(for: timer)
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
            let ok = await pushSchedule.schedule(
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
        Task { await pushSchedule.cancel(timerId: timerId) }
    }

    // MARK: - Notifications

    private func registerNotificationCategories() {
        let addOneMinute = UNNotificationAction(
            identifier: Self.addActionOneMinuteIdentifier,
            title: String(localized: "timer.notification.action.add-minute"),
            options: []
        )
        let addFiveMinutes = UNNotificationAction(
            identifier: Self.addActionFiveMinutesIdentifier,
            title: String(localized: "timer.notification.action.add-five-minutes"),
            options: []
        )
        let deleteTimer = UNNotificationAction(
            identifier: Self.deleteTimerIdentifier,
            title: String(localized: "timer.notification.action.delete"),
            options: [.destructive]
        )
        let timerComplete = UNNotificationCategory(
            identifier: Self.timerCompleteCategoryIdentifier,
            actions: [addOneMinute, addFiveMinutes, deleteTimer],
            intentIdentifiers: [],
            options: []
        )
        notificationCenter.setNotificationCategories([timerComplete])
    }

    private func sendCompletionNotification(for timer: RecipeTimer) {
        let prefsEnabled = TimerNotificationPreferences.isEnabled
        guard prefsEnabled else {
            return
        }
        Task { @MainActor in
            let status = await notificationAuthorizationStatus()
            guard status == .authorized else {
                return
            }
            deliverCompletionNotification(for: timer)
        }
    }

    private func deliverCompletionNotification(for timer: RecipeTimer) {
        // Skip local notification when server push was successfully scheduled AND
        // APNs is actually wired up (paid account + registered device token).
        // Without APNs the server "ok" is meaningless — local UN is the only
        // channel that will actually reach the user.
        if serverScheduledPushTimerIds.contains(timer.id) {
            if APnsAvailability.hasRegisteredToken {
                serverScheduledPushTimerIds.remove(timer.id)
                return
            } else {
                serverScheduledPushTimerIds.remove(timer.id)
                // fall through to deliver the local notification
            }
        }
        let content = UNMutableNotificationContent()
        content.title = String(
            format: Bundle.currentLocalizedString("timer.notification.title"),
            timer.name
        )
        content.body = String(localized: "timer.notification.body")
        content.sound = .default
        var userInfo: [String: Any] = ["timerId": timer.id, "timerName": timer.name]
        if let recipeId = timer.recipeId, !recipeId.isEmpty {
            userInfo["recipeId"] = recipeId
        }
        content.userInfo = userInfo
        content.categoryIdentifier = Self.timerCompleteCategoryIdentifier

        let request = UNNotificationRequest(
            identifier: "\(timer.id)-complete",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        notificationCenter.add(request)
    }

    // MARK: - Background

    private var liveActivityBgTaskID: UIBackgroundTaskIdentifier = .invalid
    private var liveActivityBgTimer: Timer?

    private func scheduleBackgroundTask() {
        let request = BGProcessingTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }

    func beginLiveActivityBackgroundUpdates() {
        guard liveActivityBgTaskID == .invalid else { return }
        guard timers.contains(where: { $0.isRunning }) else { return }
        liveActivityBgTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endLiveActivityBackgroundUpdates()
        }
        liveActivityBgTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.updateLiveActivitiesInBackground()
        }
    }

    func endLiveActivityBackgroundUpdates() {
        liveActivityBgTimer?.invalidate()
        liveActivityBgTimer = nil
        guard liveActivityBgTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(liveActivityBgTaskID)
        liveActivityBgTaskID = .invalid
    }

    private func updateLiveActivitiesInBackground() {
        for timer in timers where timer.isRunning {
            syncLiveActivity(for: timer)
        }
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
            AppLog.error(.timer, "Error saving timer: \(error.localizedDescription)")
        }
    }

    private func deleteFromStore(_ timer: RecipeTimer) {
        guard let modelContext else { return }
        do {
            modelContext.delete(timer)
            try modelContext.save()
        } catch {
            AppLog.error(.timer, "Error deleting timer: \(error.localizedDescription)")
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

    // MARK: - Live Activity

    private func installLiveActivitySupport() {
        TimerLiveActivityActionQueue.installHandler { [weak self] action, timerId in
            Task { @MainActor in
                guard let self else { return }
                switch action {
                case .pause:
                    self.pauseTimer(id: timerId)
                case .resume:
                    self.resumeTimer(id: timerId)
                }
            }
        }
        TimerLiveActivityActionQueue.drainIfNeeded()
        TimerLiveActivityCoordinator.shared.restoreFromSystem()
        reconcileLiveActivities()
    }

    private func syncLiveActivity(for timer: RecipeTimer) {
        Task {
            await TimerLiveActivityCoordinator.shared.sync(timer: timer)
        }
    }

    private func endLiveActivity(timerId: String) {
        Task {
            await TimerLiveActivityCoordinator.shared.end(timerId: timerId)
        }
    }

    /// Refreshes Live Activity content (e.g. recipe name/thumbnail after collection sync).
    func refreshLiveActivities() {
        reconcileLiveActivities()
    }

    private func reconcileLiveActivities() {
        Task {
            await TimerLiveActivityCoordinator.shared.reconcile(with: timers)
        }
    }

    #if DEBUG
    /// Test hook: invokes the periodic update loop without waiting for the scheduled timer.
    @MainActor
    func tickUpdateRunningTimersForTests() {
        updateRunningTimers()
    }
    #endif

    nonisolated deinit {
        Task { @MainActor in
            stopUpdateTimer()
        }
    }
}

enum TimerNotificationPreferences {
    private static let enabledKey = "timerNotificationsEnabled"
    private static let userOverrideKey = "timerNotificationsUserDidOverride"

    /// Defaults to `true` (timers are useful without notifications being useless).
    /// Once the user explicitly toggles the switch in Account Settings, that
    /// choice is honoured regardless of the default.
    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.bool(forKey: userOverrideKey) {
                return UserDefaults.standard.bool(forKey: enabledKey)
            }
            return true
        }
        set {
            UserDefaults.standard.set(true, forKey: userOverrideKey)
            UserDefaults.standard.set(newValue, forKey: enabledKey)
        }
    }
}

/// Whether server-side APNs is actually wired up (entitlements + token issued).
/// Without a paid developer program, `registerForRemoteNotifications` returns
/// nothing, so this stays `false` and the local UN must fire unconditionally.
private enum APnsAvailability {
    private static let tokenKey = "apnsDeviceToken"
    static var hasRegisteredToken: Bool {
        !(UserDefaults.standard.string(forKey: tokenKey) ?? "").isEmpty
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
            case Self.addActionOneMinuteIdentifier:
                Task { @MainActor in self.addTime(id: timerId, minutes: 1) }
            case Self.addActionFiveMinutesIdentifier:
                Task { @MainActor in self.addTime(id: timerId, minutes: 5) }
            case Self.deleteTimerIdentifier:
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
}
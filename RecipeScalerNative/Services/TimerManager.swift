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
                registerForRemoteNotifications()
            }
            return granted
        } catch {
            AppLog.error(.timer, "Notification authorization error: \(error.localizedDescription)")
            return false
        }
    }

    /// Requests an APNs device token when notification permission is already granted.
    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
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
        syncLiveActivity(for: timer, policy: .userAction)
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
        syncLiveActivity(for: timer, policy: .userAction)
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
        syncLiveActivity(for: timer, policy: .userAction)
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
        syncLiveActivity(for: timer, policy: .userAction)
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
        syncLiveActivity(for: timer, policy: .userAction)
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
        syncLiveActivity(for: timer, policy: .reconcile)
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
            // Intent optimistic writes set pending-local; durable Manager snapshot
            // is authoritative — release the Provider / silent network gate early
            // instead of waiting out the full 15s TTL.
            TimerSnapshotStore.clearPendingLocalMutation()
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

    /// Tick: discovers completion, refreshes Live Activity, and pushes a debounced
    /// snapshot to the widget. Does NOT mutate `remainingTime` (UI countdown is
    /// driven by `TimelineView` in `MobileTimerPanel`) and does NOT reassign
    /// `activeTimers` (which would invalidate `safeAreaInset` on every tab root
    /// every second). Widget snapshot is republished on every tick — the widget
    /// has no other source of truth for overdue-phase progression.
    private func updateRunningTimers() {
        var snapshotNeedsRepublish = false
        for timer in timers where timer.isRunning {
            guard let endTime = timer.endTime else { continue }
            let remaining = endTime.timeIntervalSinceNow
            if remaining <= 0, !timer.hasCompleted {
                handleTimerReachedZero(timer)
                snapshotNeedsRepublish = true
            } else if remaining <= 0 {
                syncLiveActivityIfOverdue(timer)
                snapshotNeedsRepublish = true
            } else {
                syncLiveActivityProgress(timer)
                snapshotNeedsRepublish = true
            }
        }
        if snapshotNeedsRepublish {
            persistTimerSnapshot()
        }
    }

    /// Spec 058: while a foreground server pull is in flight, progress ticks must
    /// not push stale local `.running` onto ActivityKit (APNs may already show pause).
    private(set) var suppressProgressLiveActivitySync = false

    /// Call before `loadActiveTimersFromServer(force:)` on becoming active.
    func beginForegroundRemoteRefresh() {
        suppressProgressLiveActivitySync = true
    }

    /// Call after the foreground server pull finishes (success or failure).
    func endForegroundRemoteRefresh() {
        suppressProgressLiveActivitySync = false
        reconcileLiveActivities()
    }

    /// Test / verify seam: whether a progress tick is allowed to sync LA.
    static func shouldAllowProgressLiveActivitySync(
        appIsActive: Bool,
        suppressProgressSync: Bool
    ) -> Bool {
        appIsActive && !suppressProgressSync
    }

    private func syncLiveActivityProgress(_ timer: RecipeTimer) {
        // Spec 058: while not active, APNs owns cross-device LA updates. Periodic
        // local Activity.update(running) was overwriting push pause/resume with
        // stale phone endTime. Also suppress while foreground remote refresh runs.
        guard Self.shouldAllowProgressLiveActivitySync(
            appIsActive: UIApplication.shared.applicationState == .active,
            suppressProgressSync: suppressProgressLiveActivitySync
        ) else { return }
        let now = Date()
        if let last = lastLiveActivityProgressSync[timer.id], now.timeIntervalSince(last) < 3 {
            return
        }
        lastLiveActivityProgressSync[timer.id] = now
        syncLiveActivity(for: timer, policy: .progress)
    }

    private var lastOverdueLiveActivitySync: [String: Date] = [:]

    /// Keeps exceeded Live Activity phase/content fresh while the app stays in memory.
    private func syncLiveActivityIfOverdue(_ timer: RecipeTimer) {
        guard Self.shouldAllowProgressLiveActivitySync(
            appIsActive: UIApplication.shared.applicationState == .active,
            suppressProgressSync: suppressProgressLiveActivitySync
        ) else { return }
        let now = Date()
        if let last = lastOverdueLiveActivitySync[timer.id], now.timeIntervalSince(last) < 5 {
            return
        }
        lastOverdueLiveActivitySync[timer.id] = now
        syncLiveActivity(for: timer, policy: .progress)
    }

    private func handleTimerReachedZero(_ timer: RecipeTimer) {
        guard !timer.hasCompleted else { return }
        timer.hasCompleted = true
        persist(timer)
        refreshPanelTimers()
        sendCompletionNotification(for: timer)
        syncLiveActivity(for: timer, policy: .userAction)
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
        // UNNotificationAction titles are UIKit strings — must use
        // Bundle.currentLocalizedString so they follow the in-app language
        // override (String(localized:) can resolve via system locale instead).
        let addOneMinute = UNNotificationAction(
            identifier: Self.addActionOneMinuteIdentifier,
            title: Bundle.currentLocalizedString("timer.notification.action.add-minute"),
            options: []
        )
        let addFiveMinutes = UNNotificationAction(
            identifier: Self.addActionFiveMinutesIdentifier,
            title: Bundle.currentLocalizedString("timer.notification.action.add-five-minutes"),
            options: []
        )
        let deleteTimer = UNNotificationAction(
            identifier: Self.deleteTimerIdentifier,
            title: Bundle.currentLocalizedString("timer.notification.action.delete"),
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
        content.body = Bundle.currentLocalizedString("timer.notification.body")
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
        // Spec 058: do not push local running state onto ActivityKit in background —
        // that races APNs content-state from web/Watch pause & resume.
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

    /// Coalesces parallel `sync(timer:)` calls for the same `timerId`.
    /// `syncLiveActivity(for:)` is invoked from ~10 sites (start, pause,
    /// resume, +1/+5, sync-event, 3s progress tick, 5s overdue tick, bg task),
    /// each spawning a fresh `Task`. Without dedup, two concurrent syncs for
    /// the same timer race past the "is activity already in cache?" check and
    /// both call `Activity.request`, producing duplicate activities.
    private var inFlightSyncTasks: [String: Task<Void, Never>] = [:]

    /// Serializes `reconcileLiveActivities()` calls. On cold start, three
    /// independent triggers fire near-simultaneously: `installLiveActivitySupport`
    /// (init), `replaceTimersFromServer` (sync), and
    /// `ContentView.onChange(of: collectionEntries)`. Without serialization,
    /// each reconcile iterates the entire timer array and races into
    /// `Activity.request`.
    private var reconcileTask: Task<Void, Never>?
    private var pendingReconcile = false

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

    private func syncLiveActivity(for timer: RecipeTimer, policy: LiveActivitySyncPolicy) {
        // Cancel any in-flight sync for this timerId and replace it. The last
        // caller wins — its snapshot of state is freshest. Cancelling (rather
        // than awaiting) keeps the API fire-and-forget from each call site.
        inFlightSyncTasks[timer.id]?.cancel()
        let timerId = timer.id
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await self.runSyncLiveActivity(timerId: timerId, policy: policy)
        }
        inFlightSyncTasks[timerId] = task
    }

    private func runSyncLiveActivity(timerId: String, policy: LiveActivitySyncPolicy) async {
        // Re-resolve the timer from `timers` at execution time so the
        // coordinator sees the freshest state (rather than capturing a stale
        // `RecipeTimer` struct at the call site).
        guard let timer = timers.first(where: { $0.id == timerId }) else {
            inFlightSyncTasks.removeValue(forKey: timerId)
            return
        }
        await TimerLiveActivityCoordinator.shared.sync(timer: timer, policy: policy)
        // Only clear if we're still the active task — a newer caller may have
        // already replaced us and put their own Task here.
        if inFlightSyncTasks[timerId]?.isCancelled == false {
            inFlightSyncTasks.removeValue(forKey: timerId)
        }
    }

    private func endLiveActivity(timerId: String) {
        inFlightSyncTasks[timerId]?.cancel()
        inFlightSyncTasks.removeValue(forKey: timerId)
        Task {
            await TimerLiveActivityCoordinator.shared.end(timerId: timerId)
        }
    }

    /// Refreshes Live Activity content (e.g. recipe name/thumbnail after collection sync).
    func refreshLiveActivities() {
        reconcileLiveActivities()
    }

    private func reconcileLiveActivities() {
        // If a reconcile is already running, mark a pending follow-up: when
        // the current one finishes, a single new reconcile will be scheduled
        // with the latest `timers` snapshot. This collapses 3 simultaneous
        // cold-start triggers into at most 2 sequential reconciles.
        if reconcileTask != nil {
            pendingReconcile = true
            return
        }
        scheduleReconcile()
    }

    private func scheduleReconcile() {
        // Snapshot `timers` synchronously at dispatch time so the Task's body
        // has a stable array even if `timers` mutates during the await.
        let snapshot = timers
        let task: Task<Void, Never> = Task { [weak self] in
            await TimerLiveActivityCoordinator.shared.reconcile(with: snapshot)
            self?.finishReconcilePass()
        }
        reconcileTask = task
    }

    private func finishReconcilePass() {
        // Drain any coalesced follow-up request with a fresh snapshot.
        reconcileTask = nil
        if pendingReconcile {
            pendingReconcile = false
            scheduleReconcile()
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
            for task in inFlightSyncTasks.values {
                task.cancel()
            }
            inFlightSyncTasks.removeAll()
            reconcileTask?.cancel()
            reconcileTask = nil
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

        // Spec 072: follow-feed pushes carry a canonical 059 `url` (single
        // recipe → /public/@/{username}/{recipeId}, digest → /discover/feed).
        // Routed through DeepLinkRouter so a push tap behaves exactly like a
        // Universal Link tap. Takes priority over the legacy `recipeId` field:
        // routing both would queue two conflicting links (2026-08-30 debug:
        // the fallback ran 3 ms later and overwrote the parsed url), and for
        // follow-feed pushes the recipe is public — `.openRecipe` (own
        // collection lookup) can never resolve it.
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else {
            completionHandler()
            return
        }

        let payloadURL = userInfo["url"] as? String
        let legacyRecipeId = userInfo["recipeId"] as? String

        if let payloadURL, !payloadURL.isEmpty {
            Task { @MainActor in
                if DeepLinkRouter.handlePushURL(payloadURL) {
                    AppLog.info(.push, "push_payload_url_routed")
                } else if let legacyRecipeId, !legacyRecipeId.isEmpty {
                    // `url` present but unroutable — legacy recipeId fallback.
                    DeepLinkRouter.shared.handle(.openRecipe(recipeId: legacyRecipeId))
                    AppLog.info(.push, "push_recipe_id_fallback_routed")
                }
                completionHandler()
            }
        } else if let legacyRecipeId, !legacyRecipeId.isEmpty {
            // Legacy `recipeId` payload (pre-072 server builds, third-party
            // APNs): no `url` field at all.
            Task { @MainActor in
                DeepLinkRouter.shared.handle(.openRecipe(recipeId: legacyRecipeId))
                AppLog.info(.push, "push_recipe_id_fallback_routed")
                completionHandler()
            }
        } else {
            completionHandler()
        }
    }
}
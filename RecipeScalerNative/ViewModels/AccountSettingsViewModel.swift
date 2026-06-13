//
//  AccountSettingsViewModel.swift
//  RecipeScalerNative
//

import Foundation
import SwiftUI
import EventKit
import RecipeScalerCore

@MainActor
@Observable
final class AccountSettingsViewModel {
    var isLoading = false
    var isOnline = false
    var statusMessage: String?

    var displayName = ""
    var avatarURL: URL?
    var username: String?
    var canChangeUsername = false

    var publicProfileEnabled = false
    var shareMode: PublicShareMode = .one_by_one
    var allowRecipeDownloads = true
    var isUpdatingSharing = false

    var showNutrition = true
    var appTheme: AppThemePreference = .current
    var timerNotificationsEnabled = false
    var timerNotificationsDenied = false

    var remindersSyncEnabled = false
    var remindersSyncDenied = false
    var remindersListName: String = ""
    var availableRemindersLists: [EKCalendar] = []

    private var nameSaveTask: Task<Void, Never>?

    func bind(syncService: YjsSyncService) {
        isOnline = syncService.connectionState == .connected
    }

    func refresh(syncService: YjsSyncService) async {
        bind(syncService: syncService)

        showNutrition = NutritionSettings.isGlobalEnabled
        appTheme = .current
        await refreshTimerNotificationState()
        refreshRemindersState()

        guard AuthService.shared.userId != nil else { return }

        do {
            async let profile = AccountAPI.fetchProfile()
            async let sharing = AccountAPI.fetchSharingSettings()
            let settings = try? await AccountAPI.fetchUserSettings()

            let profileData = try await profile
            let sharingData = try await sharing

            displayName = profileData.name ?? ""
            if let urlString = profileData.avatarUrl {
                let candidate = URL(string: urlString)
                avatarURL = (candidate?.scheme != nil) ? candidate : URL(string: "\(Config.baseURL)\(urlString)")
            } else {
                avatarURL = nil
            }
            username = profileData.username ?? sharingData.username
            canChangeUsername = profileData.canChangeUsername ?? false

            publicProfileEnabled = sharingData.publicProfileEnabled == true
            shareMode = PublicShareMode(apiValue: sharingData.shareMode) ?? .one_by_one
            allowRecipeDownloads = sharingData.allowRecipeDownloads != false

            // Persist for offline use in the recipe share sheet
            SharingSettingsCache.save(
                publicProfileEnabled: publicProfileEnabled,
                shareMode: shareMode,
                username: username ?? ""
            )

            if let settings, let enabled = settings.nutritionEnabled {
                showNutrition = enabled
                UserDefaults.standard.set(enabled, forKey: NutritionSettings.globalEnabledKey)
            }
            statusMessage = nil
        } catch {
            setStatus(from: error, isBackgroundRefresh: true)
        }
    }

    func scheduleNameSave() {
        nameSaveTask?.cancel()
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        nameSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            do {
                try await AccountAPI.patchDisplayName(trimmed)
            } catch {
                setStatus(from: error)
            }
        }
    }

    func uploadAvatar(data: Data, syncService: YjsSyncService) async {
        do {
            try await AccountAPI.uploadAvatar(imageData: data)
            await refresh(syncService: syncService)
            statusMessage = String(localized: "account.avatar.updated")
        } catch {
            setStatus(from: error)
        }
    }

    func deleteAvatar(syncService: YjsSyncService) async {
        do {
            try await AccountAPI.deleteAvatar()
            avatarURL = nil
            await refresh(syncService: syncService)
        } catch {
            setStatus(from: error)
        }
    }

    func setPublicProfileEnabled(_ enabled: Bool) async {
        guard isOnline else {
            statusMessage = String(localized: "account.offline.alert")
            return
        }
        let previous = publicProfileEnabled
        publicProfileEnabled = enabled
        isUpdatingSharing = true
        defer { isUpdatingSharing = false }
        do {
            let result = try await AccountAPI.patchSharingSettings(publicProfileEnabled: enabled)
            publicProfileEnabled = result.publicProfileEnabled ?? enabled
            if let generated = result.username {
                username = generated
            }
            if let mode = PublicShareMode(apiValue: result.shareMode) {
                shareMode = mode
            }
        } catch {
            publicProfileEnabled = previous
            setStatus(from: error)
        }
    }

    func setShareMode(_ mode: PublicShareMode) async {
        guard isOnline, publicProfileEnabled else { return }
        let previous = shareMode
        shareMode = mode
        isUpdatingSharing = true
        defer { isUpdatingSharing = false }
        do {
            let result = try await AccountAPI.patchSharingSettings(shareMode: mode)
            shareMode = PublicShareMode(apiValue: result.shareMode) ?? mode
        } catch {
            shareMode = previous
            setStatus(from: error)
        }
    }

    func setAllowRecipeDownloads(_ enabled: Bool) async {
        guard isOnline, publicProfileEnabled else { return }
        let previous = allowRecipeDownloads
        allowRecipeDownloads = enabled
        isUpdatingSharing = true
        defer { isUpdatingSharing = false }
        do {
            let result = try await AccountAPI.patchSharingSettings(allowRecipeDownloads: enabled)
            allowRecipeDownloads = result.allowRecipeDownloads != false
        } catch {
            allowRecipeDownloads = previous
            setStatus(from: error)
        }
    }

    func saveUsername(_ value: String) async {
        guard isOnline else { return }
        let sanitized = sanitizeUsername(value)
        guard sanitized.count >= 3 else {
            statusMessage = String(localized: "account.username.too-short")
            return
        }
        do {
            try await AccountAPI.updateUsername(sanitized)
            username = sanitized
            canChangeUsername = false
            statusMessage = String(localized: "account.username.saved")
        } catch {
            setStatus(from: error)
        }
    }

    func setShowNutrition(_ enabled: Bool) async {
        let previous = showNutrition
        showNutrition = enabled
        UserDefaults.standard.set(enabled, forKey: NutritionSettings.globalEnabledKey)
        do {
            try await AccountAPI.updateNutritionEnabled(enabled)
        } catch {
            showNutrition = previous
            UserDefaults.standard.set(previous, forKey: NutritionSettings.globalEnabledKey)
            setStatus(from: error)
        }
    }

    func setAppTheme(_ theme: AppThemePreference) {
        appTheme = theme
        AppThemePreference.save(theme)
    }

    func refreshTimerNotificationState() async {
        let status = await TimerManager.shared.notificationAuthorizationStatus()
        timerNotificationsDenied = status == .denied
        timerNotificationsEnabled = TimerNotificationPreferences.isEnabled && status == .authorized
    }

    func setTimerNotificationsEnabled(_ enabled: Bool) async {
        if !enabled {
            TimerNotificationPreferences.isEnabled = false
            timerNotificationsEnabled = false
            return
        }

        let status = await TimerManager.shared.notificationAuthorizationStatus()
        if status == .denied {
            timerNotificationsDenied = true
            timerNotificationsEnabled = false
            statusMessage = String(localized: "account.timer-notifications.denied")
            return
        }

        var granted = status == .authorized
        if status == .notDetermined {
            granted = await TimerManager.shared.requestNotificationAuthorization()
        }

        if granted {
            TimerNotificationPreferences.isEnabled = true
            timerNotificationsEnabled = true
            timerNotificationsDenied = false
        } else {
            TimerNotificationPreferences.isEnabled = false
            timerNotificationsEnabled = false
            statusMessage = String(localized: "account.timer-notifications.not-granted")
        }
    }

    // MARK: - Apple Reminders sync

    func refreshRemindersState() {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        remindersSyncDenied = status == .denied || status == .restricted
        remindersSyncEnabled = RemindersSyncPreferences.isEnabled && status == .fullAccess
        remindersListName = resolveRemindersListName()
    }

    func setRemindersSyncEnabled(
        _ enabled: Bool,
        syncService: YjsSyncService,
        remindersService: RemindersSyncService
    ) async {
        if !enabled {
            remindersService.disable()
            remindersSyncEnabled = false
            return
        }

        let status = EKEventStore.authorizationStatus(for: .reminder)
        if status == .denied || status == .restricted {
            remindersSyncDenied = true
            remindersSyncEnabled = false
            statusMessage = String(localized: "account.reminders.denied")
            return
        }

        let granted = await remindersService.enable(syncService: syncService)
        if granted {
            remindersSyncEnabled = true
            remindersSyncDenied = false
            remindersService.loadAvailableLists()
            availableRemindersLists = remindersService.availableLists
            remindersListName = resolveRemindersListName()
        } else if EKEventStore.authorizationStatus(for: .reminder) == .denied {
            remindersSyncDenied = true
            remindersSyncEnabled = false
            statusMessage = String(localized: "account.reminders.denied")
        }
    }

    func loadRemindersLists(remindersService: RemindersSyncService) {
        remindersService.loadAvailableLists()
        availableRemindersLists = remindersService.availableLists
    }

    func selectRemindersList(
        _ identifier: String,
        syncService: YjsSyncService,
        remindersService: RemindersSyncService
    ) async {
        await remindersService.selectList(identifier, syncService: syncService)
        remindersListName = resolveRemindersListName(
            lists: remindersService.availableLists,
            identifier: identifier
        )
    }

    private func resolveRemindersListName(
        lists: [EKCalendar]? = nil,
        identifier: String? = nil
    ) -> String {
        let id = identifier ?? RemindersSyncPreferences.listIdentifier
        if id == RemindersSyncPreferences.dedicatedListSentinel {
            return RemindersSyncService.dedicatedListName
        }
        let source = lists ?? availableRemindersLists
        return source.first(where: { $0.calendarIdentifier == id })?.title
            ?? RemindersSyncService.dedicatedListName
    }

    func logout(syncService: YjsSyncService) async {
        if let userId = AuthService.shared.userId,
           let deviceId = UserDefaults.standard.string(forKey: "deviceId") {
            await AccountAPI.logoutDevice(userId: userId, deviceId: deviceId)
        }
        await syncService.clearSessionForLogout()
        do {
            try AuthService.shared.logout()
        } catch {
            setStatus(from: error)
        }
    }

    private func sanitizeUsername(_ value: String) -> String {
        var result = value.lowercased()
        result = result.replacingOccurrences(of: #"[^a-z0-9_.-]"#, with: "-", options: .regularExpression)
        result = result.replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// Maps API/transport errors to localized account status text. Background refresh skips transient network noise.
    private func setStatus(from error: Error, isBackgroundRefresh: Bool = false) {
        statusMessage = UserFacingAPIError.accountStatusMessage(
            for: error,
            isBackgroundRefresh: isBackgroundRefresh
        )
    }
}
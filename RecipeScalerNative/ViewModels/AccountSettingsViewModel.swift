//
//  AccountSettingsViewModel.swift
//  RecipeScalerNative
//

import Foundation
import SwiftUI

@MainActor
final class AccountSettingsViewModel: ObservableObject {
    @Published var isLoading = true
    @Published var isOnline = false
    @Published var statusMessage: String?

    @Published var displayName = ""
    @Published var avatarURL: URL?
    @Published var username: String?
    @Published var canChangeUsername = false

    @Published var publicProfileEnabled = false
    @Published var shareMode: PublicShareMode = .one_by_one
    @Published var allowRecipeDownloads = true
    @Published var isUpdatingSharing = false

    @Published var showNutrition = true
    @Published var appTheme: AppThemePreference = .current

    private var nameSaveTask: Task<Void, Never>?

    func bind(syncService: YjsSyncService) {
        isOnline = syncService.connectionState == .connected
    }

    func refresh(syncService: YjsSyncService) async {
        bind(syncService: syncService)
        isLoading = true
        defer { isLoading = false }

        showNutrition = NutritionSettings.isGlobalEnabled
        appTheme = .current

        guard AuthService.shared.userId != nil else { return }

        do {
            async let profile = AccountAPI.fetchProfile()
            async let sharing = AccountAPI.fetchSharingSettings()
            let settings = try? await AccountAPI.fetchUserSettings()

            let profileData = try await profile
            let sharingData = try await sharing

            displayName = profileData.name ?? ""
            if let urlString = profileData.avatarUrl {
                avatarURL = URL(string: urlString)
            } else {
                avatarURL = nil
            }
            username = profileData.username ?? sharingData.username
            canChangeUsername = profileData.canChangeUsername ?? false

            publicProfileEnabled = sharingData.publicProfileEnabled == true
            shareMode = PublicShareMode(apiValue: sharingData.shareMode) ?? .one_by_one
            allowRecipeDownloads = sharingData.allowRecipeDownloads != false

            if let settings, let enabled = settings.nutritionEnabled {
                showNutrition = enabled
                UserDefaults.standard.set(enabled, forKey: NutritionSettings.globalEnabledKey)
            }
        } catch {
            statusMessage = error.localizedDescription
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
                statusMessage = error.localizedDescription
            }
        }
    }

    func uploadAvatar(data: Data, syncService: YjsSyncService) async {
        do {
            try await AccountAPI.uploadAvatar(imageData: data)
            await refresh(syncService: syncService)
            statusMessage = String(localized: "account.avatar.updated")
        } catch {
            statusMessage = error.localizedDescription
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
            statusMessage = error.localizedDescription
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
            statusMessage = error.localizedDescription
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
            statusMessage = error.localizedDescription
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
            statusMessage = error.localizedDescription
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
            statusMessage = error.localizedDescription
        }
    }

    func setAppTheme(_ theme: AppThemePreference) {
        appTheme = theme
        AppThemePreference.save(theme)
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
            statusMessage = error.localizedDescription
        }
    }

    private func sanitizeUsername(_ value: String) -> String {
        var result = value.lowercased()
        result = result.replacingOccurrences(of: #"[^a-z0-9_.-]"#, with: "-", options: .regularExpression)
        result = result.replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
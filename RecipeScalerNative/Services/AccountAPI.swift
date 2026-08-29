//
//  AccountAPI.swift
//  RecipeScalerNative
//

import Foundation
import Observation
import RecipeScalerCore

// MARK: - DTOs

struct UserProfileDTO: Decodable, Sendable {
    let username: String?
    let name: String?
    let avatarUrl: String?
    let telegramUsername: String?
    let canChangeUsername: Bool?
    let profileUrl: String?
}

struct SharingSettingsDTO: Decodable, Sendable {
    let username: String?
    let publicProfileEnabled: Bool?
    let shareMode: String?
    let allowRecipeDownloads: Bool?
}

struct SharingSettingsPatchResponseDTO: Decodable, Sendable {
    let username: String?
    let name: String?
    let publicProfileEnabled: Bool?
    let shareMode: String?
    let allowRecipeDownloads: Bool?
}

struct UserSettingsDTO: Decodable, Sendable {
    let nutritionEnabled: Bool?
    let vkusvillEnabled: Bool?
}

/// Spec 054: outcome of a cold-start `/api/settings` probe used by
/// `AuthService.performStaleSessionHealthCheck()`.
enum UserExistsResult: Sendable {
    /// 2xx — user present on server, keep local session as-is.
    case exists
    /// HTTP 404 — user no longer exists (e.g. after server DB cutover).
    case userMissing
    /// HTTP 401 / 403 — token revoked or account locked.
    case unauthorized
    /// 5xx, network error, decoding error, or anything else transient.
    case transient
}

/// Feature-adoption report (spec 038). All 11 keys are always present in the
/// server payload; each is modeled as `Bool?` and treated as `false` when nil
/// via `value(for:)`. Snake_case JSON keys map to camelCase Swift properties.
struct FeatureAdoptionReportDTO: Decodable, Sendable {
    let installedNativeApp: Bool?
    let installedWatchApp: Bool?
    let importedRecipe: Bool?
    let createdRecipe: Bool?
    let createdCollection: Bool?
    let sharedRecipe: Bool?
    let connectedTelegram: Bool?
    let connectedMcpAssistant: Bool?
    let sentAssistantMessage: Bool?
    let usedShoppingList: Bool?
    let namedWithEmoji: Bool?

    enum CodingKeys: String, CodingKey {
        case installedNativeApp = "installed_native_app"
        case installedWatchApp = "installed_watch_app"
        case importedRecipe = "imported_recipe"
        case createdRecipe = "created_recipe"
        case createdCollection = "created_collection"
        case sharedRecipe = "shared_recipe"
        case connectedTelegram = "connected_telegram"
        case connectedMcpAssistant = "connected_mcp_assistant"
        case sentAssistantMessage = "sent_assistant_message"
        case usedShoppingList = "used_shopping_list"
        case namedWithEmoji = "named_with_emoji"
    }

    func value(for item: FeatureAdoptionItem) -> Bool {
        switch item {
        case .installedNativeApp: return installedNativeApp ?? false
        case .installedWatchApp: return installedWatchApp ?? false
        case .importedRecipe: return importedRecipe ?? false
        case .createdRecipe: return createdRecipe ?? false
        case .createdCollection: return createdCollection ?? false
        case .sharedRecipe: return sharedRecipe ?? false
        case .connectedTelegram: return connectedTelegram ?? false
        case .connectedMcpAssistant: return connectedMcpAssistant ?? false
        case .sentAssistantMessage: return sentAssistantMessage ?? false
        case .usedShoppingList: return usedShoppingList ?? false
        case .namedWithEmoji: return namedWithEmoji ?? false
        }
    }
}

enum PublicShareMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all
    case with_images_and_steps
    case one_by_one

    var id: String { rawValue }

    init?(apiValue: String?) {
        guard let apiValue, let mode = PublicShareMode(rawValue: apiValue) else { return nil }
        self = mode
    }
}

// MARK: - API

enum AccountAPI {
    /// FIFO async mutex that serializes `/api/settings` PUTs so an older
    /// network round-trip cannot land on the server after a newer one
    /// (review finding: overlapping PUTs not serialized). Bodies are captured
    /// before enqueueing, so ordering reflects when callers initiated the
    /// change, mirroring what the user saw last.
    private static let settingsPutMutex = AsyncFIFOMutex()

    static func fetchProfile() async throws -> UserProfileDTO {
        let response: APIResponse<UserProfileDTO> = try await APIClient.shared.requestJSON(
            path: "/api/users/profile"
        )
        return try APIClient.unwrapResponse(response, fallback: .accountProfileLoadFailed)
    }

    static func fetchSharingSettings() async throws -> SharingSettingsDTO {
        let response: APIResponse<SharingSettingsDTO> = try await APIClient.shared.requestJSON(
            path: "/api/users/sharing-settings"
        )
        return try APIClient.unwrapResponse(response, fallback: .accountSharingLoadFailed)
    }

    static func patchSharingSettings(
        publicProfileEnabled: Bool? = nil,
        shareMode: PublicShareMode? = nil,
        allowRecipeDownloads: Bool? = nil
    ) async throws -> SharingSettingsPatchResponseDTO {
        struct Body: Encodable {
            var publicProfileEnabled: Bool?
            var shareMode: String?
            var allowRecipeDownloads: Bool?

            enum CodingKeys: String, CodingKey {
                case publicProfileEnabled
                case shareMode
                case allowRecipeDownloads
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encodeIfPresent(publicProfileEnabled, forKey: .publicProfileEnabled)
                try container.encodeIfPresent(shareMode, forKey: .shareMode)
                try container.encodeIfPresent(allowRecipeDownloads, forKey: .allowRecipeDownloads)
            }
        }
        let response: APIResponse<SharingSettingsPatchResponseDTO> = try await APIClient.shared.requestJSON(
            path: "/api/users/sharing-settings",
            method: "PATCH",
            body: Body(
                publicProfileEnabled: publicProfileEnabled,
                shareMode: shareMode?.rawValue,
                allowRecipeDownloads: allowRecipeDownloads
            )
        )
        return try APIClient.unwrapResponse(response, fallback: .accountSharingUpdateFailed)
    }

    static func patchDisplayName(_ name: String) async throws {
        struct Body: Encodable { let name: String }
        let _: APIResponse<UserProfileDTO> = try await APIClient.shared.requestJSON(
            path: "/api/users/name",
            method: "PATCH",
            body: Body(name: name)
        )
    }

    static func updateUsername(_ username: String) async throws {
        struct Body: Encodable { let username: String }
        let _: APIResponse<UserProfileDTO> = try await APIClient.shared.requestJSON(
            path: "/api/users/username",
            method: "PUT",
            body: Body(username: username)
        )
    }

    static func uploadAvatar(imageData: Data) async throws {
        _ = try await APIClient.shared.uploadMultipart(
            path: "/api/users/avatar",
            fieldName: "avatar",
            fileData: imageData,
            fileName: "avatar.jpg",
            mimeType: "image/jpeg"
        )
    }

    static func deleteAvatar() async throws {
        let _: APIResponse<[String: String]> = try await APIClient.shared.requestJSON(
            path: "/api/users/avatar",
            method: "DELETE"
        )
    }

    /// Spec 065: `POST /api/feedback` — text plus optional files, no stored id.
    static func submitFeedback(
        message: String,
        files: [(fileName: String, data: Data, mimeType: String)]
    ) async throws {
        var headers: [String: String] = [
            "X-App-Language": AppLanguagePreference.current.rawValue
        ]
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            headers["X-App-Version"] = version
        }
        let raw = try await APIClient.shared.uploadMultipart(
            path: "/api/feedback",
            fields: ["message": message],
            fieldName: "files",
            files: files,
            extraHeaders: headers
        )
        struct Payload: Decodable {
            let success: Bool
            let error: String?
        }
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: raw)
        } catch {
            throw APIError.decodingError(error)
        }
        guard payload.success else {
            throw APIError.serverError(
                code: ServerErrorCode.from(
                    serverValue: payload.error,
                    fallback: .accountFeedbackSendFailed
                )
            )
        }
    }

    static func fetchUserSettings() async throws -> UserSettingsDTO {
        let response: APIResponse<UserSettingsDTO> = try await APIClient.shared.requestJSON(
            path: "/api/settings"
        )
        return try APIClient.unwrapResponse(response, fallback: .accountSettingsLoadFailed)
    }

    /// Spec 054: lightweight existence check for the stored user on cold start.
    ///
    /// Wraps `fetchUserSettings()` with error classification so the caller can
    /// decide between wipe (user missing / token revoked) and keep going
    /// (transient server / network error). Never throws.
    ///
    /// Returns `.exists` only on a successful 2xx; `.userMissing` on HTTP 404;
    /// `.unauthorized` on HTTP 401/403; `.transient` on 5xx, network errors,
    /// decoding errors, or any other unexpected failure.
    static func checkUserExists() async -> UserExistsResult {
        do {
            _ = try await fetchUserSettings()
            return .exists
        } catch let error as APIError {
            switch error {
            case .httpError(let code) where code == 404:
                return .userMissing
            case .httpError(let code) where code == 401 || code == 403:
                return .unauthorized
            default:
                return .transient
            }
        } catch {
            return .transient
        }
    }

    static func updateNutritionEnabled(_ enabled: Bool) async throws {
        struct Body: Encodable {
            let nutrition_enabled: Bool
        }
        try await settingsPutMutex.withLock {
            let _: APIResponse<UserSettingsDTO> = try await APIClient.shared.requestJSON(
                path: "/api/settings",
                method: "PUT",
                body: Body(nutrition_enabled: enabled)
            )
        }
    }

    static func updateVkusvillEnabled(_ enabled: Bool) async throws {
        struct Body: Encodable {
            let vkusvill_enabled: Bool
        }
        try await settingsPutMutex.withLock {
            let response: APIResponse<UserSettingsDTO> = try await APIClient.shared.requestJSON(
                path: "/api/settings",
                method: "PUT",
                body: Body(vkusvill_enabled: enabled)
            )
            _ = try APIClient.unwrapResponse(response, fallback: .accountSettingsLoadFailed)
        }
    }

    struct LegacyAuthStatusDTO: Decodable, Sendable {
        let legacyAuthCutoffAt: String?
        let allMigrated: Bool
        let hasOtherUnmigratedDevices: Bool

        enum CodingKeys: String, CodingKey {
            case legacyAuthCutoffAt = "legacy_auth_cutoff_at"
            case allMigrated = "all_migrated"
            case hasOtherUnmigratedDevices = "has_other_unmigrated_devices"
        }
    }

    static func fetchLegacyAuthStatus() async throws -> LegacyAuthStatusDTO {
        let response: APIResponse<LegacyAuthStatusDTO> = try await APIClient.shared.requestJSON(
            path: "/api/auth/legacy-status"
        )
        return try APIClient.unwrapResponse(response, fallback: .authErrorApiGeneric)
    }

    static func logoutDevice(userId: String, deviceId: String) async {
        struct Body: Encodable {
            let user_id: String
            let device_id: String
        }
        let _: APIResponse<[String: String]>? = try? await APIClient.shared.requestJSON(
            path: "/api/auth/logout",
            method: "POST",
            body: Body(user_id: userId, device_id: deviceId)
        )
    }

    // MARK: - Feature adoption (spec 038)

    static func fetchFeatureAdoption() async throws -> FeatureAdoptionReportDTO {
        let response: APIResponse<FeatureAdoptionReportDTO> = try await APIClient.shared.requestJSON(
            path: "/api/users/me/feature-adoption"
        )
        let dto = try APIClient.unwrapResponse(response, fallback: .accountProfileLoadFailed)
        AppLog.info(.app, "feature_adoption_fetched", data: [
            "installed_native_app": String(dto.installedNativeApp ?? false)
        ])
        return dto
    }

    /// Idempotent: server applies `INSERT ... ON CONFLICT DO NOTHING`.
    ///
    /// Logged at the call site so request/response/error are visible in the
    /// DEBUG journal without introducing a logging dependency in RecipeScalerCore.
    static func markFeatureAdoption(_ feature: FeatureAdoptionClientFeature) async throws {
        AppLog.info(.app, "feature_adoption_post_begin", data: [
            "feature": feature.rawValue
        ])
        do {
            try await FeatureAdoptionAPI.markFeatureAdoption(feature)
            AppLog.info(.app, "feature_adoption_post_ok", data: [
                "feature": feature.rawValue
            ])
        } catch {
            AppLog.info(.app, "feature_adoption_post_failed", data: [
                "feature": feature.rawValue,
                "reason": String(describing: type(of: error))
            ])
            throw error
        }
    }
}

// MARK: - Vkusvill settings store

/// Process-scoped owner for the Vkusvill feature flag AND the `/api/settings`
/// read state the Profile screen needs from the same endpoint.
///
/// Account and Shopping List are separate tab subtrees, so a view-local
/// `@State` would leave the toolbar stale after changing the toggle in Profile.
/// The store is injected by `AppContainer`, owns the one in-memory value, and
/// is the single place that fetches `/api/settings` outside AuthService health
/// probes — view models must not race it with their own best-effort reads
/// (review findings: overlapping refresh epochs, ad-hoc fetch bypassing the
/// loading/error lifecycle).
@MainActor
@Observable
final class VkusvillSettingsStore {
    private(set) var enabled = false
    private(set) var isLoading = false
    private(set) var isUpdating = false
    private(set) var lastError: Error?

    /// Mirror of `nutritionEnabled` from the latest successful GET. Written by
    /// `applyRemoteValue(..., nutrition:)`; the nutrition toggle keeps its own
    /// optimistic-update path for latency but re-syncs from here.
    private(set) var nutritionEnabledFromServer: Bool?

    private var activeUserId: String?
    /// Bumped by every mutation (`setEnabled`), account activation and logout so
    /// any response that predates the bump can never be applied afterwards.
    private var generation = 0
    /// Monotonic counter bumped at the START of every `refresh()`. Overlapping
    /// refreshes get distinct epochs; only the newest epoch may apply its
    /// result, closing the stale-GET-overwrites-fresh-value window (a plain
    /// generation snapshot is equal for concurrent non-mutating refreshes).
    private var refreshEpoch = 0

    /// Network seams for unit tests (mirrors `AuthService.checkUserExistsProvider`):
    /// tests inject delayed/failing responses with real suspension points instead
    /// of hitting the network.
    var fetchUserSettingsProvider: () async throws -> UserSettingsDTO = {
        try await AccountAPI.fetchUserSettings()
    }
    var updateVkusvillEnabledProvider: (_ enabled: Bool) async throws -> Void = { value in
        try await AccountAPI.updateVkusvillEnabled(value)
    }

    /// Test-only view of the active account binding.
    var activeUserIdForTesting: String? { activeUserId }

    private static let cachedUserIdKey = "vkusvill.settings.userId"
    private static let cachedEnabledKey = "vkusvill.settings.enabled"

    func refresh(userId: String?, isOnline: Bool) async {
        guard let userId, !userId.isEmpty else {
            clearForLogout()
            return
        }

        activate(userId: userId)
        guard isOnline else { return }

        // Cancel (epoch-wise) any overlapping refresh started earlier.
        refreshEpoch &+= 1
        let requestEpoch = refreshEpoch
        let requestGeneration = generation
        isLoading = true
        defer {
            // Only the newest refresh owns the loading flag.
            if requestEpoch == refreshEpoch {
                isLoading = false
            }
        }

        do {
            let settings = try await fetchUserSettingsProvider()
            guard !Task.isCancelled,
                  requestEpoch == refreshEpoch,
                  requestGeneration == generation,
                  activeUserId == userId else {
                return
            }
            guard !isUpdating else { return }
            if let value = settings.vkusvillEnabled {
                applyRemoteValue(value, userId: userId)
            }
            nutritionEnabledFromServer = settings.nutritionEnabled
        } catch {
            guard !Task.isCancelled,
                  requestEpoch == refreshEpoch,
                  requestGeneration == generation,
                  activeUserId == userId else {
                return
            }
            lastError = error
        }
    }

    func applyRemoteValue(_ value: Bool, userId: String?) {
        guard let userId, !userId.isEmpty else { return }
        activate(userId: userId)
        guard !isUpdating else { return }
        enabled = value
        lastError = nil
        persistCache()
    }

    func setEnabled(_ value: Bool, userId: String?) async {
        guard let userId, !userId.isEmpty else { return }
        activate(userId: userId)

        let previous = enabled
        // Bump before the request so an in-flight GET for the same account is
        // invalidated while this PUT is in progress (mutation invalidates reads).
        generation &+= 1
        let requestGeneration = generation
        enabled = value
        lastError = nil
        isUpdating = true
        defer {
            if requestGeneration == generation {
                isUpdating = false
            }
        }

        do {
            try await updateVkusvillEnabledProvider(value)
            guard !Task.isCancelled,
                  requestGeneration == generation,
                  activeUserId == userId else {
                return
            }
            persistCache()
        } catch {
            guard !Task.isCancelled,
                  requestGeneration == generation,
                  activeUserId == userId else {
                return
            }
            enabled = previous
            lastError = error
        }
    }

    func clearForLogout() {
        generation &+= 1
        refreshEpoch &+= 1
        activeUserId = nil
        enabled = false
        isLoading = false
        isUpdating = false
        lastError = nil
        nutritionEnabledFromServer = nil
    }

    private func activate(userId: String) {
        guard activeUserId != userId else { return }
        generation &+= 1
        refreshEpoch &+= 1
        activeUserId = userId
        lastError = nil
        enabled = cachedValue(for: userId)
    }

    private func cachedValue(for userId: String) -> Bool {
        guard UserDefaults.standard.string(forKey: Self.cachedUserIdKey) == userId else {
            return false
        }
        return UserDefaults.standard.bool(forKey: Self.cachedEnabledKey)
    }

    private func persistCache() {
        guard let activeUserId else { return }
        UserDefaults.standard.set(activeUserId, forKey: Self.cachedUserIdKey)
        UserDefaults.standard.set(enabled, forKey: Self.cachedEnabledKey)
    }
}

// MARK: - Async FIFO mutex

/// Minimal async mutual-exclusion primitive with FIFO wakeup order. Used to
/// serialize non-idempotent PUT requests whose server-side effect depends on
/// arrival order.
actor AsyncFIFOMutex {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withLock<T: Sendable>(_ body: @Sendable () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await body()
    }

    private func acquire() async {
        if !isLocked {
            isLocked = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            isLocked = false
        }
    }
}

//
//  FeatureAdoptionStore.swift
//  RecipeScalerNative
//

import Foundation

/// Value-type snapshot of the 11 feature-adoption flags (spec 038).
/// Persisted as a JSON blob under the `feature-adoption-cache` UserDefaults key
/// so the section renders instantly from cache before the network resolves.
struct FeatureAdoptionReport: Codable, Sendable, Equatable {
    var installedNativeApp: Bool = false
    var installedWatchApp: Bool = false
    var importedRecipe: Bool = false
    var createdRecipe: Bool = false
    var createdCollection: Bool = false
    var sharedRecipe: Bool = false
    var connectedTelegram: Bool = false
    var connectedMcpAssistant: Bool = false
    var sentAssistantMessage: Bool = false
    var usedShoppingList: Bool = false
    var namedWithEmoji: Bool = false

    static let empty = FeatureAdoptionReport()

    init(
        installedNativeApp: Bool = false,
        installedWatchApp: Bool = false,
        importedRecipe: Bool = false,
        createdRecipe: Bool = false,
        createdCollection: Bool = false,
        sharedRecipe: Bool = false,
        connectedTelegram: Bool = false,
        connectedMcpAssistant: Bool = false,
        sentAssistantMessage: Bool = false,
        usedShoppingList: Bool = false,
        namedWithEmoji: Bool = false
    ) {
        self.installedNativeApp = installedNativeApp
        self.installedWatchApp = installedWatchApp
        self.importedRecipe = importedRecipe
        self.createdRecipe = createdRecipe
        self.createdCollection = createdCollection
        self.sharedRecipe = sharedRecipe
        self.connectedTelegram = connectedTelegram
        self.connectedMcpAssistant = connectedMcpAssistant
        self.sentAssistantMessage = sentAssistantMessage
        self.usedShoppingList = usedShoppingList
        self.namedWithEmoji = namedWithEmoji
    }

    private enum CodingKeys: String, CodingKey {
        case installedNativeApp
        case installedWatchApp
        case importedRecipe
        case createdRecipe
        case createdCollection
        case sharedRecipe
        case connectedTelegram
        case connectedMcpAssistant
        case sentAssistantMessage
        case usedShoppingList
        case namedWithEmoji
    }

    /// Keeps caches written before the 11th flag readable after the contract
    /// grows. Missing keys are false, while present legacy values are retained.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        installedNativeApp = try container.decodeIfPresent(Bool.self, forKey: .installedNativeApp) ?? false
        installedWatchApp = try container.decodeIfPresent(Bool.self, forKey: .installedWatchApp) ?? false
        importedRecipe = try container.decodeIfPresent(Bool.self, forKey: .importedRecipe) ?? false
        createdRecipe = try container.decodeIfPresent(Bool.self, forKey: .createdRecipe) ?? false
        createdCollection = try container.decodeIfPresent(Bool.self, forKey: .createdCollection) ?? false
        sharedRecipe = try container.decodeIfPresent(Bool.self, forKey: .sharedRecipe) ?? false
        connectedTelegram = try container.decodeIfPresent(Bool.self, forKey: .connectedTelegram) ?? false
        connectedMcpAssistant = try container.decodeIfPresent(Bool.self, forKey: .connectedMcpAssistant) ?? false
        sentAssistantMessage = try container.decodeIfPresent(Bool.self, forKey: .sentAssistantMessage) ?? false
        usedShoppingList = try container.decodeIfPresent(Bool.self, forKey: .usedShoppingList) ?? false
        namedWithEmoji = try container.decodeIfPresent(Bool.self, forKey: .namedWithEmoji) ?? false
    }
}

/// Holds the live feature-adoption report for the current user.
///
/// - `loadFromCache()` is synchronous and called at section appear (and during
///   `AppContainer.bootstrap`) so the UI never shows a loading state.
/// - `refresh()` hits the network and updates both `report` and the cache.
///   Errors are swallowed (logged) — offline shows the last cached snapshot.
/// - `markInstalledLocally()` flips `installedNativeApp` to `true` and persists
///   it for an instant UI update before the POST returns.
@MainActor
@Observable
final class FeatureAdoptionStore {
    private static let cacheKey = "feature-adoption-cache"

    /// Idempotency flag for `installed_native_app` (spec 038 FR-038-N4). Stored
    /// in `UserDefaults` so a successful POST is not retried on every launch.
    /// Reset in `clearForLogout()` so a previous account's flag does not block
    /// the POST for a different account signing in on the same device — see
    /// spec 038 changelog 2026-08-03 ("installed_native_app per-account reset").
    static let installedReportedKey = "feature-adoption.installed-reported"

    var report: FeatureAdoptionReport = .empty

    func value(for item: FeatureAdoptionItem) -> Bool {
        switch item {
        case .installedNativeApp: return report.installedNativeApp
        case .installedWatchApp: return report.installedWatchApp
        case .importedRecipe: return report.importedRecipe
        case .createdRecipe: return report.createdRecipe
        case .createdCollection: return report.createdCollection
        case .sharedRecipe: return report.sharedRecipe
        case .connectedTelegram: return report.connectedTelegram
        case .connectedMcpAssistant: return report.connectedMcpAssistant
        case .sentAssistantMessage: return report.sentAssistantMessage
        case .usedShoppingList: return report.usedShoppingList
        case .namedWithEmoji: return report.namedWithEmoji
        }
    }

    func loadFromCache() {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey) else { return }
        do {
            report = try JSONDecoder().decode(FeatureAdoptionReport.self, from: data)
        } catch {
            // Stale / corrupt blob — fall back to empty defaults and let the next refresh overwrite.
            report = .empty
        }
    }

    func refresh() async {
        do {
            let dto = try await AccountAPI.fetchFeatureAdoption()
            report = FeatureAdoptionReport(
                installedNativeApp: dto.installedNativeApp ?? false,
                installedWatchApp: dto.installedWatchApp ?? false,
                importedRecipe: dto.importedRecipe ?? false,
                createdRecipe: dto.createdRecipe ?? false,
                createdCollection: dto.createdCollection ?? false,
                sharedRecipe: dto.sharedRecipe ?? false,
                connectedTelegram: dto.connectedTelegram ?? false,
                connectedMcpAssistant: dto.connectedMcpAssistant ?? false,
                sentAssistantMessage: dto.sentAssistantMessage ?? false,
                usedShoppingList: dto.usedShoppingList ?? false,
                namedWithEmoji: dto.namedWithEmoji ?? false
            )
            persist()
        } catch {
            // Silent: keep showing the last cached snapshot (spec US5 / SC-006).
            // Log so offline / server issues are diagnosable in debug sessions
            // without surfacing them to the user.
            AppLog.info(.app, "feature_adoption_refresh_failed", data: [
                "reason": String(describing: type(of: error))
            ])
        }
    }

    /// Instant UI update for `installed_native_app` before the POST resolves.
    /// Per spec FR-038-N4 the server POST itself is fired from `AuthService`.
    func markInstalledLocally() {
        guard !report.installedNativeApp else { return }
        report.installedNativeApp = true
        persist()
    }

    /// Wipe in-memory report and persisted cache (logout / account switch).
    ///
    /// Also clears `installed-reported` so the next account signing in on this
    /// device triggers a fresh `installed_native_app` POST. Without this reset
    /// the very first account on a device would set the flag once and every
    /// subsequent account would skip the POST, so their server-side flag never
    /// gets recorded (spec 038 changelog 2026-08-03).
    func clearForLogout() {
        report = .empty
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
        UserDefaults.standard.removeObject(forKey: Self.installedReportedKey)
        AppLog.info(.app, "feature_adoption_cleared")
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(report)
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        } catch {
            // Non-fatal: the in-memory `report` is still correct for this session.
        }
    }
}

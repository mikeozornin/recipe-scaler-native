//
//  FeatureAdoptionStore.swift
//  RecipeScalerNative
//

import Foundation

/// Value-type snapshot of the 9 feature-adoption flags (spec 038).
/// Persisted as a JSON blob under the `feature-adoption-cache` UserDefaults key
/// so the section renders instantly from cache before the network resolves.
struct FeatureAdoptionReport: Codable, Sendable, Equatable {
    var installedNativeApp: Bool = false
    var importedRecipe: Bool = false
    var createdRecipe: Bool = false
    var createdCollection: Bool = false
    var sharedRecipe: Bool = false
    var connectedTelegram: Bool = false
    var connectedMcpAssistant: Bool = false
    var sentAssistantMessage: Bool = false
    var usedShoppingList: Bool = false

    static let empty = FeatureAdoptionReport()
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

    var report: FeatureAdoptionReport = .empty

    func value(for item: FeatureAdoptionItem) -> Bool {
        switch item {
        case .installedNativeApp: return report.installedNativeApp
        case .importedRecipe: return report.importedRecipe
        case .createdRecipe: return report.createdRecipe
        case .createdCollection: return report.createdCollection
        case .sharedRecipe: return report.sharedRecipe
        case .connectedTelegram: return report.connectedTelegram
        case .connectedMcpAssistant: return report.connectedMcpAssistant
        case .sentAssistantMessage: return report.sentAssistantMessage
        case .usedShoppingList: return report.usedShoppingList
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
                importedRecipe: dto.importedRecipe ?? false,
                createdRecipe: dto.createdRecipe ?? false,
                createdCollection: dto.createdCollection ?? false,
                sharedRecipe: dto.sharedRecipe ?? false,
                connectedTelegram: dto.connectedTelegram ?? false,
                connectedMcpAssistant: dto.connectedMcpAssistant ?? false,
                sentAssistantMessage: dto.sentAssistantMessage ?? false,
                usedShoppingList: dto.usedShoppingList ?? false
            )
            persist()
        } catch {
            // Silent: keep showing the last cached snapshot (spec US5 / SC-006).
        }
    }

    /// Instant UI update for `installed_native_app` before the POST resolves.
    /// Per spec FR-038-N4 the server POST itself is fired from `AuthService`.
    func markInstalledLocally() {
        guard !report.installedNativeApp else { return }
        report.installedNativeApp = true
        persist()
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

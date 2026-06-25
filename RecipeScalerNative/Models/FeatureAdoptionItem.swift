//
//  FeatureAdoptionItem.swift
//  RecipeScalerNative
//

import SwiftUI

/// Canonical feature-adoption flags tracked by spec 038.
///
/// `rawValue` is the exact snake_case key sent to / returned by the backend
/// (`GET/POST /api/users/me/feature-adoption`). `allCases` order matches the
/// spec table order and drives the rendering order of `FeatureAdoptionDetailView`.
enum FeatureAdoptionItem: String, CaseIterable, Sendable {
    case installedNativeApp = "installed_native_app"
    case importedRecipe = "imported_recipe"
    case createdRecipe = "created_recipe"
    case createdCollection = "created_collection"
    case sharedRecipe = "shared_recipe"
    case connectedTelegram = "connected_telegram"
    case connectedMcpAssistant = "connected_mcp_assistant"
    case sentAssistantMessage = "sent_assistant_message"

    /// Literal `LocalizedStringKey` for this item.
    ///
    /// Must be built from a literal — not interpolated from `rawValue` — because
    /// `LocalizedStringKey("...\\(rawValue)")` compiles into a format string
    /// (`"...%@"`) which then doesn't resolve against the string catalog.
    var titleKey: LocalizedStringKey {
        switch self {
        case .installedNativeApp: return "account.feature-adoption.item.installed_native_app"
        case .importedRecipe: return "account.feature-adoption.item.imported_recipe"
        case .createdRecipe: return "account.feature-adoption.item.created_recipe"
        case .createdCollection: return "account.feature-adoption.item.created_collection"
        case .sharedRecipe: return "account.feature-adoption.item.shared_recipe"
        case .connectedTelegram: return "account.feature-adoption.item.connected_telegram"
        case .connectedMcpAssistant: return "account.feature-adoption.item.connected_mcp_assistant"
        case .sentAssistantMessage: return "account.feature-adoption.item.sent_assistant_message"
        }
    }
}

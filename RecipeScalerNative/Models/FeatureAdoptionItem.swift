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
    case installedWatchApp = "installed_watch_app"
    case createdRecipe = "created_recipe"
    case usedShoppingList = "used_shopping_list"
    case importedRecipe = "imported_recipe"
    case createdCollection = "created_collection"
    case sentAssistantMessage = "sent_assistant_message"
    case connectedTelegram = "connected_telegram"
    case connectedMcpAssistant = "connected_mcp_assistant"
    case sharedRecipe = "shared_recipe"

    /// Literal `LocalizedStringKey` for this item.
    ///
    /// Must be built from a literal — not interpolated from `rawValue` — because
    /// `LocalizedStringKey("...\\(rawValue)")` compiles into a format string
    /// (`"...%@"`) which then doesn't resolve against the string catalog.
    var titleKey: LocalizedStringKey {
        switch self {
        case .installedNativeApp: return "account.feature-adoption.item.installed_native_app"
        case .installedWatchApp: return "account.feature-adoption.item.installed_watch_app"
        case .createdRecipe: return "account.feature-adoption.item.created_recipe"
        case .usedShoppingList: return "account.feature-adoption.item.used_shopping_list"
        case .importedRecipe: return "account.feature-adoption.item.imported_recipe"
        case .createdCollection: return "account.feature-adoption.item.created_collection"
        case .sentAssistantMessage: return "account.feature-adoption.item.sent_assistant_message"
        case .connectedTelegram: return "account.feature-adoption.item.connected_telegram"
        case .connectedMcpAssistant: return "account.feature-adoption.item.connected_mcp_assistant"
        case .sharedRecipe: return "account.feature-adoption.item.shared_recipe"
        }
    }

    /// Optional onboarding footnote shown under the title in `FeatureAdoptionRow`.
    var footnoteKey: LocalizedStringKey? {
        switch self {
        case .installedNativeApp: return "account.feature-adoption.item.installed_native_app.footnote"
        case .installedWatchApp: return "account.feature-adoption.item.installed_watch_app.footnote"
        case .createdRecipe: return "account.feature-adoption.item.created_recipe.footnote"
        case .usedShoppingList: return "account.feature-adoption.item.used_shopping_list.footnote"
        case .importedRecipe: return "account.feature-adoption.item.imported_recipe.footnote"
        case .createdCollection: return "account.feature-adoption.item.created_collection.footnote"
        case .sentAssistantMessage: return "account.feature-adoption.item.sent_assistant_message.footnote"
        case .connectedTelegram: return "account.feature-adoption.item.connected_telegram.footnote"
        case .connectedMcpAssistant: return "account.feature-adoption.item.connected_mcp_assistant.footnote"
        case .sharedRecipe: return "account.feature-adoption.item.shared_recipe.footnote"
        }
    }

    /// Spec 040 — whether tapping this row opens a guide screen.
    /// Both `installed*` flags are completed by definition and have no guide.
    var isGuideAvailable: Bool {
        switch self {
        case .installedNativeApp, .installedWatchApp:
            return false
        default:
            return true
        }
    }

    /// Spec 040 — static content for the per-item guide screen.
    ///
    /// - Precondition: `isGuideAvailable == true`. The `installed*` items have
    ///   no guide and must never reach this code path; callers gate on
    ///   `isGuideAvailable` first. Misuse is a programmer error, not a
    ///   runtime fallback, so it traps loudly instead of silently rendering
    ///   an empty screen.
    var guideContent: FeatureAdoptionGuideContent {
        switch self {
        case .installedNativeApp, .installedWatchApp:
            fatalError("FeatureAdoptionItem.guideContent called for \(rawValue); isGuideAvailable is false")
        case .createdRecipe:
            return FeatureAdoptionGuideContent(
                item: self,
                videoResourceName: nil,
                screenshotAssetNames: [],
                exampleImages: nil,
                carouselHintKey: nil,
                primaryCTA: nil
            )
        case .usedShoppingList:
            return FeatureAdoptionGuideContent(
                item: self,
                videoResourceName: nil,
                screenshotAssetNames: [],
                exampleImages: nil,
                carouselHintKey: nil,
                primaryCTA: nil
            )
        case .importedRecipe:
            return FeatureAdoptionGuideContent(
                item: self,
                videoResourceName: "guide_imported_recipe_video",
                screenshotAssetNames: [],
                exampleImages: nil,
                carouselHintKey: nil,
                primaryCTA: .openImportTab
            )
        case .createdCollection:
            return FeatureAdoptionGuideContent(
                item: self,
                videoResourceName: nil,
                screenshotAssetNames: [],
                exampleImages: nil,
                carouselHintKey: nil,
                primaryCTA: nil
            )
        case .sentAssistantMessage:
            return FeatureAdoptionGuideContent(
                item: self,
                videoResourceName: nil,
                screenshotAssetNames: [],
                exampleImages: [
                    GuideExampleImage(
                        assetName: "guide_sent_assistant_message_ex_01",
                        accessibilityLabelKey: "account.feature-adoption.guide.sent_assistant_message.example.1.accessibility-label"
                    ),
                    GuideExampleImage(
                        assetName: "guide_sent_assistant_message_ex_02",
                        accessibilityLabelKey: "account.feature-adoption.guide.sent_assistant_message.example.2.accessibility-label"
                    ),
                    GuideExampleImage(
                        assetName: "guide_sent_assistant_message_ex_03",
                        accessibilityLabelKey: "account.feature-adoption.guide.sent_assistant_message.example.3.accessibility-label"
                    )
                ],
                carouselHintKey: "account.feature-adoption.guide.sent_assistant_message.carousel-hint",
                primaryCTA: .openAssistant
            )
        case .connectedTelegram:
            return FeatureAdoptionGuideContent(
                item: self,
                videoResourceName: "guide_connected_telegram_video",
                screenshotAssetNames: [],
                exampleImages: nil,
                carouselHintKey: nil,
                primaryCTA: .openProfileTelegram
            )
        case .connectedMcpAssistant:
            return FeatureAdoptionGuideContent(
                item: self,
                videoResourceName: nil,
                screenshotAssetNames: [],
                exampleImages: [
                    GuideExampleImage(
                        assetName: "guide_connected_mcp_assistant_ex_01",
                        accessibilityLabelKey: "account.feature-adoption.guide.connected_mcp_assistant.example.1.accessibility-label"
                    ),
                    GuideExampleImage(
                        assetName: "guide_connected_mcp_assistant_ex_02",
                        accessibilityLabelKey: "account.feature-adoption.guide.connected_mcp_assistant.example.2.accessibility-label"
                    )
                ],
                carouselHintKey: "account.feature-adoption.guide.connected_mcp_assistant.carousel-hint",
                primaryCTA: .openSafari(URL(string: "https://recipe-scaler.ru/mcp")!)
            )
        case .sharedRecipe:
            return FeatureAdoptionGuideContent(
                item: self,
                videoResourceName: nil,
                screenshotAssetNames: [],
                exampleImages: nil,
                carouselHintKey: nil,
                primaryCTA: .openProfilePublicSettings
            )
        }
    }
}

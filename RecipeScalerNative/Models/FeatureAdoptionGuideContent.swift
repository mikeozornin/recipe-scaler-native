//
//  FeatureAdoptionGuideContent.swift
//  RecipeScalerNative
//
//  Spec 040 — content model for the per-item drill-in guide shown from
//  `FeatureAdoptionDetailView`. Pure data, no @Observable.
//

import Foundation
import SwiftUI

/// One screenshot in a `GuideExampleCarousel`. Visual asset is locale-aware
/// (see `GuideAssetResolver`); the accessibility label is a literal i18n key.
struct GuideExampleImage: Equatable {
    /// Base imageset name, e.g. `guide_sent_assistant_message_ex_01`.
    /// Locale suffix (`_ru` / `_en`) is appended by `GuideAssetResolver`.
    let assetName: String

    /// Short VoiceOver description, e.g.
    /// `account.feature-adoption.guide.sent_assistant_message.example.1.accessibility-label`.
    let accessibilityLabelKey: LocalizedStringKey
}

/// Primary call-to-action at the bottom of a guide.
enum GuideCTA: Equatable {
    case openImportTab
    case openAssistant
    case openProfileTelegram
    case openSafari(URL)
    case openProfilePublicSettings
}

/// Static content for a single `FeatureAdoptionItem` guide screen.
struct FeatureAdoptionGuideContent: Equatable {
    let item: FeatureAdoptionItem

    /// Bundled mp4 name (without extension). `nil` = no video block.
    let videoResourceName: String?

    /// Step-by-step images between "why" and "how". Empty for guides without
    /// per-step screenshots.
    let screenshotAssetNames: [String]

    /// Carousel screenshots shown above the CTA. `nil` = no carousel block.
    let exampleImages: [GuideExampleImage]?

    /// Footer text under the carousel. `nil` = no footer.
    let carouselHintKey: LocalizedStringKey?

    /// Primary CTA. `nil` = no button (e.g. `used_shopping_list`).
    let primaryCTA: GuideCTA?

    /// Generated scene ids used by the DEBUG Media Studio and capture manifest.
    /// The guide view may render these assets when they are bundled; scene
    /// generation itself remains outside the production content model.
    var mediaSceneIds: [String] {
        switch item {
        case .createdRecipe:
            return ["created_recipe.creation-map"]
        case .usedShoppingList:
            return [
                "used_shopping_list.shopping-list",
                "used_shopping_list.reminders-instruction"
            ]
        case .importedRecipe:
            return [
                "imported_recipe.share-instruction",
                "imported_recipe.import-text",
                "imported_recipe.import-photo"
            ]
        case .createdCollection:
            return ["created_collection.collections"]
        case .sentAssistantMessage:
            return [
                "sent_assistant_message.assistant-fixture",
                "sent_assistant_message.example-01",
                "sent_assistant_message.example-02",
                "sent_assistant_message.example-03",
                "sent_assistant_message.example-04",
                "sent_assistant_message.example-05"
            ]
        case .connectedTelegram:
            return [
                "connected_telegram.connection-code",
                "connected_telegram.instruction"
            ]
        case .connectedMcpAssistant:
            return [
                "connected_mcp_assistant.connector-instruction",
                "connected_mcp_assistant.external-assistant",
                "connected_mcp_assistant.shopping-command",
                "connected_mcp_assistant.save-command"
            ]
        case .sharedRecipe:
            return [
                "shared_recipe.public-profile",
                "shared_recipe.share-instruction"
            ]
        case .installedNativeApp, .installedWatchApp, .namedWithEmoji:
            return []
        }
    }

    /// Why this feature matters.
    var whyKey: LocalizedStringKey {
        switch item {
        case .createdRecipe:
            return "account.feature-adoption.guide.created_recipe.why"
        case .usedShoppingList:
            return "account.feature-adoption.guide.used_shopping_list.why"
        case .importedRecipe:
            return "account.feature-adoption.guide.imported_recipe.why"
        case .createdCollection:
            return "account.feature-adoption.guide.created_collection.why"
        case .sentAssistantMessage:
            return "account.feature-adoption.guide.sent_assistant_message.why"
        case .connectedTelegram:
            return "account.feature-adoption.guide.connected_telegram.why"
        case .connectedMcpAssistant:
            return "account.feature-adoption.guide.connected_mcp_assistant.why"
        case .sharedRecipe:
            return "account.feature-adoption.guide.shared_recipe.why"
        case .installedNativeApp, .installedWatchApp, .namedWithEmoji:
            fatalError("FeatureAdoptionGuideContent.whyKey unreachable for \(item.rawValue)")
        }
    }

    /// "How" step keys. Order = rendering order. Variable length per item.
    var howStepKeys: [LocalizedStringKey] {
        switch item {
        case .createdRecipe:
            return [
                "account.feature-adoption.guide.created_recipe.how.1",
                "account.feature-adoption.guide.created_recipe.how.2",
                "account.feature-adoption.guide.created_recipe.how.3",
                "account.feature-adoption.guide.created_recipe.how.4"
            ]
        case .usedShoppingList:
            return [
                "account.feature-adoption.guide.used_shopping_list.how.1",
                "account.feature-adoption.guide.used_shopping_list.how.2",
                "account.feature-adoption.guide.used_shopping_list.how.3"
            ]
        case .importedRecipe:
            return [
                "account.feature-adoption.guide.imported_recipe.how.1",
                "account.feature-adoption.guide.imported_recipe.how.2",
                "account.feature-adoption.guide.imported_recipe.how.3",
                "account.feature-adoption.guide.imported_recipe.how.4"
            ]
        case .createdCollection:
            return [
                "account.feature-adoption.guide.created_collection.how.1",
                "account.feature-adoption.guide.created_collection.how.2",
                "account.feature-adoption.guide.created_collection.how.3"
            ]
        case .sentAssistantMessage:
            return [
                "account.feature-adoption.guide.sent_assistant_message.how.1",
                "account.feature-adoption.guide.sent_assistant_message.how.2",
                "account.feature-adoption.guide.sent_assistant_message.how.3"
            ]
        case .connectedTelegram:
            return [
                "account.feature-adoption.guide.connected_telegram.how.1",
                "account.feature-adoption.guide.connected_telegram.how.2",
                "account.feature-adoption.guide.connected_telegram.how.3",
                "account.feature-adoption.guide.connected_telegram.how.4"
            ]
        case .connectedMcpAssistant:
            return [
                "account.feature-adoption.guide.connected_mcp_assistant.how.1",
                "account.feature-adoption.guide.connected_mcp_assistant.how.2",
                "account.feature-adoption.guide.connected_mcp_assistant.how.3"
            ]
        case .sharedRecipe:
            return [
                "account.feature-adoption.guide.shared_recipe.how.1",
                "account.feature-adoption.guide.shared_recipe.how.2",
                "account.feature-adoption.guide.shared_recipe.how.3"
            ]
        case .installedNativeApp, .installedWatchApp, .namedWithEmoji:
            fatalError("FeatureAdoptionGuideContent.howStepKeys unreachable for \(item.rawValue)")
        }
    }

    /// Primary CTA button title (pending state).
    var ctaTitleKey: LocalizedStringKey? {
        switch item {
        case .installedNativeApp, .installedWatchApp, .usedShoppingList, .createdCollection, .createdRecipe, .namedWithEmoji:
            return nil
        case .importedRecipe:
            return "account.feature-adoption.guide.imported_recipe.cta"
        case .sentAssistantMessage:
            return "account.feature-adoption.guide.sent_assistant_message.cta"
        case .connectedTelegram:
            return "account.feature-adoption.guide.connected_telegram.cta"
        case .connectedMcpAssistant:
            return "account.feature-adoption.guide.connected_mcp_assistant.cta"
        case .sharedRecipe:
            return "account.feature-adoption.guide.shared_recipe.cta"
        }
    }

    /// Primary CTA button title (done state — re-open / revisit).
    var ctaDoneTitleKey: LocalizedStringKey? {
        switch item {
        case .installedNativeApp, .installedWatchApp, .usedShoppingList, .createdCollection, .createdRecipe, .namedWithEmoji:
            return nil
        case .importedRecipe:
            return "account.feature-adoption.guide.imported_recipe.cta-done"
        case .sentAssistantMessage:
            return "account.feature-adoption.guide.sent_assistant_message.cta-done"
        case .connectedTelegram:
            return "account.feature-adoption.guide.connected_telegram.cta-done"
        case .connectedMcpAssistant:
            return "account.feature-adoption.guide.connected_mcp_assistant.cta"
        case .sharedRecipe:
            return "account.feature-adoption.guide.shared_recipe.cta-done"
        }
    }
}

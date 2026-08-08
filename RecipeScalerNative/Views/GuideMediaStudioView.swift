//
//  GuideMediaStudioView.swift
//  RecipeScalerNative
//
//  Spec 040 — deterministic DEBUG-only scenes used to generate guide
//  screenshots and short walkthrough videos. External integrations are shown
//  as instruction cards or neutral mock conversations; no third-party UI is
//  impersonated and no network is required.
//

#if DEBUG
import SwiftUI

private enum GuideMediaSceneKind {
    case realApp
    case instructionCard
    case externalAssistantMock
}

private struct GuideMediaScene {
    let id: String
    let item: String
    let kind: GuideMediaSceneKind
    let launchScene: String
    let assetBaseName: String
    let titleKey: String
    let durationSeconds: Int
}

struct GuideMediaStudioView: View {
    let sceneId: String

    var body: some View {
        NavigationStack {
            if let scene = GuideMediaSceneCatalog.scene(for: sceneId) {
                GuideMediaSceneView(scene: scene)
                    .navigationTitle("guide-media.studio.title")
                    .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView {
                    Label(
                        "guide-media.missing-scene.title",
                        systemImage: "film.stack"
                    )
                } description: {
                    Text("guide-media.missing-scene.description")
                        .appBody()
                }
                .accessibilityIdentifier("guide_media_missing_scene")
            }
        }
        .accessibilityIdentifier("guide_media_studio")
    }
}

private struct GuideMediaSceneView: View {
    let scene: GuideMediaScene

    private var item: FeatureAdoptionItem {
        FeatureAdoptionItem(rawValue: scene.item) ?? .createdRecipe
    }

    var body: some View {
        Group {
            switch scene.kind {
            case .realApp:
                GuideMediaRealAppSceneView(scene: scene, item: item)
            case .instructionCard:
                GuideInstructionCardView(scene: scene, item: item)
            case .externalAssistantMock:
                GuideExternalAssistantMockView(scene: scene, item: item)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .accessibilityIdentifier("guide_media_scene_\(scene.id)")
    }
}

private enum GuideMediaSceneCatalog {
    static func scene(for id: String) -> GuideMediaScene? {
        let itemRawValue = id.split(separator: ".", maxSplits: 1).first.map(String.init)
        guard let itemRawValue, FeatureAdoptionItem(rawValue: itemRawValue) != nil else {
            return nil
        }

        let kind: GuideMediaSceneKind
        if id.hasSuffix("external-assistant")
            || id.hasSuffix("shopping-command")
            || id.hasSuffix("save-command") {
            kind = .externalAssistantMock
        } else if id.hasSuffix("instruction")
                    || id.contains(".share-instruction")
                    || id.contains(".connector-instruction")
                    || id.contains(".reminders-instruction") {
            kind = .instructionCard
        } else {
            kind = .realApp
        }

        return GuideMediaScene(
            id: id,
            item: itemRawValue,
            kind: kind,
            launchScene: id,
            assetBaseName: assetBaseName(for: id, itemRawValue: itemRawValue),
            titleKey: "account.feature-adoption.item.\(itemRawValue)",
            durationSeconds: 4
        )
    }

    private static func assetBaseName(for id: String, itemRawValue: String) -> String {
        let suffix = id.split(separator: ".", maxSplits: 1).dropFirst().first.map(String.init) ?? "scene"
        if suffix.hasPrefix("example-") {
            let number = suffix.replacingOccurrences(of: "example-", with: "")
            return "guide_\(itemRawValue)_ex_\(number)"
        }
        return "guide_\(itemRawValue)_\(suffix.replacingOccurrences(of: "-", with: "_"))"
    }
}

private struct GuideInstructionCardView: View {
    let scene: GuideMediaScene
    let item: FeatureAdoptionItem

    private var steps: [LocalizedStringKey] {
        switch scene.id {
        case "created_recipe.creation-map":
            return [
                "account.feature-adoption.guide.created_recipe.how.1",
                "account.feature-adoption.guide.created_recipe.how.2",
                "account.feature-adoption.guide.created_recipe.how.3",
                "account.feature-adoption.guide.created_recipe.how.4"
            ]
        default:
            return Array(item.guideContent.howStepKeys.prefix(3))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GuideMediaTitleBlock(item: item)

                VStack(alignment: .leading, spacing: 12) {
                    Text("guide-media.instruction.title")
                        .font(AppTypography.title3)
                    Text("guide-media.instruction.caption")
                        .appBody()
                        .foregroundStyle(.secondary)

                    ForEach(Array(steps.enumerated()), id: \.offset) { index, stepKey in
                        HStack(alignment: .top, spacing: 12) {
                            Text(verbatim: "\(index + 1)")
                                .font(AppTypography.sansMedium(16))
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .center)
                            Text(stepKey)
                                .appBody()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(20)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                ))

                if scene.id.contains("instruction") {
                    Label {
                        Text("guide-media.instruction.external-note")
                            .appFootnote()
                    } icon: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
    }
}

private struct GuideExternalAssistantMockView: View {
    let scene: GuideMediaScene
    let item: FeatureAdoptionItem

    private var promptKey: LocalizedStringKey {
        switch scene.id {
        case "connected_mcp_assistant.shopping-command":
            return "guide-media.external-assistant.shopping-prompt"
        case "connected_mcp_assistant.save-command":
            return "guide-media.external-assistant.save-prompt"
        default:
            return "guide-media.external-assistant.search-prompt"
        }
    }

    private var responseKey: LocalizedStringKey {
        switch scene.id {
        case "connected_mcp_assistant.shopping-command":
            return "guide-media.external-assistant.shopping-response"
        case "connected_mcp_assistant.save-command":
            return "guide-media.external-assistant.save-response"
        default:
            return "guide-media.external-assistant.search-response"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GuideMediaTitleBlock(item: item)

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: "link")
                        Text("guide-media.external-assistant.connected")
                            .appFootnote()
                        Spacer()
                    }
                    .foregroundStyle(.secondary)

                    Text("guide-media.external-assistant.title")
                        .font(AppTypography.title3)

                    GuideMediaBubble(textKey: promptKey, isUser: true)
                    GuideMediaBubble(textKey: responseKey, isUser: false)
                }
                .padding(18)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                ))

                Text("guide-media.external-assistant.disclaimer")
                    .appFootnote()
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
    }
}

private struct GuideMediaBubble: View {
    let textKey: LocalizedStringKey
    let isUser: Bool

    var body: some View {
        Text(textKey)
            .appBody()
            .foregroundStyle(isUser ? Color.primary : Color.primary.opacity(0.9))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isUser
                    ? Color.accentColor.opacity(0.16)
                    : Color(.tertiarySystemFill),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
    }
}

private struct GuideMediaRealAppSceneView: View {
    let scene: GuideMediaScene
    let item: FeatureAdoptionItem

    var body: some View {
        Group {
            if item == .sentAssistantMessage {
                GuideMediaAssistantFixtureSceneView(scene: scene)
            } else if scene.id.hasPrefix("imported_recipe.") {
                GuideMediaImportSceneView(scene: scene, item: item)
            } else {
                GuideMediaAppCard(scene: scene, item: item)
            }
        }
    }
}

private struct GuideMediaAssistantFixtureSceneView: View {
    let scene: GuideMediaScene

    var body: some View {
        VStack(spacing: 0) {
            Text("assistant.title")
                .font(AppTypography.title3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    GuideMediaBubble(
                        textKey: assistantPromptKey,
                        isUser: true
                    )
                    GuideMediaBubble(
                        textKey: assistantResponseKey,
                        isUser: false
                    )
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemBackground))
        .accessibilityIdentifier("guide_media_assistant_fixture")
    }

    private var assistantPromptKey: LocalizedStringKey {
        switch scene.id {
        case "sent_assistant_message.example-02":
            return "guide-media.assistant.example-02.prompt"
        case "sent_assistant_message.example-03":
            return "guide-media.assistant.example-03.prompt"
        case "sent_assistant_message.example-04":
            return "guide-media.assistant.example-04.prompt"
        case "sent_assistant_message.example-05":
            return "guide-media.assistant.example-05.prompt"
        default:
            return "guide-media.assistant.example-01.prompt"
        }
    }

    private var assistantResponseKey: LocalizedStringKey {
        switch scene.id {
        case "sent_assistant_message.example-02":
            return "guide-media.assistant.example-02.response"
        case "sent_assistant_message.example-03":
            return "guide-media.assistant.example-03.response"
        case "sent_assistant_message.example-04":
            return "guide-media.assistant.example-04.response"
        case "sent_assistant_message.example-05":
            return "guide-media.assistant.example-05.response"
        default:
            return "guide-media.assistant.example-01.response"
        }
    }
}

private struct GuideMediaImportSceneView: View {
    let scene: GuideMediaScene
    let item: FeatureAdoptionItem

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
            GuideMediaAppCard(scene: scene, item: item)
        }
        .accessibilityIdentifier("guide_media_import_scene")
    }
}

private struct GuideMediaAppCard: View {
    let scene: GuideMediaScene
    let item: FeatureAdoptionItem

    private var titleKey: LocalizedStringKey {
        switch scene.id {
        case "imported_recipe.import-text":
            return "guide-media.app.import-text.title"
        case "imported_recipe.import-photo":
            return "guide-media.app.import-photo.title"
        case "used_shopping_list.shopping-list":
            return "guide-media.app.shopping.title"
        case "connected_telegram.connection-code":
            return "guide-media.app.telegram.title"
        case "created_collection.collections":
            return "guide-media.app.collections.title"
        case "shared_recipe.public-profile":
            return "guide-media.app.public-profile.title"
        default:
            return "guide-media.app.creation-map.title"
        }
    }

    private var detailKeys: [LocalizedStringKey] {
        switch scene.id {
        case "imported_recipe.import-text":
            return [
                "guide-media.app.import-text.detail",
                "guide-media.app.import-text.value"
            ]
        case "imported_recipe.import-photo":
            return [
                "guide-media.app.import-photo.detail",
                "guide-media.app.import-photo.value"
            ]
        case "used_shopping_list.shopping-list":
            return [
                "guide-media.app.shopping.detail",
                "guide-media.app.shopping.value"
            ]
        case "connected_telegram.connection-code":
            return [
                "guide-media.app.telegram.detail",
                "guide-media.app.telegram.value"
            ]
        case "created_collection.collections":
            return [
                "guide-media.app.collections.detail",
                "guide-media.app.collections.value"
            ]
        case "shared_recipe.public-profile":
            return [
                "guide-media.app.public-profile.detail",
                "guide-media.app.public-profile.value"
            ]
        default:
            return [
                "guide-media.app.creation-map.detail",
                "guide-media.app.creation-map.value"
            ]
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GuideMediaTitleBlock(item: item)

                VStack(alignment: .leading, spacing: 16) {
                    Text(titleKey)
                        .font(AppTypography.title2)

                    ForEach(Array(detailKeys.enumerated()), id: \.offset) { index, key in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: index == 0 ? "checkmark.circle.fill" : "arrow.right.circle")
                                .foregroundStyle(index == 0 ? .green : .secondary)
                            Text(key)
                                .appBody()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(20)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                ))
            }
            .padding(20)
        }
    }
}

private struct GuideMediaTitleBlock: View {
    let item: FeatureAdoptionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("guide-media.studio.preview-label")
                .appFootnote()
                .foregroundStyle(.secondary)
            Text(item.titleKey)
                .font(AppTypography.display(30))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview("Instruction") {
    GuideMediaStudioView(sceneId: "connected_mcp_assistant.connector-instruction")
}

#Preview("External assistant") {
    GuideMediaStudioView(sceneId: "connected_mcp_assistant.external-assistant")
}
#endif

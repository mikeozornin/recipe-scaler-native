//
//  FeatureAdoptionGuideView.swift
//  RecipeScalerNative
//
//  Spec 040 — per-item drill-in screen behind `FeatureAdoptionRow`. Layout:
//  status badge → why → (media, added in later phases) → how → (carousel,
//  added in later phases) → CTA.
//

import SwiftUI

struct FeatureAdoptionGuideView: View {
    let item: FeatureAdoptionItem

    @Environment(FeatureAdoptionStore.self) private var store
    @Environment(\.featureAdoptionAppCta) private var appCta
    @Environment(\.featureAdoptionProfileScrollCta) private var profileScrollCta
    @Environment(\.dismiss) private var dismiss

    private var content: FeatureAdoptionGuideContent {
        item.guideContent
    }

    private var isDone: Bool {
        store.value(for: item)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                statusBadge

                whyBlock

                if let videoResourceName = content.videoResourceName {
                    GuideVideoPlayer(resourceName: videoResourceName)
                }

                howBlock

                if let exampleImages = content.exampleImages, !exampleImages.isEmpty {
                    carouselBlock(exampleImages: exampleImages)
                }

                if let carouselHintKey = content.carouselHintKey {
                    Text(carouselHintKey)
                        .appFootnote()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let ctaTitleKey = content.ctaTitleKey {
                    ctaButton(titleKey: isDone ? (content.ctaDoneTitleKey ?? ctaTitleKey) : ctaTitleKey)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(item.titleKey)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Blocks

    private var statusBadge: some View {
        HStack {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isDone ? Color.green : Color.secondary)
            Text(verbatim: Bundle.currentLocalizedString(
                isDone
                    ? "account.feature-adoption.state.done"
                    : "account.feature-adoption.state.pending"
            ))
            .appFootnote()
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var whyBlock: some View {
        Text(content.whyKey)
            .appBody()
            .fixedSize(horizontal: false, vertical: true)
    }

    private var howBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(content.howStepKeys.enumerated()), id: \.offset) { index, stepKey in
                HStack(alignment: .top, spacing: 12) {
                    Text(verbatim: "\(index + 1)")
                        .font(AppTypography.sansMedium(16))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .center)
                        .accessibilityHidden(true)
                    Text(stepKey)
                        .appBody()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func ctaButton(titleKey: LocalizedStringKey) -> some View {
        Button {
            handleCTA(content.primaryCTA)
        } label: {
            Text(titleKey)
                .font(AppTypography.sansMedium(16))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    @ViewBuilder
    private func carouselBlock(exampleImages: [GuideExampleImage]) -> some View {
        GuideExampleCarousel(images: exampleImages)
            .frame(maxWidth: .infinity)
    }

    // MARK: - CTA dispatch

    private func handleCTA(_ ctaCase: GuideCTA?) {
        guard let ctaCase else { return }
        switch ctaCase {
        case .openAssistant:
            dismiss()
            appCta.openAssistant()
        case .openImportTab:
            dismiss()
            appCta.openImport()
        case .openProfileTelegram:
            dismiss()
            profileScrollCta.openTelegramSection()
        case .openProfilePublicSettings:
            dismiss()
            profileScrollCta.openPublicProfileSection()
        case .openSafari(let url):
            appCta.openSafari(url)
        }
    }
}

// MARK: - Previews

#Preview("Done + CTA", traits: .fixedLayout(width: 390, height: 844)) {
    let store = FeatureAdoptionStore()
    store.report = FeatureAdoptionReport(
        installedNativeApp: true,
        importedRecipe: true,
        createdRecipe: true,
        createdCollection: true,
        sharedRecipe: true,
        connectedTelegram: true,
        connectedMcpAssistant: true,
        sentAssistantMessage: true,
        usedShoppingList: true
    )
    return NavigationStack {
        FeatureAdoptionGuideView(item: .importedRecipe)
            .environment(store)
    }
}

#Preview("Pending + no CTA", traits: .fixedLayout(width: 390, height: 844)) {
    let store = FeatureAdoptionStore()
    return NavigationStack {
        FeatureAdoptionGuideView(item: .usedShoppingList)
            .environment(store)
    }
}

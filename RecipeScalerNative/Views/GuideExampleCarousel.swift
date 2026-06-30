//
//  GuideExampleCarousel.swift
//  RecipeScalerNative
//
//  Spec 040 — horizontally scrollable image gallery with page dots and
//  VoiceOver-friendly accessibility labels. Renders `GuideAssetPlaceholder`
//  when an image is not yet bundled.
//

import SwiftUI

struct GuideExampleCarousel: View {
    let images: [GuideExampleImage]
    let aspectRatio: CGFloat

    @State private var currentIndex: Int = 0
    @State private var availableWidth: CGFloat = 0

    init(images: [GuideExampleImage], aspectRatio: CGFloat = GuideAssetPlaceholder.defaultAspectRatio) {
        self.images = images
        self.aspectRatio = aspectRatio
    }

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                carouselPage(image: image, index: index)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .frame(height: pageHeight)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { availableWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newValue in
                        availableWidth = newValue
                    }
            }
        )
        .accessibilityElement(children: .contain)
    }

    // MARK: - Subviews

    @ViewBuilder
    private func carouselPage(image: GuideExampleImage, index: Int) -> some View {
        Group {
            if let resolved = GuideAssetResolver.image(forBaseName: image.assetName) {
                resolved
                    .resizable()
                    .scaledToFill()
            } else {
                GuideAssetPlaceholder(name: image.assetName)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: pageHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(image.accessibilityLabelKey)
        .accessibilityValue(Text(verbatim: "\(index + 1) / \(images.count)"))
    }

    // MARK: - Layout

    /// Page height follows the carousel's own width via `GeometryReader`.
    /// Falls back to a sensible default before the first layout pass.
    private var pageHeight: CGFloat {
        let width = availableWidth > 0 ? availableWidth : defaultFallbackWidth
        return width / aspectRatio
    }

    private let defaultFallbackWidth: CGFloat = 320
}

// MARK: - Previews

#Preview {
    GuideExampleCarousel(
        images: [
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
        ]
    )
    .padding(.horizontal, 20)
}

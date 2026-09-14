//
//  ClipboardImportBanner.swift
//  RecipeScalerNative
//
//  Spec 076 — bottom clipboard import prompt.
//

import SwiftUI

struct ClipboardBannerHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ClipboardImportBanner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let onImport: () -> Void
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        HStack(alignment: .center, spacing: ClipboardImportBannerLayout.stackSpacing) {
            Text("import.clipboard-banner.message")
                .appBody()
                .multilineTextAlignment(.leading)
                .lineLimit(ClipboardImportBannerLayout.messageLineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(AccessibilityIdentifiers.clipboardImportBannerMessage)
            Button(action: onImport) {
                AppSymbol.image("checkmark")
                    .font(AppTypography.iconSize(AppTypography.bodySize))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .modifier(ClipboardImportActionButtonChrome())
            .frame(
                width: ClipboardImportBannerLayout.actionSide,
                height: ClipboardImportBannerLayout.actionSide
            )
            .accessibilityLabel(Text("import.lets-go"))
            .accessibilityIdentifier(AccessibilityIdentifiers.clipboardImportBannerAction)
        }
        .padding(.horizontal, ClipboardImportBannerLayout.innerHorizontalPadding)
        .padding(.vertical, ClipboardImportBannerLayout.innerVerticalPadding)
        .frame(maxWidth: bannerMaxWidth)
        .modifier(ClipboardImportBannerChrome())
        .offset(y: reduceMotion ? 0 : dragOffset)
        .opacity(reduceMotion && dragOffset > 0 ? max(0.35, 1 - dragOffset / 120) : 1)
        .gesture(swipeGesture)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityIdentifiers.clipboardImportBanner)
        .accessibilityAction(named: Text("common.close")) {
            onDismiss()
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: ClipboardBannerHeightKey.self, value: proxy.size.height)
            }
        }
    }

    private var bannerMaxWidth: CGFloat {
        horizontalSizeClass == .regular ? ClipboardImportBannerLayout.iPadMaxWidth : .infinity
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                let shouldDismiss = value.translation.height >= ClipboardImportBannerLayout.swipeDismissDistance
                    || value.predictedEndTranslation.height >= ClipboardImportBannerLayout.swipeDismissDistance
                if shouldDismiss {
                    onDismiss()
                } else if reduceMotion {
                    dragOffset = 0
                } else {
                    withAnimation(.easeOut(duration: ClipboardImportBannerLayout.appearDuration)) {
                        dragOffset = 0
                    }
                }
            }
    }
}

private struct ClipboardImportActionButtonChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
        } else {
            content.buttonStyle(ClipboardImportActionLegacyButtonStyle())
        }
    }
}

private struct ClipboardImportActionLegacyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background {
                Circle()
                    .fill(Color.accentColor)
            }
            .frame(
                width: ClipboardImportBannerLayout.actionSide,
                height: ClipboardImportBannerLayout.actionSide
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

private struct ClipboardImportBannerChrome: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(
                .regular.interactive(),
                in: RoundedRectangle(
                    cornerRadius: ClipboardImportBannerLayout.cornerRadius,
                    style: .continuous
                )
            )
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(
                        cornerRadius: ClipboardImportBannerLayout.cornerRadius,
                        style: .continuous
                    )
                )
                .shadow(
                    color: .black.opacity(colorScheme == .dark ? 0.35 : 0.18),
                    radius: 10,
                    y: 4
                )
        }
    }
}

#Preview("clipboard-banner-light") {
    ClipboardImportBanner(onImport: {}, onDismiss: {})
        .padding()
        .preferredColorScheme(.light)
}

#Preview("clipboard-banner-dark") {
    ClipboardImportBanner(onImport: {}, onDismiss: {})
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("clipboard-banner-xxxl-se") {
    ClipboardImportBanner(onImport: {}, onDismiss: {})
        .frame(width: 320)
        .environment(\.dynamicTypeSize, .accessibility5)
        .padding()
}

#Preview("clipboard-banner-en") {
    ClipboardImportBanner(onImport: {}, onDismiss: {})
        .environment(\.locale, Locale(identifier: "en"))
        .padding()
}

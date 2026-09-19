import SwiftUI
import UIKit

/// Sticky status strip when keep-awake is on.
struct ScreenAwakeStatusBanner: View {
    var voiceEnabled: Bool
    var handEnabled: Bool
    var faceEnabled: Bool
    var lastPulseByChannel: [AwakeScrollInputChannel: Date] = [:]
    var onHelp: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var indicatorPulse = false

    private var bannerBackground: Color {
        colorScheme == .dark ? Color.green.opacity(0.22) : Color.green.opacity(0.14)
    }

    private var bannerBorder: Color {
        colorScheme == .dark ? Color.green.opacity(0.38) : Color.green.opacity(0.28)
    }

    private var bannerText: Color {
        colorScheme == .dark ? Color(red: 0.55, green: 0.85, blue: 0.65) : Color(red: 0.1, green: 0.45, blue: 0.2)
    }

    private var handSymbolName: String {
        if UIImage(systemName: AwakeScrollLayout.bannerHandSymbol) != nil {
            return AwakeScrollLayout.bannerHandSymbol
        }
        return AwakeScrollLayout.bannerHandFallbackSymbol
    }

    var body: some View {
        HStack(spacing: AwakeScrollLayout.bannerAccessoryGap) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .opacity(indicatorPulse ? 1 : 0.45)
            HStack(spacing: AwakeScrollLayout.bannerTitleIconGap) {
                Text("recipe.awake-scroll.banner")
                    .appBody()
                    .foregroundStyle(bannerText)
                    .lineLimit(1)
                if voiceEnabled {
                    channelIcon(
                        "waveform",
                        identifier: AccessibilityIdentifiers.screenAwakeBannerIconVoice,
                        labelKey: "recipe.awake-scroll.help.icon.voice",
                        pulseAt: lastPulseByChannel[.voice]
                    )
                }
                if handEnabled {
                    channelIcon(
                        handSymbolName,
                        identifier: AccessibilityIdentifiers.screenAwakeBannerIconHand,
                        labelKey: "recipe.awake-scroll.help.icon.hand",
                        pulseAt: lastPulseByChannel[.hand]
                    )
                }
                if faceEnabled {
                    channelIcon(
                        "face.smiling",
                        identifier: AccessibilityIdentifiers.screenAwakeBannerIconFace,
                        labelKey: "recipe.awake-scroll.help.icon.face",
                        pulseAt: lastPulseByChannel[.face]
                    )
                }
            }
            Spacer(minLength: 0)
            Button(action: onHelp) {
                AppSymbol.image("ellipsis")
                    .frame(
                        width: AwakeScrollLayout.bannerAccessorySize,
                        height: AwakeScrollLayout.bannerAccessorySize
                    )
                    .foregroundStyle(bannerText)
                    .frame(
                        width: AwakeScrollLayout.bannerAccessoryHit,
                        height: AwakeScrollLayout.bannerAccessoryHit
                    )
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("recipe.awake-scroll.menu")
            .accessibilityIdentifier(AccessibilityIdentifiers.screenAwakeBannerMenu)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(bannerBackground)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(bannerBorder)
                .frame(height: 0.5)
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.screenAwakeBanner)
        .onAppear {
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                indicatorPulse = true
            }
        }
    }

    private func channelIcon(
        _ systemName: String,
        identifier: String,
        labelKey: LocalizedStringKey,
        pulseAt: Date?
    ) -> some View {
        ScreenAwakeBannerChannelIcon(
            systemName: systemName,
            identifier: identifier,
            labelKey: labelKey,
            tint: bannerText,
            pulseAt: pulseAt
        )
    }
}

private struct ScreenAwakeBannerChannelIcon: View {
    var systemName: String
    var identifier: String
    var labelKey: LocalizedStringKey
    var tint: Color
    var pulseAt: Date?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isScaled = false
    @State private var bounceTask: Task<Void, Never>?

    var body: some View {
        AppSymbol.sizedImage(
            systemName,
            pointSize: AwakeScrollLayout.bannerChannelIconSize,
            weight: .semibold
        )
        .foregroundStyle(tint)
        .frame(
            width: AwakeScrollLayout.bannerChannelIconSize,
            height: AwakeScrollLayout.bannerChannelIconSize
        )
        .scaleEffect(isScaled ? AwakeScrollLayout.bannerChannelPulseScale : 1)
        .accessibilityLabel(labelKey)
        .accessibilityIdentifier(identifier)
        .onChange(of: pulseAt) { _, newValue in
            guard newValue != nil else { return }
            bounce()
        }
        .onDisappear {
            bounceTask?.cancel()
            bounceTask = nil
        }
    }

    private func bounce() {
        bounceTask?.cancel()
        guard !reduceMotion else { return }
        let duration = AwakeScrollLayout.bannerChannelPulseDuration
        withAnimation(.easeInOut(duration: duration)) {
            isScaled = true
        }
        bounceTask = Task { @MainActor in
            let nanos = UInt64(duration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: duration)) {
                isScaled = false
            }
        }
    }
}

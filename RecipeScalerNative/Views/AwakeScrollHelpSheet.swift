import SwiftUI
import UIKit

struct AwakeScrollHelpSheet: View {
    var controller: AwakeScrollController
    @Binding var voiceEnabled: Bool
    @Binding var handEnabled: Bool
    @Binding var faceEnabled: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AwakeScrollLayout.helpSheetSectionGap) {
                    Text("recipe.awake-scroll.help.title")
                        .font(AppTypography.title3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                    Text("recipe.awake-scroll.help.intro")
                        .appBody()
                        .frame(maxWidth: .infinity, minHeight: AwakeScrollLayout.helpIntroRowMinHeight, alignment: .leading)
                    HStack(alignment: .top, spacing: AwakeScrollLayout.helpChipGap) {
                        AppSymbol.sizedImage(
                            "switch.2",
                            pointSize: AwakeScrollLayout.helpEnergyGlyphSize,
                            weight: .regular
                        )
                        .frame(
                            width: AwakeScrollLayout.helpEnergyGlyphSize,
                            height: AwakeScrollLayout.helpEnergyGlyphSize
                        )
                        .accessibilityHidden(true)
                        Text("recipe.awake-scroll.help.energy")
                            .appBody()
                    }
                    .frame(maxWidth: .infinity, minHeight: AwakeScrollLayout.helpIntroRowMinHeight, alignment: .leading)

                    channelToggle(
                        titleKey: "recipe.awake-scroll.voice",
                        isOn: $voiceEnabled,
                        denied: controller.lastPermissions.voiceBlocked,
                        deniedKey: voiceDeniedKey,
                        identifier: AccessibilityIdentifiers.screenAwakeVoiceToggle
                    )
                    if voiceEnabled, !controller.lastPermissions.voiceBlocked {
                        voiceLiveBlock
                    }

                    channelToggle(
                        titleKey: "recipe.awake-scroll.hand",
                        isOn: $handEnabled,
                        denied: controller.lastPermissions.cameraBlocked,
                        deniedKey: "recipe.awake-scroll.help.denied.camera",
                        identifier: AccessibilityIdentifiers.screenAwakeHandToggle
                    )
                    if handEnabled, !controller.lastPermissions.cameraBlocked {
                        tryHint("recipe.awake-scroll.help.try-hand")
                        gestureIcons
                    }

                    if controller.showsFaceChannel {
                        channelToggle(
                            titleKey: "recipe.awake-scroll.face",
                            isOn: $faceEnabled,
                            denied: controller.lastPermissions.cameraBlocked,
                            deniedKey: "recipe.awake-scroll.help.denied.camera",
                            identifier: AccessibilityIdentifiers.screenAwakeFaceToggle
                        )
                        if faceEnabled, !controller.lastPermissions.cameraBlocked {
                            tryHint("recipe.awake-scroll.help.try-face")
                            faceIcons
                        }
                    }

                    if controller.lastPermissions.showsOpenSettings {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("recipe.awake-scroll.help.open-settings")
                                .appBody()
                        }
                        .tint(Color.accentColor)
                        .frame(maxWidth: .infinity, minHeight: AwakeScrollLayout.helpToggleRowHeight, alignment: .leading)
                        .accessibilityIdentifier(AccessibilityIdentifiers.screenAwakeOpenSettings)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AwakeScrollLayout.helpSheetHorizontalPad)
                .padding(.top, AwakeScrollLayout.helpSheetTopPad)
                .padding(.bottom, AwakeScrollLayout.helpSheetSectionGap)
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                controller.refreshPermissions()
            }
        }
    }

    private var voiceDeniedKey: LocalizedStringKey {
        if controller.lastPermissions.speechDenied, !controller.lastPermissions.micDenied {
            "recipe.awake-scroll.help.denied.speech"
        } else {
            "recipe.awake-scroll.help.denied.mic"
        }
    }

    private func channelToggle(
        titleKey: LocalizedStringKey,
        isOn: Binding<Bool>,
        denied: Bool,
        deniedKey: LocalizedStringKey,
        identifier: String
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey)
                    .appHeadline()
                    .fixedSize(horizontal: false, vertical: true)
                if denied {
                    Text(deniedKey)
                        .appFootnote()
                        .foregroundStyle(Color.orange)
                }
            }
        }
        .disabled(denied)
        .frame(minHeight: denied ? AwakeScrollLayout.helpDeniedRowMinHeight : AwakeScrollLayout.helpToggleRowHeight)
        .accessibilityIdentifier(identifier)
    }

    private var voiceLiveBlock: some View {
        VStack(alignment: .leading, spacing: AwakeScrollLayout.helpChipGap) {
            tryHint("recipe.awake-scroll.help.try-voice")
            Text("recipe.awake-scroll.help.voice-listening")
                .appFootnote()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
                AwakeScrollChipFlow(spacing: AwakeScrollLayout.helpChipGap) {
                    ForEach(AwakeScrollVoiceChip.allCases, id: \.self) { chip in
                        voiceChip(chip, now: timeline.date)
                    }
                }
            }
        }
    }

    private func voiceChip(_ chip: AwakeScrollVoiceChip, now: Date) -> some View {
        let fired = isVoiceChipFired(chip, now: now)
        return Text(LocalizedStringKey(chip.localizationKey))
            .appFootnote()
            .padding(.horizontal, AwakeScrollLayout.helpChipHorizontalPad)
            .frame(height: AwakeScrollLayout.helpChipHeight)
            .background(fired ? Color.green : Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(fired ? Color.white : Color.primary)
            .accessibilityIdentifier(AccessibilityIdentifiers.screenAwakeHelpChip(chip.accessibilityToken))
    }

    private var gestureIcons: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
            HStack(spacing: 0) {
                gestureIcon(
                    "hand.thumbsup.fill",
                    identifier: AccessibilityIdentifiers.screenAwakeHelpIconHandUp,
                    fired: isChannelFired(.hand, action: .up, now: timeline.date)
                )
                gestureIcon(
                    "hand.thumbsdown.fill",
                    identifier: AccessibilityIdentifiers.screenAwakeHelpIconHandDown,
                    fired: isChannelFired(.hand, action: .down, now: timeline.date)
                )
            }
            .frame(height: AwakeScrollLayout.helpGestureRowHeight)
        }
    }

    private var faceIcons: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
            HStack(spacing: 0) {
                gestureIcon(
                    "eye.fill",
                    identifier: AccessibilityIdentifiers.screenAwakeHelpIconFaceUp,
                    fired: isChannelFired(.face, action: .up, now: timeline.date)
                )
                gestureIcon(
                    "eye.fill",
                    identifier: AccessibilityIdentifiers.screenAwakeHelpIconFaceDown,
                    fired: isChannelFired(.face, action: .down, now: timeline.date)
                )
            }
            .frame(height: AwakeScrollLayout.helpGestureRowHeight)
        }
    }

    private func gestureIcon(_ systemName: String, identifier: String, fired: Bool) -> some View {
        AppSymbol.sizedImage(
            systemName,
            pointSize: AwakeScrollLayout.helpGestureIconSize,
            weight: .regular
        )
        .foregroundStyle(fired ? Color.green : Color.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(identifier)
    }

    private func tryHint(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .appBody()
            .frame(maxWidth: .infinity, minHeight: AwakeScrollLayout.helpTryHintHeight, alignment: .leading)
    }

    private func isVoiceChipFired(_ chip: AwakeScrollVoiceChip, now: Date) -> Bool {
        guard controller.lastVoiceChip == chip,
              let pulsed = controller.lastPulseByChannel[.voice] else { return false }
        return now.timeIntervalSince(pulsed) < AwakeScrollLayout.helpDebugFiredDuration
    }

    private func isChannelFired(
        _ channel: AwakeScrollInputChannel,
        action: AwakeScrollAction,
        now: Date
    ) -> Bool {
        guard controller.lastActionByChannel[channel] == action,
              let pulsed = controller.lastPulseByChannel[channel] else { return false }
        return now.timeIntervalSince(pulsed) < AwakeScrollLayout.helpDebugFiredDuration
    }
}

private struct AwakeScrollChipFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            width = max(width, x - spacing)
        }
        return (CGSize(width: width, height: y + rowHeight), origins)
    }
}

#Preview("off") {
    let controller = AwakeScrollController()
    controller.startsRealEngines = false
    return AwakeScrollHelpSheet(
        controller: controller,
        voiceEnabled: .constant(false),
        handEnabled: .constant(false),
        faceEnabled: .constant(false)
    )
}

#Preview("voice-hand") {
    let controller = AwakeScrollController()
    controller.startsRealEngines = false
    return AwakeScrollHelpSheet(
        controller: controller,
        voiceEnabled: .constant(true),
        handEnabled: .constant(true),
        faceEnabled: .constant(false)
    )
}

#Preview("denied") {
    let controller = AwakeScrollController()
    controller.startsRealEngines = false
    controller.applyPermissionSnapshot(.denied)
    return AwakeScrollHelpSheet(
        controller: controller,
        voiceEnabled: .constant(false),
        handEnabled: .constant(false),
        faceEnabled: .constant(false)
    )
}

#Preview("voice-fired") {
    let controller = AwakeScrollController()
    controller.startsRealEngines = false
    controller.notePulse(.voice, action: .up, chip: .up)
    return AwakeScrollHelpSheet(
        controller: controller,
        voiceEnabled: .constant(true),
        handEnabled: .constant(false),
        faceEnabled: .constant(false)
    )
}

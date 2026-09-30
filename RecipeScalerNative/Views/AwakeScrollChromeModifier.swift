import SwiftUI

struct AwakeScrollChromeModifier: ViewModifier {
    var controller: AwakeScrollController
    var isScreenAwakeActive: Bool
    var assistantSheetOpen: Bool
    var cookingCoverPresented: Bool
    @Binding var voiceEnabled: Bool
    @Binding var handEnabled: Bool
    @Binding var faceEnabled: Bool
    @Binding var showingHelp: Bool
    var onArmFlagsChanged: () -> Void
    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if isScreenAwakeActive {
                    ScreenAwakeStatusBanner(
                        voiceEnabled: voiceEnabled,
                        handEnabled: handEnabled,
                        faceEnabled: faceEnabled,
                        lastPulseByChannel: controller.lastPulseByChannel,
                        onHelp: { showingHelp = true }
                    )
                }
            }
            .sheet(isPresented: $showingHelp, onDismiss: onArmFlagsChanged) {
                AwakeScrollHelpSheet(
                    controller: controller,
                    voiceEnabled: $voiceEnabled,
                    handEnabled: $handEnabled,
                    faceEnabled: $faceEnabled
                )
                .appOpaqueSheetPresentationPlain(detents: [.large])
            }
            .onChange(of: isScreenAwakeActive) { _, active in
                ScreenAwakeController.setActive(active)
                onArmFlagsChanged()
            }
            .onChange(of: voiceEnabled) { _, _ in
                onArmFlagsChanged()
            }
            .onChange(of: handEnabled) { _, isOn in
                if isOn { faceEnabled = false }
                onArmFlagsChanged()
            }
            .onChange(of: faceEnabled) { _, isOn in
                if isOn { handEnabled = false }
                onArmFlagsChanged()
            }
            .onChange(of: assistantSheetOpen) { _, _ in
                onArmFlagsChanged()
            }
            .onChange(of: cookingCoverPresented) { _, _ in
                onArmFlagsChanged()
            }
            .onChange(of: locale.identifier) { _, _ in
                controller.restartVoiceForLocaleChange()
            }
    }
}

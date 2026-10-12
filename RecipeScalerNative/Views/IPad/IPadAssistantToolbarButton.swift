import SwiftUI

/// ✦ in the toolbars of «Покупки» and «Подборки» on `.padRegular` (spec 081, FR-007).
/// Opens the assistant the same way as the «Ассистент» tab: on these screens no recipe
/// is visible, so the chat starts empty. Until the inspector lands (US5) that is the
/// phone sheet.
///
/// Toolbar content: the coordinator is passed in, never read with
/// `@Environment(SomeObservable.self)` (plan.md, the iOS 26 trap).
struct IPadAssistantToolbarButton: View {
    let coordinator: AppShellCoordinator

    var body: some View {
        Button {
            coordinator.handleTabSelection(.assistant)
        } label: {
            AppToolbarStyle.iconOnly(systemName: AppTab.assistant.tabBarSymbol)
        }
        .appToolbarIconButton()
        .accessibilityLabel(Text(AppTab.assistant.title))
        .accessibilityIdentifier(AccessibilityIdentifiers.ipadAssistantToolbarButton)
    }
}

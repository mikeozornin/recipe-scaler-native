import SwiftUI

/// ✦ in the toolbars of «Покупки», «Подборки» and the recipe panel on `.padRegular`
/// (spec 081, FR-007, FR-013), only while the sidebar is shown: in the top tab bar the
/// pinned «Ассистент» tab is the one entry (`IPadLayoutPolicy.showsAssistantToolbarButton`).
/// Opens the assistant the same way as the «Ассистент» tab. Until the inspector lands
/// (US3) that is the phone sheet.
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

import SwiftUI

/// ✦ in the toolbars of «Покупки», «Подборки» and the recipe panel on `.padRegular`
/// (spec 081, FR-007, FR-013), only while the sidebar is shown: in the top tab bar the
/// pinned «Ассистент» tab is the one entry (`IPadLayoutPolicy.showsAssistantToolbarButton`).
/// Opens and closes the assistant panel the same way as the «Ассистент» tab (FR-021);
/// `startsNewChat` (✦ on «Покупки» and «Подборки») opens it with a new chat.
///
/// Toolbar content: the coordinator is passed in, never read with
/// `@Environment(SomeObservable.self)` (plan.md, the iOS 26 trap).
struct IPadAssistantToolbarButton: View {
    let coordinator: AppShellCoordinator
    var startsNewChat = false

    var body: some View {
        Button {
            coordinator.handleAssistantToolbarTap(startsNewChat: startsNewChat)
        } label: {
            AppToolbarStyle.iconOnly(systemName: AppTab.assistant.tabBarSymbol)
        }
        .appToolbarIconButton()
        .accessibilityLabel(Text(AppTab.assistant.title))
        .accessibilityIdentifier(AccessibilityIdentifiers.ipadAssistantToolbarButton)
    }
}

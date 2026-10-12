import SwiftUI

/// Spec 081 (plan.md Р2a; FR-004a, FR-004b) — «Моё всё» as a form sheet over the
/// current section in a wide iPad window. Applied to the iPad tab view only.
///
/// - `.profile` selected in `.padRegular` from anywhere (tab tap, `requestRemindersSetup`,
///   ⌘4, `-OpenTab=profile`) goes back to the previous section with the sheet on top;
/// - widening a compact window on the «Профиль» tab does the same with the last section;
/// - narrowing keeps an open sheet (the system shows it full width), as in Scrapp; while
///   it is up, «Профиль» keeps the sheet instead of opening a second profile page.
///
/// Dependencies are passed in explicitly, like the rest of the iPad shell.
struct IPadProfileSheetModifier: ViewModifier {
    @Bindable var coordinator: AppShellCoordinator
    let auth: AuthService
    let timer: TimerManager
    let vkusvillSettings: VkusvillSettingsStore
    let performLogoutTeardown: () async -> Void

    @Environment(\.appLayoutMode) private var layoutMode

    func body(content: Content) -> some View {
        content
            .onChange(of: coordinator.selectedTab) { previous, _ in
                coordinator.normalizeProfileSelection(previous: previous, layoutMode: layoutMode)
            }
            .onChange(of: layoutMode, initial: true) { _, mode in
                guard mode == .padRegular else { return }
                coordinator.normalizeProfileSelection(
                    previous: coordinator.lastNonProfileTab,
                    layoutMode: mode
                )
            }
            .sheet(
                isPresented: $coordinator.isProfileSheetPresented,
                onDismiss: coordinator.profileSheetDidDismiss
            ) {
                // `AccountView` has its own `NavigationStack` and the «Моё всё» title.
                AccountView(
                    auth: auth,
                    timer: timer,
                    vkusvillSettings: vkusvillSettings,
                    performLogoutTeardown: performLogoutTeardown,
                    onDone: { coordinator.isProfileSheetPresented = false }
                )
                .iPadFormSheet()
            }
    }
}

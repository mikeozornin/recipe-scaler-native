import SwiftUI

/// The profile row at the bottom of the iPad sidebar (spec 081, plan.md Р2a, layout.md
/// `.sb-foot`): avatar and name, or the account number. A tap opens «Моё всё» as a form
/// sheet; the row is never selected and the sidebar selection does not change.
///
/// Dependencies are passed in explicitly: the sidebar bottom bar is hosted by UIKit, where
/// iOS 26 may hand it a fallback environment (`@Environment(Observable)` traps).
@available(iOS 26.2, *)
struct IPadSidebarProfileFooter: View {
    let coordinator: AppShellCoordinator
    let auth: AuthService
    let syncService: YjsSyncService
    @State private var viewModel: AccountSettingsViewModel

    init(
        coordinator: AppShellCoordinator,
        auth: AuthService,
        syncService: YjsSyncService,
        timer: TimerManager,
        vkusvillSettings: VkusvillSettingsStore,
        performLogoutTeardown: @escaping () async -> Void
    ) {
        self.coordinator = coordinator
        self.auth = auth
        self.syncService = syncService
        _viewModel = State(initialValue: AccountSettingsViewModel(
            auth: auth,
            timer: timer,
            vkusvillSettings: vkusvillSettings,
            performLogoutTeardown: performLogoutTeardown
        ))
    }

    /// Bumped each time the sync socket connects; see the refresh task below.
    @State private var connects = 0

    private struct FooterKey: Hashable {
        let userId: String?
        let revision: Int
        let connects: Int
    }

    var body: some View {
        Button {
            // A programmatic action does not close a floating sidebar (spike S1, workaround 3):
            // without this the sheet opens under the dimmed sidebar.
            IPadSidebarControl.hideSidebarIfOverlaying()
            coordinator.presentProfileSheet()
        } label: {
            HStack(spacing: 12) {
                AccountAvatarView(url: viewModel.avatarURL, size: IPadLayoutMetrics.footerAvatarSize)
                title
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .accessibilityIdentifier(AccessibilityIdentifiers.ipadSidebarFooter)
        .task(id: FooterKey(
            userId: auth.userId,
            revision: coordinator.profileSheetRevision,
            connects: connects
        )) {
            guard auth.userId != nil else { return }
            // `refresh` drops what it fetched if the account changed during the request.
            await viewModel.refresh(syncService: syncService)
        }
        // The row is on screen from launch. A refresh that fails there (no network, or REST
        // 401s until the device token is recovered) would keep the account number of a public
        // profile until the profile sheet next closes. Refetch whenever the socket connects,
        // as the phone `AccountView` does; the new key also cancels a refresh still in flight
        // with the stale token.
        .onChange(of: syncService.connectionState.isConnected) { _, isConnected in
            if isConnected { connects += 1 }
        }
    }

    /// The public name when the profile is public and named, otherwise the account number.
    @ViewBuilder
    private var title: some View {
        let name = viewModel.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if viewModel.publicProfileEnabled, !name.isEmpty {
            Text(verbatim: name)
                .font(AppTypography.headline)
                .foregroundStyle(.primary)
        } else if let userId = auth.userId {
            Text(verbatim: UserIdFormatter.format(userId))
                .font(AppTypography.mono(AppTypography.bodySize))
                .foregroundStyle(.primary)
        }
    }
}

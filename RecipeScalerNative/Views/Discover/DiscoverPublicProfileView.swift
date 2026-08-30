//
//  DiscoverPublicProfileView.swift
//  RecipeScalerNative
//

import RecipeScalerCore
import SwiftUI

/// Read-only public profile `@username` (web `/public/@/:username`).
///
/// Header: avatar + name + description + share-mode badge + recipe count.
/// Body: tokenized search (matches name **or** description) + adaptive grid of
/// recipe preview cards. Tapping a card opens `DiscoverRecipeView`.
struct DiscoverPublicProfileView: View {
    let username: String

    @Environment(\.apiClient) private var apiClient
    @Environment(\.discoverListState) private var discoverListState
    @Environment(AuthService.self) private var authService
    @Environment(FollowStore.self) private var followStore
    @State private var model: DiscoverPublicProfileModel?
    @State private var searchText = ""
    @State private var searchStore = DiscoverSearchStore<PublicRecipePreviewDTO>()
    @State private var searchTokens: [String] = []

    private var scope: DiscoverListScope {
        .profile(username)
    }

    var body: some View {
        Group {
            switch model?.state {
            case .idle, .loading, .none:
                ProgressView(Bundle.currentLocalizedString("discover.loading"))
                    .mobileTimerPanelBottomPadding()
            case .failed(let errorMessage):
                ContentUnavailableView {
                    AppEmptyState.label("discover.profile.not-found", symbol: "person.crop.circle.badge.exclamationmark")
                } description: {
                    Text(errorMessage).appBody()
                }
                .mobileTimerPanelBottomPadding()
            case .loaded(let response):
                content(for: response)
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: Text("search.recipes")
        )
        .task(id: username) {
            if model == nil {
                model = DiscoverPublicProfileModel(api: apiClient)
            }
            if let discoverListState {
                let saved = discoverListState.state(for: scope)
                if searchText != saved.searchText {
                    searchText = saved.searchText
                }
            }
            followStore.clearError()
            await followStore.refresh(username: username, api: apiClient)
            await model?.loadIfNeeded(username: username)
            if case .loaded(let response) = model?.state {
                searchStore.setItems(DiscoverSearch.sortedByRecipeName(response.recipes) { $0.name })
            }
        }
        .refreshable {
            await model?.refresh(username: username)
            if case .loaded(let response) = model?.state {
                searchStore.setItems(DiscoverSearch.sortedByRecipeName(response.recipes) { $0.name })
            }
        }
        .onChange(of: searchText) { _, query in
            searchTokens = DiscoverSearch.tokenize(query)
            searchStore.setQuery(query)
            discoverListState?.updateSearchText(query, for: scope)
        }
        .errorAlert(message: Binding(
            get: { followStore.lastError.map { Bundle.currentLocalizedString($0.rawValue) } },
            set: { _ in followStore.clearError() }
        ))
    }

    @ViewBuilder
    private func content(for response: PublicProfileResponseDTO) -> some View {
        let filtered = searchStore.filteredSnapshot
        let filteredIDs = filtered.map(\.id)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(for: response.profile)
                    if response.recipes.isEmpty {
                        Text("discover.profile.no-recipes")
                            .appBody()
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    } else if filtered.isEmpty {
                        Text("recipes.no-recipes")
                            .appBody()
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    } else {
                        DiscoverRecipeCardGrid(items: filtered) { recipe in
                            NavigationLink(
                                value: DiscoverRoute.recipe(
                                    id: recipe.id,
                                    allowDownloads: response.profile.allowRecipeDownloads != false,
                                    imageSource: .publicRecipe,
                                    returnContext: DiscoverRecipeReturnContext(
                                        scope: scope,
                                        recipeID: recipe.id
                                    )
                                )
                            ) {
                                DiscoverRecipeCard(recipe: recipe, searchTokens: searchTokens)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(
                                AccessibilityIdentifiers.discoverRecipeCard(recipeID: recipe.id)
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .mobileTimerPanelBottomPadding()
            }
            .onAppear {
                restoreAnchorIfNeeded(
                    filtered: filtered,
                    hasRecipes: !response.recipes.isEmpty,
                    proxy: proxy
                )
            }
            .onChange(of: filteredIDs) { _, _ in
                restoreAnchorIfNeeded(
                    filtered: filtered,
                    hasRecipes: !response.recipes.isEmpty,
                    proxy: proxy
                )
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    DiscoverFollowControls(username: username)
                }
            }
        }
    }

    private func restoreAnchorIfNeeded(
        filtered: [PublicRecipePreviewDTO],
        hasRecipes: Bool,
        proxy: ScrollViewProxy
    ) {
        guard let anchorID = discoverListState?.anchor(for: scope) else {
            return
        }
        if filtered.isEmpty, hasRecipes {
            return
        }
        guard filtered.contains(where: { $0.id == anchorID }) else {
            discoverListState?.clearAnchor(for: scope)
            return
        }
        _ = discoverListState?.consumeAnchor(for: scope)
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(anchorID, anchor: .center)
        }
    }

    @ViewBuilder
    private func header(for profile: PublicProfileDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                DiscoverAvatar(
                    avatarURL: DiscoverImageURLs.avatar(fromPublicProfile: profile.avatarUrl),
                    size: 64
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name ?? profile.username)
                        .font(AppTypography.display(22))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text("@\(profile.username)")
                        .appFootnote()
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if let description = profile.description, !description.isEmpty {
                Text(description)
                    .appBody()
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                if let shareMode = profile.shareMode {
                    ShareModeBadge(shareMode: shareMode)
                }
                Text(recipeCountText(count: profile.recipeCount))
                    .appFootnote()
                    .foregroundStyle(.secondary)
                if let followersCount = profile.followersCount {
                    Text(verbatim: followersText(count: followersCount))
                        .appFootnote()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color(.secondarySystemBackground))
                        )
                }
            }
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.discoverProfileHeader)
    }

    private func recipeCountText(count: Int) -> String {
        Bundle.appPluralizedString(key: "discover.profile.recipe-count", count: count)
    }

    private func followersText(count: Int) -> String {
        Bundle.appPluralizedString(key: "discover.follow.followers", count: count)
    }
}

/// Follow button / subscription dropdown (spec 072 US1/US2). Hidden on the
/// user's own profile; the server is the source of truth for ownership.
struct DiscoverFollowControls: View {
    let username: String

    @Environment(\.apiClient) private var apiClient
    @Environment(AuthService.self) private var authService
    @Environment(FollowStore.self) private var followStore

    /// Spinner appears only after a 1s pending delay — fast mutations
    /// (typical unfollow/follow) flip the control without a flash.
    @State private var showPendingIndicator = false

    private static let pendingIndicatorDelay: Duration = .seconds(1)

    /// A resolved own-username that matches this profile hides the controls.
    /// Unknown own username (settings never loaded) keeps them visible —
    /// tapping would only surface `follow.self-not-allowed` (US9).
    private var isOwnProfile: Bool {
        guard let own = authService.ownUsername, !own.isEmpty else { return false }
        return own.caseInsensitiveCompare(username) == .orderedSame
    }

    var body: some View {
        if !isOwnProfile {
            controls
                .task(id: followStore.isFollowingPending) {
                    guard followStore.isFollowingPending else {
                        showPendingIndicator = false
                        return
                    }
                    do {
                        try await Task.sleep(for: Self.pendingIndicatorDelay)
                        showPendingIndicator = true
                    } catch { }
                }
        }
    }

    @ViewBuilder
    private var controls: some View {
        let status = followStore.status
        if status?.following == true {
            subscriptionMenu(status: status)
        } else {
            Button {
                Task { await followStore.follow(username: username, api: apiClient) }
            } label: {
                if showPendingIndicator, followStore.isFollowingPending {
                    ProgressView()
                        .frame(minWidth: 64)
                } else {
                    Text("discover.follow.subscribe")
                        .appBody()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(followStore.isFollowingPending)
            .accessibilityIdentifier(AccessibilityIdentifiers.followButton)
        }
    }

    private func subscriptionMenu(status: FollowStatusDTO?) -> some View {
        Menu {
            Button(role: .destructive) {
                Task { await followStore.unfollow(username: username, api: apiClient) }
            } label: {
                Label("discover.follow.unsubscribe", systemImage: "person.badge.minus")
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.followMenuUnsubscribe)

            Button {
                Task { await followStore.setPushOptIn(username: username, false, api: apiClient) }
            } label: {
                Label("discover.follow.subscribe-only", systemImage: "bell.slash")
            }
            .disabled(status?.pushOptIn == false)
            .accessibilityIdentifier(AccessibilityIdentifiers.followMenuSubscribeOnly)

            Button {
                Task { await followStore.setPushOptIn(username: username, true, api: apiClient) }
            } label: {
                Label("discover.follow.subscribe-notifications", systemImage: "bell")
            }
            .disabled(status?.pushOptIn == true)
            .accessibilityIdentifier(AccessibilityIdentifiers.followMenuSubscribeNotifications)
        } label: {
            AppToolbarStyle.dropdownLabel(
                systemName: status?.pushOptIn == true
                    ? "bell.and.waves.left.and.right.fill"
                    : "bell.slash",
                title: status?.pushOptIn == true
                    ? "discover.follow.subscribed-with-notifications"
                    : "discover.follow.subscribed"
            )
        }
        .menuIndicator(.hidden)
        .disabled(followStore.isFollowingPending)
        .accessibilityIdentifier(AccessibilityIdentifiers.followMenu)
        .accessibilityLabel(Text("discover.follow.menu-label"))
    }
}

/// Compact badge describing how the profile exposes its recipes.
struct ShareModeBadge: View {
    let shareMode: PublicProfileShareMode

    var body: some View {
        Text(label)
            .appFootnote()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color(.secondarySystemBackground))
            )
    }

    private var label: String {
        switch shareMode {
        case .oneByOne:
            return Bundle.currentLocalizedString("discover.profile.share-mode.one_by_one")
        case .all:
            return Bundle.currentLocalizedString("discover.profile.share-mode.all")
        case .withImagesAndSteps:
            return Bundle.currentLocalizedString("discover.profile.share-mode.with_images_and_steps")
        }
    }
}

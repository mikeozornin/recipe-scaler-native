//
//  DiscoverFeedView.swift
//  RecipeScalerNative
//

import RecipeScalerCore
import SwiftUI

/// Discover header segment (spec 072). Ephemeral UI state — never persisted;
/// Discover always enters on «Подборки».
enum DiscoverFeedSegment: Hashable {
    case collections
    case following
}

/// «Моя лента» — personal feed of new public recipes from followed authors
/// (spec 072 US3/US14). The first successful page load extinguishes the
/// tab/segment dot («прочитано = загружено», owned by `FeedStore`); this view
/// only triggers the load and renders the store state.
struct DiscoverFeedView: View {
    var onBrowseCollections: (() -> Void)?

    @Environment(AuthService.self) private var authService
    @Environment(FeedStore.self) private var feedStore
    @Environment(FeedBadgeStore.self) private var feedBadgeStore
    @Environment(\.apiClient) private var apiClient
    @State private var hasLoadedOnce = false

    private var isAuthenticated: Bool {
        authService.userId != nil
    }

    var body: some View {
        content
            .task {
                guard isAuthenticated else { return }
                // Parallel: in airplane mode a hung badge request must not
                // delay the first feed page (the spinner gate below depends
                // only on the feed load). `markSeenLocally` inside the seen
                // echo bumps the badge epoch, so a late badge response that
                // lands after a successful feed load is discarded — no dot
                // resurrection race.
                async let badgeRefresh: Void = feedBadgeStore.refresh(api: apiClient)
                if !hasLoadedOnce {
                    hasLoadedOnce = true
                    await feedStore.loadFirstPage(api: apiClient)
                }
                _ = await badgeRefresh
            }
    }

    @ViewBuilder
    private var content: some View {
        if !isAuthenticated {
            emptyNoFollows
        } else if feedStore.isLoadingFirstPage, feedStore.items.isEmpty {
            ProgressView(Bundle.currentLocalizedString("discover.feed.loading"))
                .mobileTimerPanelBottomPadding()
                .accessibilityIdentifier(AccessibilityIdentifiers.discoverFeedList)
        } else if feedStore.items.isEmpty {
            if feedStore.pageError {
                feedErrorState
            } else if feedStore.didLoadFirstPage {
                // A successful empty page (no follows / nothing new) — the
                // only path where the empty states are truthful.
                feedEmptyState
            } else {
                // First page not loaded yet (e.g. badge refresh in flight):
                // keep the spinner instead of flashing «нет нового».
                ProgressView(Bundle.currentLocalizedString("discover.feed.loading"))
                    .mobileTimerPanelBottomPadding()
                    .accessibilityIdentifier(AccessibilityIdentifiers.discoverFeedList)
            }
        } else {
            feedList
        }
    }

    private var feedList: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                ForEach(feedStore.items) { entry in
                    NavigationLink(
                        value: DiscoverRoute.recipe(id: entry.recipeId, imageSource: .publicRecipe)
                    ) {
                        DiscoverFeedCard(entry: entry)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(AccessibilityIdentifiers.discoverFeedCard)
                    .onAppear {
                        guard isTail(entry), let cursor = feedStore.nextCursor,
                              !feedStore.pageError, !feedStore.isAppendingPage else { return }
                        Task { await feedStore.loadPage(cursor: cursor, api: apiClient) }
                    }
                }
                pageFooter
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .mobileTimerPanelBottomPadding()
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.discoverFeedList)
        .refreshable { await feedStore.refresh(api: apiClient) }
    }

    @ViewBuilder
    private var pageFooter: some View {
        if feedStore.nextCursor == nil {
            EmptyView()
        } else if feedStore.pageError {
            VStack(spacing: 12) {
                Text("discover.feed.load-error")
                    .appBody()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("common.retry") {
                    Task { await loadNextPage() }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .accessibilityIdentifier(AccessibilityIdentifiers.discoverFeedAutoLoad)
        } else if feedStore.isAppendingPage {
            ProgressView()
                .padding(.vertical, 16)
                .accessibilityIdentifier(AccessibilityIdentifiers.discoverFeedAutoLoad)
        } else {
            Color.clear
                .frame(height: 1)
                .accessibilityIdentifier(AccessibilityIdentifiers.discoverFeedAutoLoad)
        }
    }

    private var feedErrorState: some View {
        ContentUnavailableView {
            AppEmptyState.label("discover.feed.error", symbol: "wifi.exclamationmark")
        } description: {
            VStack(spacing: 0) {
                Text("discover.error-server").appBody()
                tryAgainButton
            }
        }
        .mobileTimerPanelBottomPadding()
        .accessibilityIdentifier(AccessibilityIdentifiers.discoverFeedList)
    }

    /// Empty feed (US3): the server's `has_follows=false` signal renders the
    /// «нет подписок» state; otherwise «нет нового» plus a shortcut back to
    /// «Подборки».
    @ViewBuilder
    private var feedEmptyState: some View {
        if feedStore.hasFollows == false {
            emptyNoFollows
        } else {
            ContentUnavailableView {
                AppEmptyState.label("discover.feed.empty-no-new", symbol: "tray")
            } description: {
                if let onBrowseCollections {
                    browseCollectionsButton
                }
            }
            .mobileTimerPanelBottomPadding()
            .accessibilityIdentifier(AccessibilityIdentifiers.discoverFeedList)
        }
    }

    private var emptyNoFollows: some View {
        ContentUnavailableView {
            AppEmptyState.label("discover.feed.empty-no-follows", symbol: "person.2")
        } description: {
            if let onBrowseCollections {
                browseCollectionsButton
            }
        }
        .mobileTimerPanelBottomPadding()
        .accessibilityIdentifier(AccessibilityIdentifiers.discoverFeedList)
    }

    /// Transparent button with standard control padding; the explicit
    /// `.appBody()` label keeps the 16 pt Martian size — `ContentUnavailableView`
    /// description would otherwise downsize a plain string label.
    private var tryAgainButton: some View {
        Button {
            Task { await feedStore.loadFirstPage(api: apiClient) }
        } label: {
            Text("common.try-again")
                .appBody()
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 16)
        .accessibilityIdentifier(AccessibilityIdentifiers.discoverFeedRetry)
    }

    /// Transparent button with standard control padding; the explicit
    /// `.appBody()` label keeps the 16 pt Martian size — `ContentUnavailableView`
    /// description would otherwise downsize a plain string label.
    @ViewBuilder
    private var browseCollectionsButton: some View {
        if let onBrowseCollections {
            Button {
                onBrowseCollections()
            } label: {
                Text("discover.feed.empty-cta")
                    .appBody()
            }
            .buttonStyle(.borderless)
            .padding(.vertical, 16)
        }
    }

    private func isTail(_ entry: FeedEntryDTO) -> Bool {
        entry.id == feedStore.items.last?.id
    }

    private func loadNextPage() async {
        guard let cursor = feedStore.nextCursor else { return }
        await feedStore.loadPage(cursor: cursor, api: apiClient)
    }
}

/// Feed card (web `FeedCard` parity): recipe preview with a red «Новое» chip
/// over the image, then title, author avatar + display name and the
/// publication time on the right.
struct DiscoverFeedCard: View {
    let entry: FeedEntryDTO

    private var imageURL: URL? {
        guard let imageRef = entry.imageRef, !imageRef.isEmpty else { return nil }
        return DiscoverAPI.recipeImageURL(recipeId: entry.recipeId, preview: false)
    }

    private var avatarURL: URL? {
        let raw: URL? = if let avatarRef = entry.avatarRef, !avatarRef.isEmpty {
            DiscoverAPI.avatarURL(fromPublicProfile: avatarRef)
        } else {
            DiscoverImageURLs.avatar(username: entry.username)
        }
        return DiscoverImageURLs.avatarPreviewURL(raw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                DiscoverRecipeCard(
                    imageURL: imageURL,
                    name: entry.name,
                    accentColor: .accentColor
                )
                if entry.isNew {
                    newBadge
                }
            }
            authorRow
        }
        .contentShape(Rectangle())
    }

    private var newBadge: some View {
        Text("discover.feed.new-badge")
            .appFootnote()
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Capsule(style: .continuous).fill(Color.red))
            .padding(8)
            .accessibilityIdentifier(AccessibilityIdentifiers.discoverFeedCardNewBadge)
            .accessibilityLabel(Text("discover.feed.new-badge-a11y"))
    }

    private var authorRow: some View {
        HStack(spacing: 8) {
            DiscoverAvatar(avatarURL: avatarURL, size: 24)
            Text(verbatim: entry.displayName ?? entry.username)
                .appFootnote()
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(verbatim: DiscoverFeedTimeFormatter.string(from: entry.publishedAt))
                .appFootnote()
                .foregroundStyle(.secondary)
        }
    }
}

/// Koobiq `absoluteLongDateTime` parity (web spec 072):
/// ru «16 июля, 05:04» / «16 июля 2026, 05:04»;
/// en «July 16, 05:04» / «July 16, 2025, 05:04». Full year only when it
/// differs from the current one; 24-hour time; NBSP inside date parts.
@MainActor
enum DiscoverFeedTimeFormatter {
    private static let ruParts = Parts(
        locale: Locale(identifier: "ru_RU"),
        dayMonthTemplate: "dMMMM"
    )
    private static let enParts = Parts(
        locale: Locale(identifier: "en_US"),
        dayMonthTemplate: "MMMMd"
    )

    private struct Parts {
        let dayMonth: DateFormatter
        let year: DateFormatter
        let time: DateFormatter

        init(locale: Locale, dayMonthTemplate: String) {
            dayMonth = DateFormatter()
            dayMonth.locale = locale
            dayMonth.setLocalizedDateFormatFromTemplate(dayMonthTemplate)
            year = DateFormatter()
            year.locale = locale
            year.setLocalizedDateFormatFromTemplate("y")
            time = DateFormatter()
            time.locale = locale
            time.dateFormat = "HH:mm"
        }
    }

    static func string(from isoString: String, now: Date = Date()) -> String {
        guard let date = DiscoverDateParser.parse(isoString) else { return "" }
        let isRussian = AppLanguagePreference.current == .ru
        let parts = isRussian ? ruParts : enParts
        let dayMonth = parts.dayMonth
            .string(from: date)
            .replacingOccurrences(of: " ", with: "\u{00A0}")
        let time = parts.time.string(from: date)
        let calendar = Calendar.current
        guard calendar.component(.year, from: date) != calendar.component(.year, from: now) else {
            return "\(dayMonth), \(time)"
        }
        let year = parts.year.string(from: date)
        return isRussian
            ? "\(dayMonth)\u{00A0}\(year), \(time)"
            : "\(dayMonth), \(year), \(time)"
    }
}

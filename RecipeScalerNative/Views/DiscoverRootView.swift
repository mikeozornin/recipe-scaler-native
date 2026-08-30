//
//  DiscoverRootView.swift
//  RecipeScalerNative
//

import RecipeScalerCore
import SwiftUI
import UIKit

struct DiscoverRecipeReturnContext: Hashable, Sendable {
    let scope: DiscoverListScope
    let recipeID: String
}

struct DiscoverRootView: View {
    @Binding var path: NavigationPath
    @Environment(\.apiClient) private var apiClient
    @Environment(FeedBadgeStore.self) private var feedBadgeStore
    @Environment(AppShellCoordinator.self) private var coordinator
    @State private var model: DiscoverRootModel?
    /// Ephemeral segment state (spec 072): not persisted, Discover always
    /// enters on «Подборки». A digest push bump (see `.task`/`.onChange`
    /// below) switches it to «Моя лента» once.
    @State private var segment: DiscoverFeedSegment = .collections

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                DiscoverFeedSegmentPicker(segment: $segment)
                Group {
                    switch segment {
                    case .collections:
                        if let model {
                            DiscoverRootContent(model: model)
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .mobileTimerPanelBottomPadding()
                        }
                    case .following:
                        DiscoverFeedView {
                            segment = .collections
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .localizedNavigationTitle("discover.title")
            .navigationDestination(for: DiscoverRoute.self) { route in
                switch route {
                case .collection(let slug):
                    DiscoverCollectionView(slug: slug)
                case .recipe(let id, let allowDownloads, let imageSource, let returnContext):
                    DiscoverRecipeView(
                        recipeId: id,
                        allowRecipeDownloads: allowDownloads,
                        imageSource: imageSource,
                        returnContext: returnContext
                    )
                case .profile(let username):
                    DiscoverPublicProfileView(username: username)
                }
            }
            .task {
                if model == nil {
                    model = DiscoverRootModel(api: apiClient)
                }
                if coordinator.discoverFeedRequestEpoch > 0 {
                    activateFeedSegment()
                }
            }
            .onChange(of: coordinator.discoverFeedRequestEpoch) { _, _ in
                activateFeedSegment()
            }
        }
    }

    /// Spec 072 digest push landing: select «Моя лента» and clear the new-content
    /// dot — same side effects as a manual segment tap (`DiscoverFeedSegmentPicker`).
    /// `markSeenLocally` (not `clearForLogout`) so the server marker is owned
    /// by `FeedStore` after the feed page loads.
    private func activateFeedSegment() {
        segment = .following
        feedBadgeStore.markSeenLocally()
    }
}

/// «Подборки | Моя лента» header control (spec 072). Segmented picker under
/// the navigation title; the «Моя лента» segment carries the red new-content
/// dot while unread (US4), matching the tab-bar dot semantics.
///
/// A custom SwiftUI segment, not `Picker(.segmented)`: the system control
/// flattens its labels into `UISegmentedControl` titles, so an overlay dot on
/// the label is not guaranteed to render on device (the reason
/// `RecipeNutritionBlockView` ships its own segment wrapper too). Full control
/// over the dot, hit targets and the a11y identifier the UI tests use.
/// Styling mirrors the system segmented control (ImportRecipeSheet):
/// rounded track (8) + thumb (6), Martian 16 via `AppTypography.body`.
struct DiscoverFeedSegmentPicker: View {
    @Binding var segment: DiscoverFeedSegment
    @Environment(FeedBadgeStore.self) private var feedBadgeStore

    var body: some View {
        HStack(spacing: 2) {
            segmentButton(.collections, titleKey: "discover.feed.segment-collections")
            segmentButton(.following, titleKey: "discover.feed.segment-following")
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .accessibilityIdentifier(AccessibilityIdentifiers.discoverFeedSegment)
        .accessibilityLabel(Text("discover.feed.segment-label"))
    }

    private func segmentButton(
        _ target: DiscoverFeedSegment,
        titleKey: LocalizedStringKey
    ) -> some View {
        let isSelected = segment == target
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                segment = target
            }
            if target == .following {
                feedBadgeStore.markSeenLocally()
            }
        } label: {
            Text(titleKey)
                .font(AppTypography.body)
                .foregroundStyle(Color.primary)
                .overlay(alignment: .trailing) {
                    if target == .following, feedBadgeStore.hasNew {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                            .offset(x: 8, y: -7)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color(.systemBackground) : .clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Renders the loaded discover root content. Extracted so the parent
/// `DiscoverRootView` can construct the model from `@Environment(\.apiClient)`
/// before any network call runs.
private struct DiscoverRootContent: View {
    let model: DiscoverRootModel

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                ProgressView()
                    .mobileTimerPanelBottomPadding()
            case .failed:
                ContentUnavailableView {
                    AppEmptyState.label("discover.error", symbol: "wifi.exclamationmark")
                } description: {
                    Text("discover.error-server").appBody()
                } actions: {
                    Button("common.try-again") {
                        Task { await model.load() }
                    }
                    .buttonStyle(.bordered)
                }
                .mobileTimerPanelBottomPadding()
            case .loaded(let data) where !data.collections.isEmpty || !data.profiles.isEmpty:
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if !data.collections.isEmpty {
                            section(
                                titleKey: "discover.curated-collections",
                                items: data.collections
                            ) { collection in
                                NavigationLink(
                                    value: DiscoverRoute.collection(collection.slug)
                                ) {
                                    DiscoverCollectionCard(collection: collection)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier(
                                    AccessibilityIdentifiers.discoverCollectionCard
                                )
                            }
                        }
                        if !data.profiles.isEmpty {
                            section(
                                titleKey: "discover.featured-chefs",
                                items: data.profiles
                            ) { profile in
                                NavigationLink(
                                    value: DiscoverRoute.profile(profile.username)
                                ) {
                                    DiscoverProfileCard(profile: profile)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier(
                                    AccessibilityIdentifiers.discoverProfileCard
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                    .mobileTimerPanelBottomPadding()
                }
            case .loaded:
                ContentUnavailableView {
                    AppEmptyState.label("discover.empty", symbol: "sparkles")
                } description: {
                    Text("discover.empty-description").appBody()
                }
                .mobileTimerPanelBottomPadding()
            }
        }
        .task { await model.load() }
        .refreshable { await model.load() }
        .accessibilityIdentifier(AccessibilityIdentifiers.discoverRoot)
    }

    @ViewBuilder
    private func section<Item: Identifiable, Content: View>(
        titleKey: LocalizedStringKey,
        items: [Item],
        @ViewBuilder cell: @escaping (Item) -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(titleKey)
            VStack(spacing: 0) {
                ForEach(items) { item in
                    cell(item)
                }
            }
        }
    }
}

enum DiscoverRoute: Hashable {
    case collection(String)
    case recipe(
        id: String,
        allowDownloads: Bool = true,
        imageSource: DiscoverRecipeImageSource = .curatedDiscover,
        returnContext: DiscoverRecipeReturnContext? = nil
    )
    case profile(String)
}

/// Curated collection preview card (web `CollectionCard` + cover on the right).
struct DiscoverCollectionCard: View {
    let collection: DiscoveryCollectionDTO

    private var coverURL: URL? {
        DiscoverImageURLs.collectionCover(from: collection.coverImageURL)
    }

    var body: some View {
        DiscoverRootPreviewCard(
            title: collection.title,
            subtitle: collection.description,
            badgeText: recipeCountText
        ) {
            DiscoverPreviewThumbnail(
                url: coverURL,
                fallbackColor: .accentColor,
                placeholderSymbol: "photo"
            )
        }
    }

    private var recipeCountText: String {
        Bundle.appPluralizedString(key: "discover.collection.recipe-count", count: collection.recipeCount)
    }
}

/// Featured chef preview card (web `ProfileCard`: name, recipe list, avatar right, badge).
struct DiscoverProfileCard: View {
    let profile: PublicProfilePreviewDTO

    var body: some View {
        DiscoverRootPreviewCard(
            title: profile.name ?? profile.username,
            subtitle: profile.description,
            badgeText: recipeCountText
        ) {
            DiscoverPreviewThumbnail(
                url: DiscoverImageURLs.avatar(username: profile.username),
                fallbackColor: .accentColor,
                placeholderSymbol: "person.fill",
                placeholderIconSize: 40,
                neutralPlaceholder: true
            )
        }
    }

    private var recipeCountText: String {
        Bundle.appPluralizedString(key: "discover.profile.recipe-count", count: profile.recipeCount)
    }
}

/// Shared discover root card: title + subtitle left, thumbnail right, divider, count badge.
private struct DiscoverRootPreviewCard<Thumbnail: View>: View {
    let title: String
    let subtitle: String?
    let badgeText: String
    @ViewBuilder let thumbnail: () -> Thumbnail

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(AppTypography.title3)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .appBody()
                            .foregroundStyle(.primary.opacity(0.8))
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                thumbnail()
            }
            .padding(.top, 24)
            .padding(.bottom, 12)

            Divider()

            DiscoverRecipeCountBadge(text: badgeText)
                .padding(.vertical, 12)
        }
    }
}

/// 64×64 rounded-square preview image for discover root cards.
private struct DiscoverPreviewThumbnail: View {
    let url: URL?
    let fallbackColor: Color
    let placeholderSymbol: String
    var placeholderIconSize: CGFloat = 28
    var neutralPlaceholder: Bool = false

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
        )
    }

    private var placeholder: some View {
        AppSymbol.sizedImage(placeholderSymbol, pointSize: placeholderIconSize)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(neutralPlaceholder
                          ? Color(.tertiarySystemFill)
                          : fallbackColor.opacity(0.12))
            )
    }
}

private struct DiscoverRecipeCountBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .appFootnote()
            .foregroundStyle(.primary.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
    }
}

/// Rounded-square avatar for discover public profiles (matches `DiscoverPreviewThumbnail`).
struct DiscoverAvatar: View {
    let avatarURL: URL?
    var size: CGFloat = 40

    @State private var uiImage: UIImage?

    private var resolvedURL: URL? {
        DiscoverImageURLs.avatarPreviewURL(avatarURL)
    }

    private var cornerRadius: CGFloat { 8 }

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
        )
        .task(id: resolvedURL) {
            await loadAvatar()
        }
    }

    /// Avatars use full bitmap decode; keep them out of `DiscoverImageMemoryCache`
    /// which stores downsampled recipe thumbnails keyed by the same public URL.
    private enum AvatarImageCache {
        private static let cache: NSCache<NSURL, UIImage> = {
            let cache = NSCache<NSURL, UIImage>()
            cache.countLimit = 64
            return cache
        }()

        static func image(for url: URL) -> UIImage? {
            cache.object(forKey: url as NSURL)
        }

        static func store(_ image: UIImage, for url: URL) {
            cache.setObject(image, forKey: url as NSURL)
        }
    }

    private var placeholder: some View {
        AppSymbol.sizedImage("person.fill", pointSize: max(size * 0.55, 16))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )
    }

    /// Square server preview (`preview=true`) + full bitmap + `scaledToFill`,
    /// matching web feed `Avatar` (`object-cover` on the 96×96 preview asset).
    private func loadAvatar() async {
        guard let resolvedURL else {
            uiImage = nil
            return
        }

        if let cached = AvatarImageCache.image(for: resolvedURL) {
            uiImage = cached
            return
        }

        if let fileURL = PublicImageDiskCache.existingFileURL(for: resolvedURL),
           let image = Self.decodeFullImage(from: fileURL) {
            AvatarImageCache.store(image, for: resolvedURL)
            uiImage = image
            return
        }

        guard let fileURL = await PublicImageCacheService.shared.ensureCached(
            url: resolvedURL,
            allowNetwork: true
        ),
              let image = Self.decodeFullImage(from: fileURL) else {
            return
        }
        AvatarImageCache.store(image, for: resolvedURL)
        uiImage = image
    }

    private static func decodeFullImage(from fileURL: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }
}

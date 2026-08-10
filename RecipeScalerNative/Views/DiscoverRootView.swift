//
//  DiscoverRootView.swift
//  RecipeScalerNative
//

import RecipeScalerCore
import SwiftUI

struct DiscoverRootView: View {
    @Binding var path: NavigationPath
    @Environment(\.apiClient) private var apiClient
    @State private var model: DiscoverRootModel?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let model {
                    DiscoverRootContent(model: model)
                } else {
                    ProgressView()
                        .mobileTimerPanelBottomPadding()
                }
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
            }
        }
    }

    /// Vertical list of rows, one card per line (web parity on mobile).
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
            case .failed(let message):
                ContentUnavailableView {
                    AppEmptyState.label("discover.error", symbol: "wifi.exclamationmark")
                } description: {
                    Text(message).appBody()
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

    private var cornerRadius: CGFloat { 8 }

    var body: some View {
        ZStack {
            placeholder
            if let avatarURL {
                PublicCachedImageView(
                    url: avatarURL,
                    allowsNetworkRefresh: true,
                    maxPixelSize: RecipeImageDecoder.previewMaxPixelSize,
                    contentMode: .fill
                )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
        )
    }

    private var placeholder: some View {
        AppSymbol.sizedImage("person.fill", pointSize: max(size * 0.5, 40))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )
    }
}

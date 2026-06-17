//
//  DiscoverRootView.swift
//  RecipeScalerNative
//

import RecipeScalerCore
import SwiftUI

struct DiscoverRootView: View {
    @Binding var path: NavigationPath
    @State private var data: DiscoveryDataDTO?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading, data == nil {
                    ProgressView()
                } else if let errorMessage, data == nil {
                    ContentUnavailableView {
                        AppEmptyState.label("discover.error", symbol: "wifi.exclamationmark")
                    } description: {
                        Text(errorMessage).appBody()
                    }
                } else if let data, !data.collections.isEmpty || !data.profiles.isEmpty {
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
                    }
                } else {
                    ContentUnavailableView {
                        AppEmptyState.label("discover.empty", symbol: "sparkles")
                    } description: {
                        Text("discover.empty-description").appBody()
                    }
                }
            }
            .localizedNavigationTitle("discover.title")
            .navigationDestination(for: DiscoverRoute.self) { route in
                switch route {
                case .collection(let slug):
                    DiscoverCollectionView(slug: slug)
                case .recipe(let id, let allowDownloads, let imageSource):
                    DiscoverRecipeView(
                        recipeId: id,
                        allowRecipeDownloads: allowDownloads,
                        imageSource: imageSource
                    )
                case .profile(let username):
                    DiscoverPublicProfileView(username: username)
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .accessibilityIdentifier(AccessibilityIdentifiers.discoverRoot)
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

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            data = try await DiscoverAPI.fetchDiscovery()
            errorMessage = nil
        } catch {
            errorMessage = UserFacingAPIError.message(for: error)
        }
    }
}

enum DiscoverRoute: Hashable {
    case collection(String)
    case recipe(
        id: String,
        allowDownloads: Bool = true,
        imageSource: DiscoverRecipeImageSource = .curatedDiscover
    )
    case profile(String)
}

/// Curated collection preview card (web `CollectionCard` + cover on the right).
struct DiscoverCollectionCard: View {
    let collection: DiscoveryCollectionDTO

    private var coverURL: URL? {
        DiscoverAPI.collectionCoverURL(from: collection.coverImageURL)
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
                url: DiscoverAPI.avatarURL(username: profile.username),
                fallbackColor: .accentColor,
                placeholderSymbol: "person.fill"
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
        AppSymbol.image(placeholderSymbol)
            .font(.system(size: 28, weight: .regular))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(fallbackColor.opacity(0.12))
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

/// Circular avatar for a public profile / collection author.
struct DiscoverAvatar: View {
    let avatarURL: URL?
    var size: CGFloat = 40

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
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5))
    }

    private var placeholder: some View {
        AppSymbol.image("person.fill")
            .font(.system(size: size * 0.5, weight: .regular))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Circle().fill(Color(.tertiarySystemFill)))
    }
}

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

    @State private var response: PublicProfileResponseDTO?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var searchStore = DiscoverSearchStore<PublicRecipePreviewDTO>()
    @State private var searchTokens: [String] = []

    var body: some View {
        Group {
            if let response {
                content(for: response)
            } else if isLoading {
                ProgressView(Bundle.currentLocalizedString("discover.loading"))
            } else if let errorMessage {
                ContentUnavailableView {
                    AppLabel.make("discover.profile.not-found", symbol: "person.crop.circle.badge.exclamationmark")
                } description: {
                    Text(errorMessage).appBody()
                }
            } else {
                ContentUnavailableView {
                    AppLabel.make("discover.profile.not-found", symbol: "person.crop.circle.badge.exclamationmark")
                } description: {
                    Text("discover.profile.not-found-description").appBody()
                }
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: Text("search.recipes")
        )
        .task { await load() }
        .onChange(of: searchText) { _, query in
            searchTokens = DiscoverSearch.tokenize(query)
            searchStore.setQuery(query)
        }
    }

    @ViewBuilder
    private func content(for response: PublicProfileResponseDTO) -> some View {
        let filtered = searchStore.filteredSnapshot
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
                        NavigationLink(value: DiscoverRoute.recipe(recipe.id)) {
                            DiscoverRecipeCard(recipe: recipe, searchTokens: searchTokens)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(AccessibilityIdentifiers.discoverRecipeCard)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    @ViewBuilder
    private func header(for profile: PublicProfileDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                DiscoverAvatar(
                    avatarURL: DiscoverAPI.avatarURL(fromPublicProfile: profile.avatarUrl),
                    size: 56
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
            }
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.discoverProfileHeader)
    }

    private func recipeCountText(count: Int) -> String {
        Bundle.appPluralizedString(key: "discover.profile.recipe-count", count: count)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await DiscoverAPI.fetchPublicProfile(username: username)
            response = loaded
            searchStore.setItems(DiscoverSearch.sortedByRecipeName(loaded.recipes) { $0.name })
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
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

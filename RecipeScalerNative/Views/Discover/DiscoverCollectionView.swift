//
//  DiscoverCollectionView.swift
//  RecipeScalerNative
//

import SwiftUI

/// Detail screen for a curated collection: title, description, author badge,
/// tokenized search, adaptive grid of recipe preview cards.
struct DiscoverCollectionView: View {
    let slug: String
    @State private var collection: CollectionWithRecipesDTO?
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var searchStore = DiscoverSearchStore<CuratedRecipeMetadataDTO>()
    @State private var searchTokens: [String] = []

    var body: some View {
        Group {
            if let collection {
                content(for: collection)
            } else if let errorMessage {
                ContentUnavailableView {
                    AppEmptyState.label("discover.collection.not-found", symbol: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage).appBody()
                }
                .mobileTimerPanelBottomPadding()
            } else {
                ProgressView(Bundle.currentLocalizedString("discover.collection.loading"))
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
    private func content(for collection: CollectionWithRecipesDTO) -> some View {
        let filtered = searchStore.filteredSnapshot
        if collection.recipes.isEmpty {
            ContentUnavailableView {
                AppEmptyState.label("discover.collection.empty", symbol: "tray")
            } description: {
                Text("discover.collection.empty").appBody()
            }
            .mobileTimerPanelBottomPadding()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerBlock(collection)
                    if filtered.isEmpty {
                        Text("recipes.no-recipes")
                            .appBody()
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    } else {
                        DiscoverRecipeCardGrid(items: filtered) { recipe in
                            NavigationLink(value: DiscoverRoute.recipe(id: recipe.id)) {
                                DiscoverRecipeCard(recipe: recipe, searchTokens: searchTokens)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(AccessibilityIdentifiers.discoverRecipeCard)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .mobileTimerPanelBottomPadding()
            }
        }
    }

    @ViewBuilder
    private func headerBlock(_ collection: CollectionWithRecipesDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(collection.title)
                    .font(AppTypography.display(22))
                    .foregroundStyle(.primary)
                if let author = collection.authorName, !author.isEmpty {
                    let template = Bundle.currentLocalizedString("discover.collection.by-author")
                    let label = String(
                        format: template,
                        locale: AppLanguagePreference.current.locale,
                        author
                    )
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
            }
            if let description = collection.description, !description.isEmpty {
                Text(description)
                    .appBody()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func load() async {
        do {
            let loaded = try await DiscoverAPI.fetchCollection(slug: slug)
            collection = loaded
            searchStore.setItems(DiscoverSearch.sortedByRecipeName(loaded.recipes) { $0.name })
            errorMessage = nil
        } catch {
            errorMessage = UserFacingAPIError.message(for: error)
        }
    }
}

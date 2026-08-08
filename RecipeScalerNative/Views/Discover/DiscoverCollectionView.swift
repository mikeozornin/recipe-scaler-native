//
//  DiscoverCollectionView.swift
//  RecipeScalerNative
//

import SwiftUI

/// Detail screen for a curated collection: title, description, author badge,
/// tokenized search, adaptive grid of recipe preview cards.
struct DiscoverCollectionView: View {
    let slug: String
    @Environment(\.apiClient) private var apiClient
    @Environment(\.discoverListState) private var discoverListState
    @State private var model: DiscoverCollectionModel?
    @State private var searchText = ""
    @State private var searchStore = DiscoverSearchStore<CuratedRecipeMetadataDTO>()
    @State private var searchTokens: [String] = []

    private var scope: DiscoverListScope {
        .collection(slug)
    }

    var body: some View {
        Group {
            switch model?.state {
            case .idle, .loading, .none:
                ProgressView(Bundle.currentLocalizedString("discover.collection.loading"))
            case .failed(let errorMessage):
                ContentUnavailableView {
                    AppEmptyState.label("discover.collection.not-found", symbol: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage).appBody()
                }
                .mobileTimerPanelBottomPadding()
            case .loaded(let collection):
                content(for: collection)
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: Text("search.recipes")
        )
        .task(id: slug) {
            if model == nil {
                model = DiscoverCollectionModel(api: apiClient)
            }
            if let discoverListState {
                let saved = discoverListState.state(for: scope)
                if searchText != saved.searchText {
                    searchText = saved.searchText
                }
            }
            await model?.loadIfNeeded(slug: slug)
            if case .loaded(let collection) = model?.state {
                searchStore.setItems(DiscoverSearch.sortedByRecipeName(collection.recipes) { $0.name })
            }
        }
        .refreshable {
            await model?.refresh(slug: slug)
            if case .loaded(let collection) = model?.state {
                searchStore.setItems(DiscoverSearch.sortedByRecipeName(collection.recipes) { $0.name })
            }
        }
        .onChange(of: searchText) { _, query in
            searchTokens = DiscoverSearch.tokenize(query)
            searchStore.setQuery(query)
            discoverListState?.updateSearchText(query, for: scope)
        }
    }

    @ViewBuilder
    private func content(for collection: CollectionWithRecipesDTO) -> some View {
        let filtered = searchStore.filteredSnapshot
        let filteredIDs = filtered.map(\.id)
        if collection.recipes.isEmpty {
            ContentUnavailableView {
                AppEmptyState.label("discover.collection.empty", symbol: "tray")
            } description: {
                Text("discover.collection.empty").appBody()
            }
            .mobileTimerPanelBottomPadding()
        } else {
            ScrollViewReader { proxy in
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
                                NavigationLink(
                                    value: DiscoverRoute.recipe(
                                        id: recipe.id,
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
                        hasRecipes: !collection.recipes.isEmpty,
                        proxy: proxy
                    )
                }
                .onChange(of: filteredIDs) { _, _ in
                    restoreAnchorIfNeeded(
                        filtered: filtered,
                        hasRecipes: !collection.recipes.isEmpty,
                        proxy: proxy
                    )
                }
            }
        }
    }

    private func restoreAnchorIfNeeded(
        filtered: [CuratedRecipeMetadataDTO],
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
}

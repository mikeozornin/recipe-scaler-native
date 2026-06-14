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

    var body: some View {
        Group {
            if let collection {
                content(for: collection)
            } else if let errorMessage {
                ContentUnavailableView {
                    AppLabel.make("discover.collection.not-found", symbol: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage).appBody()
                }
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
    }

    @ViewBuilder
    private func content(for collection: CollectionWithRecipesDTO) -> some View {
        let filtered = collection.recipes.filtered(by: searchText)
        if collection.recipes.isEmpty {
            ContentUnavailableView {
                AppLabel.make("discover.collection.empty", symbol: "tray")
            } description: {
                Text("discover.collection.empty").appBody()
            }
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
                            NavigationLink(value: DiscoverRoute.recipe(recipe.id)) {
                                DiscoverRecipeCard(recipe: recipe)
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
            collection = try await DiscoverAPI.fetchCollection(slug: slug)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

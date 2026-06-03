//
//  DiscoverRootView.swift
//  RecipeScalerNative
//

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
                        AppLabel.make("Discover", symbol: "wifi.exclamationmark")
                    } description: {
                        Text(errorMessage)
                    }
                } else if let data {
                    List {
                        Section {
                            ForEach(data.collections) { collection in
                                NavigationLink(value: DiscoverRoute.collection(collection.slug)) {
                                    VStack(alignment: .leading) {
                                        Text(collection.title)
                                        if let desc = collection.description {
                                            Text(desc).font(AppTypography.footnote).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        } header: {
                            AppSectionHeader("Collections")
                        }
                        Section {
                            ForEach(data.profiles) { profile in
                                NavigationLink(value: DiscoverRoute.profile(profile.username)) {
                                    HStack {
                                        Text(profile.name ?? profile.username)
                                        Spacer()
                                        Text("\(profile.recipe_count)")
                                            .font(AppTypography.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        } header: {
                            AppSectionHeader("Public profiles")
                        }
                    }
                }
            }
            .appListBodyTypography()
            .navigationTitle("Discover")
            .navigationDestination(for: DiscoverRoute.self) { route in
                switch route {
                case .collection(let slug):
                    DiscoverCollectionView(slug: slug)
                case .recipe(let id):
                    DiscoverRecipeView(recipeId: id)
                case .profile:
                    Text("Public profile (read-only) — open on web for full parity")
                        .padding()
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .accessibilityIdentifier(AccessibilityIdentifiers.discoverRoot)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            data = try await DiscoverAPI.fetchDiscovery()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum DiscoverRoute: Hashable {
    case collection(String)
    case recipe(String)
    case profile(String)
}

struct DiscoverCollectionView: View {
    let slug: String
    @State private var collection: CollectionWithRecipesDTO?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let collection {
                List(collection.recipes) { recipe in
                    NavigationLink(value: DiscoverRoute.recipe(recipe.id)) {
                        Text(recipe.name)
                    }
                }
                .navigationTitle(collection.title)
            } else if let errorMessage {
                ContentUnavailableView {
                    AppLabel.make("Error", symbol: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                }
            } else {
                ProgressView()
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            collection = try await DiscoverAPI.fetchCollection(slug: slug)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct DiscoverRecipeView: View {
    let recipeId: String
    @EnvironmentObject private var syncService: YjsSyncService
    @State private var recipe: CuratedRecipeDTO?
    @State private var isCloning = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            if let recipe {
                VStack(alignment: .leading, spacing: 12) {
                    Text(recipe.name).font(AppTypography.title2)
                    if let description = recipe.description {
                        Text(description)
                    }
                    ForEach(recipe.ingredients.indices, id: \.self) { i in
                        let ing = recipe.ingredients[i]
                        Text("• \(ing.name)")
                    }
                    Button {
                        Task { await clone() }
                    } label: {
                        if isCloning {
                            ProgressView()
                        } else {
                            Text("Copy to my recipes")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    if let message {
                        Text(message).font(AppTypography.footnote)
                    }
                }
                .padding()
            } else {
                ProgressView()
            }
        }
        .navigationTitle(recipe?.name ?? "Recipe")
        .task { await load() }
    }

    private func load() async {
        recipe = try? await DiscoverAPI.fetchRecipe(id: recipeId)
    }

    private func clone() async {
        isCloning = true
        defer { isCloning = false }
        do {
            let newId = try await DiscoverAPI.cloneRecipe(id: recipeId)
            message = "Copied — open My Recipes"
            await syncService.loadRecipe(recipeId: newId)
        } catch {
            message = error.localizedDescription
        }
    }
}
//
//  RecipeListViewModel.swift
//  RecipeScalerNative
//
//

import Foundation
import SwiftUI
import SwiftData

@MainActor
class RecipeListViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var errorMessage: String?

    private let apiClient = APIClient.shared
    private let listCacheKey = "recipes-list"

    func loadRecipes(modelContext: ModelContext) async {
        let hasCachedRecipes = (try? modelContext.fetchCount(FetchDescriptor<Recipe>())) ?? 0 > 0
        // Block only when we have no cache (first load); otherwise show cache and sync in background
        if !hasCachedRecipes {
            guard !isLoading else { return }
        }
        isLoading = !hasCachedRecipes
        isSyncing = true
        defer {
            isLoading = false
            isSyncing = false
        }

        do {
            let cacheEntry = fetchCacheEntry(key: listCacheKey, in: modelContext)
            if let cachedAt = cacheEntry?.lastFetchedAt {
                lastSyncDate = cachedAt
            }

            let response = try await apiClient.fetchRecipesCached(
                etag: cacheEntry?.etag,
                lastModified: cacheEntry?.lastModified
            )

            if response.statusCode == 304 {
                try await MainActor.run {
                    let entry: ApiCacheEntry
                    if let existing = cacheEntry {
                        entry = existing
                    } else {
                        entry = ApiCacheEntry(key: listCacheKey)
                        modelContext.insert(entry)
                    }
                    entry.lastFetchedAt = Date()
                    try modelContext.save()
                    lastSyncDate = entry.lastFetchedAt
                }
                Task {
                    let (missingDetailIds, imageIds) = await MainActor.run { () -> ([String], [String]) in
                        let descriptor = FetchDescriptor<Recipe>()
                        let recipes = (try? modelContext.fetch(descriptor)) ?? []
                        let missingDetails = recipes
                            .filter { ($0.detailHtml?.isEmpty ?? true) || $0.ingredients.isEmpty }
                            .map { $0.id }
                        let imageRecipeIds = recipes
                            .filter { ($0.imageUrl?.isEmpty == false) }
                            .map { $0.id }
                        return (missingDetails, imageRecipeIds)
                    }

                    await prefetchFullRecipesById(missingDetailIds, modelContext: modelContext)
                    await prefetchImagesById(imageIds, modelContext: modelContext)
                }
                return
            }

            guard let recipeDTOs = response.data else {
                throw APIError.serverError(message: "Missing recipes data")
            }

            try await MainActor.run {
                try self.upsertRecipes(recipeDTOs, in: modelContext)
                let entry: ApiCacheEntry
                if let existing = cacheEntry {
                    entry = existing
                } else {
                    entry = ApiCacheEntry(key: listCacheKey)
                    modelContext.insert(entry)
                }
                entry.etag = response.etag
                entry.lastModified = response.lastModified
                entry.lastFetchedAt = Date()
                try modelContext.save()
                lastSyncDate = entry.lastFetchedAt
            }

            Task {
                await prefetchPreviewImages(from: recipeDTOs, modelContext: modelContext)
                await prefetchFullRecipes(from: recipeDTOs, modelContext: modelContext)
            }

        } catch {
            // When we have cached data, avoid blocking error alert so user keeps seeing the list
            if !hasCachedRecipes {
                errorMessage = error.localizedDescription
            }
            print("Error fetching recipes: \(error)")
        }
    }

    private func upsertRecipes(_ recipes: [RecipeDTO], in modelContext: ModelContext) throws {
        let fetchDescriptor = FetchDescriptor<Recipe>()
        let existingRecipes = try modelContext.fetch(fetchDescriptor)
        var existingById = Dictionary(uniqueKeysWithValues: existingRecipes.map { ($0.id, $0) })

        for dto in recipes {
            let recipe = existingById[dto.id] ?? Recipe(id: dto.id, name: dto.name)
            recipe.name = dto.name
            recipe.recipeDescription = dto.description
            recipe.originalRecipeLink = dto.originalRecipeLink
            recipe.color = dto.color
            recipe.scaleFactor = dto.scaleFactor ?? 1.0
            recipe.originalRecipe = dto.originalRecipe
            if let imageUrl = dto.imageUrl, !imageUrl.isEmpty {
                if recipe.imageUrl != imageUrl {
                    recipe.imageLocalPath = nil
                    recipe.imagePreviewLocalPath = nil
                    recipe.imageEtag = nil
                    recipe.imagePreviewEtag = nil
                    recipe.imageLastModified = nil
                    recipe.imagePreviewLastModified = nil
                }
                recipe.imageUrl = imageUrl
            } else {
                recipe.imageUrl = nil
                recipe.imageLocalPath = nil
                recipe.imagePreviewLocalPath = nil
                recipe.imageEtag = nil
                recipe.imagePreviewEtag = nil
                recipe.imageLastModified = nil
                recipe.imagePreviewLastModified = nil
            }
            recipe.userId = dto.userId
            recipe.isPublic = dto.isPublic ?? false
            recipe.createdAt = Self.parseDate(dto.createdAt) ?? recipe.createdAt
            recipe.updatedAt = Self.parseDate(dto.updatedAt) ?? recipe.updatedAt

            if existingById[dto.id] == nil {
                modelContext.insert(recipe)
            }
        }

        try modelContext.save()
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    func searchRecipes(query: String, modelContext: ModelContext) async {
        guard !query.isEmpty else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let results = try await apiClient.searchRecipes(query: query)
            try await MainActor.run {
                try self.upsertRecipes(results, in: modelContext)
            }
        } catch {
            errorMessage = error.localizedDescription
            print("Error searching recipes: \(error)")
        }
    }

    private func fetchCacheEntry(key: String, in modelContext: ModelContext) -> ApiCacheEntry? {
        let descriptor = FetchDescriptor<ApiCacheEntry>(
            predicate: #Predicate { $0.key == key }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func prefetchPreviewImages(from recipes: [RecipeDTO], modelContext: ModelContext) async {
        await withTaskGroup(of: Void.self) { group in
            for dto in recipes {
                guard let imageUrl = dto.imageUrl, !imageUrl.isEmpty else { continue }
                let recipeId = dto.id
                group.addTask {
                    await self.cachePreviewImage(recipeId: recipeId, modelContext: modelContext)
                    await self.cacheFullImage(recipeId: recipeId, modelContext: modelContext)
                }
            }
        }
    }

    private func prefetchImagesById(_ recipeIds: [String], modelContext: ModelContext) async {
        await withTaskGroup(of: Void.self) { group in
            for recipeId in recipeIds {
                group.addTask {
                    await self.cachePreviewImage(recipeId: recipeId, modelContext: modelContext)
                    await self.cacheFullImage(recipeId: recipeId, modelContext: modelContext)
                }
            }
        }
    }

    private func prefetchFullRecipes(from recipes: [RecipeDTO], modelContext: ModelContext) async {
        await withTaskGroup(of: Void.self) { group in
            for dto in recipes {
                let recipeId = dto.id
                group.addTask {
                    await self.cacheFullRecipe(recipeId: recipeId, modelContext: modelContext)
                }
            }
        }
    }

    private func prefetchFullRecipesById(_ recipeIds: [String], modelContext: ModelContext) async {
        await withTaskGroup(of: Void.self) { group in
            for recipeId in recipeIds {
                group.addTask {
                    await self.cacheFullRecipe(recipeId: recipeId, modelContext: modelContext)
                }
            }
        }
    }

    private func cachePreviewImage(recipeId: String, modelContext: ModelContext) async {
        guard let remoteURL = apiClient.recipeImageURL(id: recipeId, preview: true) else { return }

        let metadata = await MainActor.run { () -> (etag: String?, lastModified: String?)? in
            let recipe = try? modelContext.fetch(
                FetchDescriptor<Recipe>(predicate: #Predicate { $0.id == recipeId })
            ).first
            return recipe.map { ($0.imagePreviewEtag, $0.imagePreviewLastModified) }
        }

        do {
            let result = try await ImageCacheService.shared.fetchAndCache(
                recipeId: recipeId,
                variant: .preview,
                remoteURL: remoteURL,
                etag: metadata?.etag,
                lastModified: metadata?.lastModified
            )

            try await MainActor.run {
                if let recipe = try? modelContext.fetch(
                    FetchDescriptor<Recipe>(predicate: #Predicate { $0.id == recipeId })
                ).first {
                    recipe.imagePreviewLocalPath = result.localURL.path
                    recipe.imagePreviewEtag = result.etag
                    recipe.imagePreviewLastModified = result.lastModified
                    try modelContext.save()
                }
            }
        } catch {
            // Ignore preview cache errors to avoid blocking list rendering
        }
    }

    private func cacheFullImage(recipeId: String, modelContext: ModelContext) async {
        guard let remoteURL = apiClient.recipeImageURL(id: recipeId, preview: false) else { return }

        let metadata = await MainActor.run { () -> (etag: String?, lastModified: String?)? in
            let recipe = try? modelContext.fetch(
                FetchDescriptor<Recipe>(predicate: #Predicate { $0.id == recipeId })
            ).first
            return recipe.map { ($0.imageEtag, $0.imageLastModified) }
        }

        do {
            let result = try await ImageCacheService.shared.fetchAndCache(
                recipeId: recipeId,
                variant: .full,
                remoteURL: remoteURL,
                etag: metadata?.etag,
                lastModified: metadata?.lastModified
            )

            try await MainActor.run {
                if let recipe = try? modelContext.fetch(
                    FetchDescriptor<Recipe>(predicate: #Predicate { $0.id == recipeId })
                ).first {
                    recipe.imageLocalPath = result.localURL.path
                    recipe.imageEtag = result.etag
                    recipe.imageLastModified = result.lastModified
                    try modelContext.save()
                }
            }
        } catch {
            // Ignore full image cache errors to avoid blocking list rendering
        }
    }

    private func cacheFullRecipe(recipeId: String, modelContext: ModelContext) async {
        let metadata = await MainActor.run { () -> (etag: String?, lastModified: String?, scaleFactor: Double)? in
            let recipe = try? modelContext.fetch(
                FetchDescriptor<Recipe>(predicate: #Predicate { $0.id == recipeId })
            ).first
            guard let recipe else { return nil }
            return (recipe.detailEtag, recipe.detailLastModified, recipe.scaleFactor)
        }

        do {
            let response = try await apiClient.fetchRecipeFullCached(
                id: recipeId,
                scaleFactor: metadata?.scaleFactor ?? 1.0,
                etag: metadata?.etag,
                lastModified: metadata?.lastModified
            )

            if response.statusCode == 304 {
                return
            }

            guard let fullRecipe = response.data else {
                return
            }

            try await MainActor.run {
                if let recipe = try? modelContext.fetch(
                    FetchDescriptor<Recipe>(predicate: #Predicate { $0.id == recipeId })
                ).first {
                    recipe.name = fullRecipe.name
                    recipe.detailHtml = fullRecipe.text
                    recipe.detailScaleFactor = metadata?.scaleFactor ?? 1.0
                    recipe.detailEtag = response.etag
                    recipe.detailLastModified = response.lastModified
                    recipe.detailFetchedAt = Date()
                    recipe.imageUrl = fullRecipe.imageUrl
                    recipe.originalRecipeLink = fullRecipe.originalRecipeLink

                    for existing in recipe.ingredients {
                        modelContext.delete(existing)
                    }
                    let newIngredients = fullRecipe.ingredients.enumerated().map { index, dto in
                        Ingredient(
                            id: dto.id,
                            name: dto.name,
                            originalAmount: dto.originalAmount,
                            unit: dto.unit,
                            order: index,
                            isSeparator: dto.isSeparator ?? false
                        )
                    }
                    recipe.ingredients = newIngredients
                    try modelContext.save()
                }
            }
        } catch {
            // Ignore full recipe cache errors to avoid blocking list rendering
        }
    }
}

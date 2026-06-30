//
//  DiscoverRecipeModel.swift
//  RecipeScalerNative
//

import Foundation
import RecipeScalerCore

/// Loads a public recipe state and handles copy-to-my-recipes for Discover.
@MainActor
@Observable
final class DiscoverRecipeModel {
    enum CloneState: Equatable {
        case idle
        case copying
        case done(newRecipeId: String)
        case failed(String)
    }

    private(set) var state: LoadState<RecipeData> = .idle
    private(set) var cloneState: CloneState = .idle

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func detailImageURL(recipeId: String, imageSource: DiscoverRecipeImageSource) -> URL? {
        DiscoverAPI.detailImageURL(recipeId: recipeId, imageSource: imageSource)
    }

    func load(recipeId: String) async {
        state = .loading
        do {
            let parsed = try await Self.parseRecipe(id: recipeId)
            state = .loaded(parsed)
        } catch {
            state = .failed(UserFacingAPIError.message(for: error))
        }
    }

    func clone(recipeId: String, fallbackImageUrl: String?, syncService: YjsSyncService) async {
        cloneState = .copying
        do {
            let newId = try await DiscoverAPI.copyRecipe(id: recipeId)
            await syncService.integrateCopiedRecipe(
                recipeId: newId,
                fallbackImageUrl: fallbackImageUrl
            )
            cloneState = .done(newRecipeId: newId)
            ShoppingFeedback.postStatus(
                Bundle.currentLocalizedString("discover.recipe.copied")
            )
        } catch {
            cloneState = .failed(UserFacingAPIError.message(for: error))
        }
    }

    private static func parseRecipe(id recipeId: String) async throws -> RecipeData {
        let state = try await DiscoverAPI.fetchPublicRecipeState(id: recipeId)
        if let bytes = state.yjsState, !bytes.isEmpty {
            let data = YjsPayloadBytes.data(from: bytes) ?? Data(bytes.map { UInt8(truncatingIfNeeded: $0) })
            if var parsed = await RecipeReader.parse(state: data, recipeId: recipeId) {
                if (parsed.imageUrl ?? "").isEmpty,
                   let imageUrl = state.imageUrl,
                   !imageUrl.isEmpty {
                    parsed = RecipeData(
                        id: parsed.id,
                        name: parsed.name,
                        servings: parsed.servings,
                        color: parsed.color,
                        version: parsed.version,
                        description: parsed.description,
                        ingredients: parsed.ingredients,
                        nutrition: parsed.nutrition,
                        isPublic: parsed.isPublic,
                        hasSteps: parsed.hasSteps,
                        createdAt: parsed.createdAt,
                        updatedAt: parsed.updatedAt,
                        imageUrl: imageUrl,
                        imageAspectRatio: parsed.imageAspectRatio,
                        originalRecipeLink: parsed.originalRecipeLink,
                        originalRecipe: parsed.originalRecipe
                    )
                }
                return parsed
            }
        }
        return RecipeData(
            id: state.id,
            name: state.name ?? "",
            servings: 0,
            color: state.color ?? "#3b82f6",
            version: "v1",
            description: nil,
            ingredients: [],
            nutrition: nil,
            isPublic: false,
            hasSteps: false,
            createdAt: "",
            updatedAt: "",
            imageUrl: state.imageUrl,
            imageAspectRatio: nil,
            originalRecipeLink: nil,
            originalRecipe: nil
        )
    }
}

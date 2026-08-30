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

    /// Author's public-profile `allowRecipeDownloads` (web `public-recipe.tsx`
    /// fetches the profile and gates the copy CTA on `!== false`). `nil` until
    /// the profile fetch resolves — the recipe renders immediately, the flag
    /// arrives a moment later. Errors are swallowed (web parity: stay default-on).
    private(set) var authorAllowsDownloads: Bool?

    private let api: APIClient
    private let fetchAuthorProfile: (String) async throws -> Bool?

    init(
        api: APIClient,
        fetchAuthorProfile: ((String) async throws -> Bool?)? = nil
    ) {
        self.api = api
        self.fetchAuthorProfile = fetchAuthorProfile ?? { username in
            let response = try await DiscoverAPI.fetchPublicProfile(username: username, api: api)
            return response.profile.allowRecipeDownloads != false
        }
    }

    func detailImageURL(recipeId: String, imageSource: DiscoverRecipeImageSource) -> URL? {
        DiscoverAPI.detailImageURL(recipeId: recipeId, imageSource: imageSource)
    }

    func load(recipeId: String, fetchAuthorProfile: Bool = false) async {
        state = .loading
        do {
            let stateDTO = try await DiscoverAPI.fetchPublicRecipeState(id: recipeId)
            let parsed = await Self.parseRecipe(state: stateDTO, recipeId: recipeId)
            state = .loaded(parsed)
            if fetchAuthorProfile {
                await updateAuthorDownloads(username: stateDTO.username)
            }
        } catch {
            state = .failed(UserFacingAPIError.message(for: error))
        }
    }

    /// Resolves the author's download permission from the public profile.
    /// Testable seam: injectable fetch, nil/empty username → no request.
    func updateAuthorDownloads(username: String?) async {
        guard let username, !username.isEmpty else { return }
        authorAllowsDownloads = try? await fetchAuthorProfile(username)
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

    private static func parseRecipe(state: PublicRecipeStateDTO, recipeId: String) async -> RecipeData {
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

//
//  DiscoverCollectionModel.swift
//  RecipeScalerNative
//

import Foundation
import RecipeScalerCore

/// Loads a curated collection and its recipe list by slug.
@MainActor
@Observable
final class DiscoverCollectionModel {
    private(set) var state: LoadState<CollectionWithRecipesDTO> = .idle

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func load(slug: String) async {
        state = .loading
        do {
            let collection = try await DiscoverAPI.fetchCollection(slug: slug)
            state = .loaded(collection)
        } catch {
            state = .failed(UserFacingAPIError.message(for: error))
        }
    }
}

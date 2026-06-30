//
//  DiscoverPublicProfileModel.swift
//  RecipeScalerNative
//

import Foundation
import RecipeScalerCore

/// Loads a public profile and its recipe previews by username.
@MainActor
@Observable
final class DiscoverPublicProfileModel {
    private(set) var state: LoadState<PublicProfileResponseDTO> = .idle

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func load(username: String) async {
        state = .loading
        do {
            let response = try await DiscoverAPI.fetchPublicProfile(username: username)
            state = .loaded(response)
        } catch {
            state = .failed(UserFacingAPIError.message(for: error))
        }
    }
}

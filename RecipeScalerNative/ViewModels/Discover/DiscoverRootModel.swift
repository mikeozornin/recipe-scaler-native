//
//  DiscoverRootModel.swift
//  RecipeScalerNative
//

import Foundation
import RecipeScalerCore

/// Loads curated collections and featured chef profiles for the Discover tab root.
@MainActor
@Observable
final class DiscoverRootModel {
    private(set) var state: LoadState<DiscoveryDataDTO> = .idle

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func load() async {
        let isRefresh: Bool
        if case .loaded = state {
            isRefresh = true
        } else {
            isRefresh = false
            state = .loading
        }
        do {
            let data = try await DiscoverAPI.fetchDiscovery()
            state = .loaded(data)
        } catch {
            if isRefresh, case .loaded = state {
                return
            }
            state = .failed(UserFacingAPIError.message(for: error))
        }
    }
}

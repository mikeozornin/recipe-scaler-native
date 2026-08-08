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
    private(set) var isRefreshing = false

    typealias FetchProfile = @Sendable (String) async throws -> PublicProfileResponseDTO

    private let fetchProfile: FetchProfile
    private var loadedUsername: String?
    private var requestGeneration: UInt64 = 0

    init(api: APIClient, fetchProfile: FetchProfile? = nil) {
        self.fetchProfile = fetchProfile ?? { [api] username in
            try await DiscoverAPI.fetchPublicProfile(username: username, api: api)
        }
    }

    /// Loads the profile only when this model does not already contain it.
    func loadIfNeeded(username: String) async {
        if loadedUsername == username, case .loaded = state {
            return
        }

        let previousValue = loadedValue(for: username)
        let generation = beginRequest(
            key: username,
            preservesLoadedValue: previousValue != nil
        )
        defer { finishRequest(generation) }

        do {
            let response = try await fetchProfile(username)
            try Task.checkCancellation()
            guard isCurrent(generation) else { return }
            state = .loaded(response)
            loadedUsername = username
            isRefreshing = false
        } catch {
            guard isCurrent(generation) else { return }
            if isCancellation(error) {
                if let previousValue {
                    state = .loaded(previousValue)
                } else {
                    state = .idle
                }
            } else if let previousValue {
                state = .loaded(previousValue)
            } else {
                state = .failed(UserFacingAPIError.message(for: error))
            }
            isRefreshing = false
        }
    }

    /// Refreshes the profile while keeping the existing grid on screen.
    func refresh(username: String) async {
        let previousValue = loadedValue(for: username)
        let generation = beginRequest(
            key: username,
            preservesLoadedValue: previousValue != nil
        )
        defer { finishRequest(generation) }

        do {
            let response = try await fetchProfile(username)
            try Task.checkCancellation()
            guard isCurrent(generation) else { return }
            state = .loaded(response)
            loadedUsername = username
            isRefreshing = false
        } catch {
            guard isCurrent(generation) else { return }
            if let previousValue {
                state = .loaded(previousValue)
            } else if isCancellation(error) {
                state = .idle
            } else {
                state = .failed(UserFacingAPIError.message(for: error))
            }
            isRefreshing = false
        }
    }

    private func loadedValue(for username: String) -> PublicProfileResponseDTO? {
        guard loadedUsername == username, case .loaded(let response) = state else {
            return nil
        }
        return response
    }

    private func beginRequest(key: String, preservesLoadedValue: Bool) -> UInt64 {
        requestGeneration &+= 1
        let generation = requestGeneration
        if !preservesLoadedValue {
            state = .loading
        }
        isRefreshing = preservesLoadedValue
        loadedUsername = preservesLoadedValue ? key : nil
        return generation
    }

    private func isCurrent(_ generation: UInt64) -> Bool {
        requestGeneration == generation
    }

    private func finishRequest(_ generation: UInt64) {
        guard isCurrent(generation) else { return }
        isRefreshing = false
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError || Task.isCancelled {
            return true
        }
        return (error as? URLError)?.code == .cancelled
    }
}

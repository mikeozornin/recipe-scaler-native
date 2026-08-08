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
    private(set) var isRefreshing = false

    typealias FetchCollection = @Sendable (String) async throws -> CollectionWithRecipesDTO

    private let fetchCollection: FetchCollection
    private var loadedSlug: String?
    private var requestGeneration: UInt64 = 0

    init(api: APIClient, fetchCollection: FetchCollection? = nil) {
        self.fetchCollection = fetchCollection ?? { [api] slug in
            try await DiscoverAPI.fetchCollection(slug: slug, api: api)
        }
    }

    /// Loads the collection only when this model does not already contain it.
    ///
    /// Navigation can make a destination task run again after returning from a
    /// pushed recipe. Keeping this operation idempotent prevents a loaded grid
    /// from being replaced by the initial loading state.
    func loadIfNeeded(slug: String) async {
        if loadedSlug == slug, case .loaded = state {
            return
        }

        let previousValue = loadedValue(for: slug)
        let generation = beginRequest(
            key: slug,
            preservesLoadedValue: previousValue != nil
        )
        defer { finishRequest(generation) }

        do {
            let collection = try await fetchCollection(slug)
            try Task.checkCancellation()
            guard isCurrent(generation) else { return }
            state = .loaded(collection)
            loadedSlug = slug
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

    /// Refreshes the collection while keeping the existing grid on screen.
    func refresh(slug: String) async {
        let previousValue = loadedValue(for: slug)
        let generation = beginRequest(
            key: slug,
            preservesLoadedValue: previousValue != nil
        )
        defer { finishRequest(generation) }

        do {
            let collection = try await fetchCollection(slug)
            try Task.checkCancellation()
            guard isCurrent(generation) else { return }
            state = .loaded(collection)
            loadedSlug = slug
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

    private func loadedValue(for slug: String) -> CollectionWithRecipesDTO? {
        guard loadedSlug == slug, case .loaded(let collection) = state else {
            return nil
        }
        return collection
    }

    private func beginRequest(key: String, preservesLoadedValue: Bool) -> UInt64 {
        requestGeneration &+= 1
        let generation = requestGeneration
        if !preservesLoadedValue {
            state = .loading
        }
        isRefreshing = preservesLoadedValue
        loadedSlug = preservesLoadedValue ? key : nil
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

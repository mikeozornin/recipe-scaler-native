//
//  DiscoverListStateStore.swift
//  RecipeScalerNative
//

import Foundation

/// Identifies a Discover list whose transient navigation state can be restored.
enum DiscoverListScope: Hashable, Sendable {
    case collection(String)
    case profile(String)
}

/// Transient state for one Discover collection or public profile list.
struct DiscoverListState: Sendable {
    var searchText = ""
    var anchorRecipeID: String?
}

/// Keeps Discover list context outside pushed destinations and root view churn.
@MainActor
@Observable
final class DiscoverListStateStore {
    private(set) var states: [DiscoverListScope: DiscoverListState] = [:]

    func state(for scope: DiscoverListScope) -> DiscoverListState {
        states[scope] ?? DiscoverListState()
    }

    func updateSearchText(_ searchText: String, for scope: DiscoverListScope) {
        var state = state(for: scope)
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard state.searchText != trimmedSearchText else { return }
        state.searchText = trimmedSearchText
        state.anchorRecipeID = nil
        states[scope] = state
    }

    func recordAnchor(recipeID: String, for scope: DiscoverListScope) {
        var state = state(for: scope)
        state.anchorRecipeID = recipeID
        states[scope] = state
    }

    func anchor(for scope: DiscoverListScope) -> String? {
        states[scope]?.anchorRecipeID
    }

    func consumeAnchor(for scope: DiscoverListScope) -> String? {
        guard var state = states[scope], let anchorRecipeID = state.anchorRecipeID else {
            return nil
        }
        state.anchorRecipeID = nil
        states[scope] = state
        return anchorRecipeID
    }

    func clearAnchor(for scope: DiscoverListScope) {
        guard var state = states[scope] else { return }
        state.anchorRecipeID = nil
        states[scope] = state
    }

    func clear(scope: DiscoverListScope) {
        states.removeValue(forKey: scope)
    }

    func clearAll() {
        states.removeAll()
    }
}

//
//  ShoppingViewModel.swift
//  RecipeScalerNative
//

import SwiftUI

/// Pre-computed shopping list buckets so `ShoppingListView.body` never
/// filters or sorts `snapshot.items` on each re-render.
///
/// Sources of invalidation (mirrors the previous computed properties):
/// - `ShoppingListSnapshot` (items + meta.sortMode) — published by `YjsSyncService`
/// - `purchasePhases` — local-to-view animation state
///
/// `recompute(...)` does a single pass to split items into to-buy / purchased
/// buckets, then sorts each. `ShoppingListView` only reads `sortedToBuy` /
/// `sortedPurchased`.
@MainActor
@Observable
final class ShoppingViewModel {
    private(set) var sortedToBuy: [ShoppingListItem] = []
    private(set) var sortedPurchased: [ShoppingListItem] = []

    func recompute(snapshot: ShoppingListSnapshot, purchasePhases: [String: ToBuyPurchasePhase]) {
        var toBuy: [ShoppingListItem] = []
        var purchased: [ShoppingListItem] = []
        toBuy.reserveCapacity(snapshot.items.count)
        purchased.reserveCapacity(snapshot.items.count)

        for item in snapshot.items {
            if item.purchased {
                if purchasePhases[item.id] != nil {
                    toBuy.append(item)
                } else {
                    purchased.append(item)
                }
            } else {
                toBuy.append(item)
            }
        }

        self.sortedToBuy = sort(toBuy, mode: snapshot.meta.sortMode)
        self.sortedPurchased = sort(purchased, mode: snapshot.meta.sortMode)
    }

    private func sort(_ items: [ShoppingListItem], mode: ShoppingSortMode) -> [ShoppingListItem] {
        switch mode {
        case .recipe:
            return items.sorted { lhs, rhs in
                let ln = lhs.recipeName.isEmpty ? "~" : lhs.recipeName
                let rn = rhs.recipeName.isEmpty ? "~" : rhs.recipeName
                if ln != rn { return ln.localizedCompare(rn) == .orderedAscending }
                return lhs.label.localizedCompare(rhs.label) == .orderedAscending
            }
        case .alphabet:
            return items.sorted {
                ShoppingListFromRecipe.sortName(for: $0.label)
                    .localizedCompare(ShoppingListFromRecipe.sortName(for: $1.label)) == .orderedAscending
            }
        }
    }
}

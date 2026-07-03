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
    /// Rows shown immediately on Return; dropped when the same manual label appears in Y.Doc snapshot.
    private(set) var pendingManualToBuy: [ShoppingListItem] = []

    func appendPendingManual(label: String) -> ShoppingListItem {
        let item = ShoppingListItem(
            id: "pending-\(UUID().uuidString)",
            label: label,
            createdAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
        pendingManualToBuy.append(item)
        return item
    }

    func removePendingManual(id: String) {
        pendingManualToBuy.removeAll { $0.id == id }
    }

    func recompute(snapshot: ShoppingListSnapshot, purchasePhases: [String: ToBuyPurchasePhase]) {
        prunePendingManual(against: snapshot.items)

        var toBuy: [ShoppingListItem] = []
        var purchased: [ShoppingListItem] = []
        toBuy.reserveCapacity(snapshot.items.count + pendingManualToBuy.count)
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

        for pending in pendingManualToBuy where !toBuy.contains(where: { $0.id == pending.id }) {
            toBuy.append(pending)
        }

        self.sortedToBuy = sort(toBuy, mode: snapshot.meta.sortMode)
        self.sortedPurchased = sort(purchased, mode: snapshot.meta.sortMode)
    }

    private func prunePendingManual(against snapshotItems: [ShoppingListItem]) {
        var manualLabelCounts: [String: Int] = [:]
        for item in snapshotItems where item.recipeId == nil && item.ingredientId == nil && !item.purchased {
            manualLabelCounts[item.label, default: 0] += 1
        }
        var slots = manualLabelCounts
        pendingManualToBuy.removeAll { pending in
            let available = slots[pending.label, default: 0]
            guard available > 0 else { return false }
            slots[pending.label] = available - 1
            return true
        }
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

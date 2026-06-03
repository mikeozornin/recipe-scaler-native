//
//  ShoppingListView.swift
//  RecipeScalerNative
//

import SwiftUI

struct ShoppingListView: View {
    @EnvironmentObject private var syncService: YjsSyncService
    @Binding var path: NavigationPath
    @State private var newItemText = ""
    private var snapshot: ShoppingListSnapshot {
        syncService.shoppingSnapshot
    }

    private var toBuy: [ShoppingListItem] {
        sorted(snapshot.items.filter { !$0.purchased })
    }

    private var purchased: [ShoppingListItem] {
        sorted(snapshot.items.filter(\.purchased))
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                AppSegmentedControl(
                    segments: [
                        .init(value: ShoppingSortMode.recipe, title: String(localized: "shopping.sort.by-recipe")),
                        .init(value: ShoppingSortMode.alphabet, title: String(localized: "shopping.sort.az")),
                    ],
                    selection: sortBinding
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .accessibilityLabel(String(localized: "shopping.sort"))

                if !toBuy.isEmpty {
                    Section {
                        ForEach(toBuy) { item in
                            shoppingRow(item)
                        }
                        .onDelete(perform: deleteToBuy)
                    } header: {
                        AppSectionHeader(String(localized: "shopping.section.to-buy"))
                    }
                }

                if !purchased.isEmpty {
                    Section {
                        ForEach(purchased) { item in
                            shoppingRow(item)
                        }
                        .onDelete(perform: deletePurchased)
                    } header: {
                        AppSectionHeader(String(localized: "shopping.section.purchased"))
                    }
                }

                Section {
                    HStack {
                        TextField(String(localized: "shopping.add.placeholder"), text: $newItemText)
                        Button(String(localized: "shopping.add")) { addManual() }
                            .disabled(newItemText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle(String(localized: "discover.nav.shopping"))
            .appListBodyTypography()
            .accessibilityIdentifier(AccessibilityIdentifiers.shoppingList)
        }
    }

    private var sortBinding: Binding<ShoppingSortMode> {
        Binding(
            get: { snapshot.meta.sortMode },
            set: { mode in
                Task { try? await syncService.setShoppingSortMode(mode) }
            }
        )
    }

    @ViewBuilder
    private func shoppingRow(_ item: ShoppingListItem) -> some View {
        HStack {
            Button {
                Task {
                    try? await syncService.setShoppingItemPurchased(id: item.id, purchased: !item.purchased)
                }
            } label: {
                AppSymbol.image( item.purchased ? "checkmark.circle.fill" : "circle")
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .strikethrough(item.purchased)
                if !item.recipeName.isEmpty {
                    Text(item.recipeName)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func sorted(_ items: [ShoppingListItem]) -> [ShoppingListItem] {
        switch snapshot.meta.sortMode {
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

    private func addManual() {
        let text = newItemText
        newItemText = ""
        Task { try? await syncService.addManualShoppingItem(label: text) }
    }

    private func deleteToBuy(at offsets: IndexSet) {
        delete(items: toBuy, at: offsets)
    }

    private func deletePurchased(at offsets: IndexSet) {
        delete(items: purchased, at: offsets)
    }

    private func delete(items: [ShoppingListItem], at offsets: IndexSet) {
        for index in offsets {
            let id = items[index].id
            Task { try? await syncService.removeShoppingItem(id: id) }
        }
    }
}
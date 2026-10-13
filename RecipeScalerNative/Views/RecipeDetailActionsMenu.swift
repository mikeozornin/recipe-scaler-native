//
//  RecipeDetailActionsMenu.swift
//  RecipeScalerNative
//

import SwiftUI

struct RecipeDetailActionsMenu: View {
    let recipeId: String
    let recipeName: String
    let ingredients: [IngredientData]
    let isEditing: Bool
    let isPinned: Bool
    /// Injected (not `@Environment`): this view renders inside a `ToolbarItem`,
    /// and iOS 26 measures toolbar content in a fallback environment without
    /// injected observables (crash: `EnvironmentValues.subscript.getter` trap
    /// after dismissing the assistant sheet — fallback env has no `YjsSyncService`).
    let syncService: YjsSyncService
    /// Spec 081 (T037): «В коллекцию» opens a popover from «…» on `.padRegular`, the sheet
    /// on the phone. Passed in: the bar item may get a fallback environment (`.phone`).
    var layoutMode: AppLayoutMode = .phone

    /// The delete confirmation and «В коллекцию» of this menu, owned by the recipe view so
    /// the iPad menu bar (⌘⌫, «В коллекцию…», spec 081 US6) opens the same ones.
    @Binding var recipePendingDelete: Bool
    @Binding var showingAssignSheet: Bool

    var body: some View {
        Menu {
            if !isEditing {
                Button {
                    showingAssignSheet = true
                } label: {
                    AppLabel.make("collections.assign-tooltip", symbol: "folder.badge.plus")
                }

                Button {
                    Task {
                        await RecipeDetailMenuActions.togglePin(
                            recipeId: recipeId,
                            isPinned: isPinned,
                            syncService: syncService
                        )
                    }
                } label: {
                    AppLabel.make(
                        isPinned ? "recipe.list.unpin" : "recipe.list.pin",
                        symbol: isPinned ? "pin.slash" : "pin"
                    )
                }

                Button {
                    Task {
                        await RecipeDetailMenuActions.addAllToShopping(
                            recipeId: recipeId,
                            recipeName: recipeName,
                            ingredients: ingredients,
                            syncService: syncService
                        )
                    }
                } label: {
                    AppLabel.make("shopping.detail-add-all", symbol: "cart.badge.plus")
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.recipeDetailMenuAddAllToShopping)

                Button(role: .destructive) {
                    recipePendingDelete = true
                } label: {
                    AppLabel.make("recipe.list.delete", symbol: "trash")
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.recipeDetailMenuDelete)
            }
        } label: {
            AppToolbarStyle.iconOnly(systemName: "ellipsis")
        }
        .appToolbarIconButton()
        .accessibilityLabel("recipe.detail.more-actions")
        .accessibilityIdentifier(AccessibilityIdentifiers.recipeDetailMenu)
        .adaptivePopover(isPresented: $showingAssignSheet) {
            // A tap outside closes the popover; the selection is saved on close, as when
            // the phone sheet closes (`CollectionAssignSheet.onDisappear`).
            CollectionAssignSheet(
                recipeId: recipeId,
                recipeName: recipeName,
                syncService: syncService
            )
            .iPadPopoverFrame(
                width: IPadLayoutMetrics.collectionsPopoverWidth,
                height: IPadLayoutMetrics.collectionsPopoverHeight
            )
        }
        .environment(\.appLayoutMode, layoutMode)
        .alert(
            Bundle.currentLocalizedString("recipe.list.delete.confirm.title"),
            isPresented: $recipePendingDelete
        ) {
            Button(Bundle.currentLocalizedString("recipe.list.delete.confirm.action"), role: .destructive) {
                Task { await RecipeDetailMenuActions.delete(recipeId: recipeId, syncService: syncService) }
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.recipeDetailDeleteConfirm)
            Button(Bundle.currentLocalizedString("recipe.list.delete.confirm.cancel"), role: .cancel) { }
        } message: {
            Text(
                String(
                    format: Bundle.currentLocalizedString("recipe.list.delete.confirm.message"),
                    locale: .current,
                    recipeName
                )
            )
        }
    }
}

/// The actions of the recipe «…» menu, shared with the iPad menu bar (spec 081, US6).
@MainActor
enum RecipeDetailMenuActions {
    static func addAllToShopping(
        recipeId: String,
        recipeName: String,
        ingredients: [IngredientData],
        syncService: YjsSyncService
    ) async {
        let items = ShoppingListFromRecipe.makeItems(
            recipeId: recipeId,
            recipeName: recipeName,
            ingredients: ingredients,
            ingredientIds: nil
        )
        guard !items.isEmpty else {
            ShoppingFeedback.postStatus(Bundle.currentLocalizedString("shopping.no-items-to-add"))
            return
        }
        do {
            try await syncService.addRecipeToShoppingList(
                recipeId: recipeId,
                recipeName: recipeName,
                ingredients: ingredients,
                selectedIngredientIds: nil
            )
            ShoppingFeedback.postStatus(ShoppingAddFeedback.message(for: items.count))
        } catch {
            ShoppingFeedback.postStatus(UserFacingAPIError.message(for: error))
        }
    }

    static func togglePin(recipeId: String, isPinned: Bool, syncService: YjsSyncService) async {
        do {
            try await syncService.setRecipePinned(recipeId: recipeId, isPinned: !isPinned)
        } catch {
            ShoppingFeedback.postStatus(UserFacingAPIError.message(for: error))
        }
    }

    static func delete(recipeId: String, syncService: YjsSyncService) async {
        do {
            try await syncService.deleteRecipeFromCollection(recipeId: recipeId)
        } catch {
            ShoppingFeedback.postStatus(UserFacingAPIError.message(for: error))
        }
    }
}

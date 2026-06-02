//
//  RecipeDetailActionsMenu.swift
//  RecipeScalerNative
//

import SwiftUI
import PhotosUI

struct RecipeDetailActionsMenu: View {
    let recipeId: String
    let recipeName: String
    let ingredients: [IngredientData]
    let isPublic: Bool
    let isEditing: Bool
    let isOnline: Bool

    @EnvironmentObject private var syncService: YjsSyncService
    @State private var photoItem: PhotosPickerItem?
    @State private var imageFromURL = ""
    @State private var statusMessage: String?

    var body: some View {
        Menu {
            Toggle(isOn: Binding(
                get: { isPublic },
                set: { value in Task { try? await syncService.updateRecipeIsPublic(value) } }
            )) {
                AppLabel.make("Public recipe", symbol: "globe")
            }

            Button {
                Task { await addAllToShopping() }
            } label: {
                AppLabel.make("Add to shopping list", symbol: "cart.badge.plus")
            }

            if isEditing {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    AppLabel.make("Upload photo", symbol: "camera")
                }
                .disabled(!isOnline)

                Button(role: .destructive) {
                    Task { await deleteImage() }
                } label: {
                    AppLabel.make("Delete photo", symbol: "trash")
                }
                .disabled(!isOnline)
            }
        } label: {
            AppSymbol.image("ellipsis")
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.recipeDetailMenu)
        .onChange(of: photoItem) { _, item in
            Task { await uploadPhoto(item) }
        }
    }

    private func addAllToShopping() async {
        do {
            try await syncService.addRecipeToShoppingList(
                recipeId: recipeId,
                recipeName: recipeName,
                ingredients: ingredients,
                selectedIngredientIds: nil
            )
            statusMessage = "Added to shopping list"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func uploadPhoto(_ item: PhotosPickerItem?) async {
        guard isOnline, let item,
              let data = try? await item.loadTransferable(type: Data.self) else { return }
        do {
            _ = try await RecipeImageUploadAPI.upload(recipeId: recipeId, imageData: data)
            await syncService.loadRecipe(recipeId: recipeId)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func deleteImage() async {
        guard isOnline else { return }
        do {
            try await RecipeImageUploadAPI.delete(recipeId: recipeId)
            await syncService.loadRecipe(recipeId: recipeId)
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
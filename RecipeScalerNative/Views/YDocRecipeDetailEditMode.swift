//
//  YDocRecipeDetailEditMode.swift
//  RecipeScalerNative
//
//  Review 2026.09.04 №20 — extracted from `YDocRecipeDetailView.swift`:
//  edit-mode toggling and the title-save pipeline.
//

import SwiftUI
import RecipeScalerCore

extension YDocRecipeDetailView {
    @ViewBuilder
    func editHeader(_ vm: RecipeEditViewModel, recipe: RecipeData) -> some View {
        RecipeEditHeaderBindable(
            viewModel: vm,
            initialTitle: recipe.name,
            pickerColor: $pickerColor,
            dismissTitleKeyboard: $dismissRecipeTitleKeyboard,
            commitTitleNonce: commitTitleNonce,
            requestInitialFocus: shouldAutoFocusRecipeTitle,
            onTitleBlur: { name in
                scheduleTitleSave(name, editViewModel: vm)
            },
            onEditingActiveChanged: { active in
                vm.isEditingTitleField = active
                syncDescriptionChromeSuppression()
            }
        )
    }

    func scheduleTitleSave(_ name: String, editViewModel: RecipeEditViewModel) {
        titleSaveTask?.cancel()
        titleSaveTask = Task { @MainActor in
            await saveRecipeTitle(name, editViewModel: editViewModel)
        }
    }

    func saveRecipeTitle(_ name: String, editViewModel: RecipeEditViewModel) async {
        guard let current = syncService.currentRecipe, current.id == recipeId else { return }
        do {
            try await editViewModel.saveRecipeName(name, against: current)
            #if DEBUG
            #endif
        } catch {
            editErrorMessage = UserFacingAPIError.message(for: error)
            #if DEBUG
            #endif
        }
    }

    func awaitPendingTitleSave() async {
        for _ in 0 ..< 40 {
            if let task = titleSaveTask {
                if !task.isCancelled {
                    await task.value
                }
                break
            }
            await Task.yield()
        }
        if let task = titleSaveTask, !task.isCancelled {
            await task.value
        }
        titleSaveTask = nil
    }

    func toggleEditMode() async {
        if isEditing {
            guard !isFinishingEdit else { return }
            isFinishingEdit = true
            defer { isFinishingEdit = false }
            commitTitleNonce += 1
            dismissRecipeTitleKeyboard = true
            await Task.yield()
            await awaitPendingTitleSave()
            #if DEBUG
            #endif
            guard let editViewModel else {
                isEditing = false
                return
            }
            guard let current = syncService.currentRecipe, current.id == recipeId else {
                editViewModel.isEditingTitleField = false
                isEditing = false
                return
            }
            saveInFlight = true
            defer { saveInFlight = false }
            let servingsChanged = editViewModel.draftServings != current.servings
            do {
                try await editViewModel.finishEditing(against: current)
                editViewModel.isEditingTitleField = false
                isEditing = false
                if servingsChanged {
                    // Base servings are persisted in Y.Doc; local scale is UI-only (web parity).
                    scaleFactor = 1
                    RecipeScaleStorage.saveScaleFactor(recipeId: recipeId, scaleFactor: 1)
                }
                if let updated = syncService.currentRecipe {
                    editViewModel.reset(from: updated)
                    pickerColor = RecipeAccentColor.color(from: updated.color)
                }
                #if DEBUG
                #endif
            } catch {
                editErrorMessage = UserFacingAPIError.message(for: error)
                #if DEBUG
                #endif
            }
        } else {
            if let recipe {
                let vm = RecipeEditViewModel(recipe: recipe, syncService: syncService)
                editViewModel = vm
                pickerColor = RecipeAccentColor.color(from: vm.draftColor)
            }
            isEditing = true
            editViewModel?.isEditingTitleField = false
        }
    }
}

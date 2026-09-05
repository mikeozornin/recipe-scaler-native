//
//  YDocRecipeDetailBlocks.swift
//  RecipeScalerNative
//
//  Review 2026.09.04 №20 — extracted from `YDocRecipeDetailView.swift`:
//  nutrition/servings blocks, scale helpers, edit-start application and
//  DEBUG screenshot/verify hooks.
//

import SwiftUI
import RecipeScalerCore

extension YDocRecipeDetailView {
    func nutritionBlock(recipe: RecipeData) -> some View {
        let outdated = recipe.nutrition?.nutritionOutdated == true
        return RecipeNutritionBlockView(
            recipe: recipe,
            baseServings: max(1, recipe.servings),
            scaleFactor: scaleFactor,
            accentColor: accentColor,
            isOnline: syncService.connectionState.isConnected,
            onRecalculate: outdated ? { [weak nutritionRecalculation] in
                guard let model = nutritionRecalculation else { return }
                await model.recalculate(recipeId: recipeId, syncService: syncService)
            } : nil,
            viewMode: $nutritionViewMode
        )
    }

    func deactivateScreenAwake() {
        if isScreenAwakeActive {
            isScreenAwakeActive = false
        }
        ScreenAwakeController.deactivate()
    }

    func applyStartInEditModeIfNeeded() {
        #if DEBUG
        let wantsEdit = startInEditMode
            || DebugLaunchOptions.startInEditMode
            || DebugLaunchOptions.startDescriptionEdit
        #else
        let wantsEdit = startInEditMode
        #endif
        guard wantsEdit,
              !didApplyStartInEditMode,
              canEnterEditMode,
              let recipe else { return }
        didApplyStartInEditMode = true
        shouldAutoFocusRecipeTitle = startInEditMode
        let vm = RecipeEditViewModel(recipe: recipe, syncService: syncService)
        editViewModel = vm
        pickerColor = RecipeAccentColor.color(from: vm.draftColor)
        isEditing = true
    }

    func applyStartDescriptionEditIfNeeded() {
        #if DEBUG
        let wantsEditor = startDescriptionEdit || DebugLaunchOptions.startDescriptionEdit
        #else
        let wantsEditor = startDescriptionEdit
        #endif
        guard wantsEditor,
              !didApplyStartDescriptionEdit,
              canEnterEditMode,
              isEditing,
              recipe != nil,
              descriptionChrome.isEditorReady,
              let bridge = descriptionChrome.bridge else { return }
        didApplyStartDescriptionEdit = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            #if DEBUG
            let command: String
            if DebugLaunchOptions.startDescriptionEdit {
                switch DebugLaunchOptions.descriptionEditorFocus {
                case "mid":
                    command = "focusMid"
                case "start":
                    command = "focus"
                default:
                    command = "focusEnd"
                }
            } else {
                command = "focus"
            }
            #else
            let command = "focus"
            #endif
            bridge.sendCommand(name: command)
        }
    }

    #if DEBUG
    func scheduleScreenshotNutritionScrollIfNeeded(
        scrollProxy: ScrollViewProxy,
        loading: Bool
    ) {
        guard !didScheduleNutritionScreenshot,
              !loading,
              recipe != nil,
              DebugLaunchOptions.screenshotScrollToNutrition else { return }
        didScheduleNutritionScreenshot = true
        AppLog.info(.app, "screenshot_nutrition_scroll_scheduled", data: ["recipeId": recipeId])
        let readyRecipeId = recipeId
        let readyImageUrl = headerImageUrl
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.3)) {
                scrollProxy.scrollTo("recipe_nutrition", anchor: .top)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                scrollProxy.scrollTo("recipe_nutrition", anchor: .top)
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 800_000_000)
                await DebugLaunchOptions.signalScreenshotRecipeMediaReadyIfNeeded(
                    recipeId: readyRecipeId,
                    imageUrl: readyImageUrl
                )
            }
        }
    }

    /// Retries edit + editor sheet until recipe is loaded (verify scripts).
    func scheduleDebugDescriptionEditorIfNeeded() {
        guard DebugLaunchOptions.startDescriptionEdit || startDescriptionEdit else { return }
        guard !didApplyStartDescriptionEdit else { return }
        Task { @MainActor in
            for _ in 0 ..< 40 {
                if didApplyStartDescriptionEdit { return }
                applyStartInEditModeIfNeeded()
                applyStartDescriptionEditIfNeeded()
                if didApplyStartDescriptionEdit { return }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
    #endif

    @ViewBuilder
    func servingsBlock(recipe: RecipeData) -> some View {
        ServingsStepperView(
            servings: scaledServingsBinding(base: max(1, recipe.servings)),
            accentColor: accentColor
        )
    }

    func scaledServingsCount(base: Int) -> Int {
        let normalizedBase = max(1, base)
        return max(1, Int((Double(normalizedBase) * scaleFactor).rounded()))
    }

    /// View-mode scaled qty edit recalculates UI scale (web `useRecipeScale.handleAmountChange`).
    func applyViewModeScaledQuantityEdit(ingredient: IngredientData, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let scaled = Double(normalized), scaled > 0, scaled.isFinite else { return }
        guard let original = ingredient.numericValue, original > 0 else { return }
        scaleFactor = scaled / original
        RecipeScaleStorage.saveScaleFactor(recipeId: recipeId, scaleFactor: scaleFactor)
    }

    func scaledServingsBinding(base: Int) -> Binding<Int> {
        Binding(
            get: { scaledServingsCount(base: base) },
            set: { newValue in
                let normalizedBase = max(1, base)
                scaleFactor = max(1.0 / Double(normalizedBase), Double(max(1, newValue)) / Double(normalizedBase))
                RecipeScaleStorage.saveScaleFactor(recipeId: recipeId, scaleFactor: scaleFactor)
            }
        )
    }
}

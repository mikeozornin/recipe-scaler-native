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
        // iPad: an edit of this recipe outlives the view it started in (T043).
        if adoptIPadEditSessionIfNeeded() { return }
        #if DEBUG
        let wantsEdit = startInEditMode
            || DebugLaunchOptions.startInEditMode
            || DebugLaunchOptions.startDescriptionEdit
        #else
        let wantsEdit = startInEditMode
        #endif
        guard wantsEdit,
              !didApplyStartInEditMode,
              !iPadStartInEditAlreadyApplied,
              canEnterEditMode,
              let recipe else { return }
        didApplyStartInEditMode = true
        noteIPadStartInEditApplied()
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
    /// Part of the 09 store shot's task id: the capture turns the iPad after launch, and the
    /// two-column layout needs its own scroll.
    var screenshotNutritionLayoutKey: String {
        "\(showsTwoColumns ? 2 : 1)-\(Int(padPanel?.detailWidth ?? 0))"
    }

    /// Scrolls the 09 store shot to the nutrition block, then tells the capture script.
    /// Runs again whenever the layout changes; a newer run cancels the older one.
    func runScreenshotNutritionScroll(scrollProxy: ScrollViewProxy, loading: Bool) async {
        guard !loading,
              recipe != nil,
              DebugLaunchOptions.screenshotScrollToNutrition else { return }
        // Two columns: the block at the bottom of the left column keeps the ingredient rows
        // with their nutrition lines in frame above it.
        let anchor: UnitPoint = showsTwoColumns ? .bottom : .top
        AppLog.info(.app, "screenshot_nutrition_scroll_scheduled", data: [
            "recipeId": recipeId,
            "twoColumns": showsTwoColumns ? "1" : "0",
        ])
        do {
            try await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation(.easeOut(duration: 0.3)) {
                scrollProxy.scrollTo("recipe_nutrition", anchor: anchor)
            }
            try await Task.sleep(nanoseconds: 350_000_000)
            scrollProxy.scrollTo("recipe_nutrition", anchor: anchor)
            try await Task.sleep(nanoseconds: 450_000_000)
        } catch {
            return
        }
        await DebugLaunchOptions.signalScreenshotRecipeMediaReadyIfNeeded(
            recipeId: recipeId,
            imageUrl: headerImageUrl
        )
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
        let base = max(1, recipe.servings)
        ServingsStepperView(
            currentServings: RecipeServings.currentServings(base: base, scaleFactor: scaleFactor),
            accentColor: accentColor,
            onDecrement: { stepServings(base: base, delta: -1) },
            onIncrement: { stepServings(base: base, delta: 1) }
        )
    }

    /// Continuous servings for labels (web `getCurrentServings`).
    func currentServingsValue(base: Int) -> Double {
        RecipeServings.currentServings(base: base, scaleFactor: scaleFactor)
    }

    /// Integer snap only where a whole-serving index is still required.
    func scaledServingsCount(base: Int) -> Int {
        RecipeServings.scaledServings(base: base, scaleFactor: scaleFactor)
    }

    func stepServings(base: Int, delta: Int) {
        let normalizedBase = max(1, base)
        let next = RecipeServings.steppedServings(base: normalizedBase, scaleFactor: scaleFactor, delta: delta)
        scaleFactor = max(1.0 / Double(normalizedBase), Double(next) / Double(normalizedBase))
        RecipeScaleStorage.saveScaleFactor(recipeId: recipeId, scaleFactor: scaleFactor)
    }

    /// View-mode scaled qty edit recalculates UI scale (web `useRecipeScale.handleAmountChange`).
    /// Keeps fractional scale (e.g. 40→60 ⇒ 1.5); does not round through integer servings.
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

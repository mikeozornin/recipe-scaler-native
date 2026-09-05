//
//  YDocRecipeDetailDescriptionEditing.swift
//  RecipeScalerNative
//
//  Review 2026.09.04 №20 — extracted from `YDocRecipeDetailView.swift`:
//  description-editor interactions (timer start, markup flows, LLM parse,
//  node-click menus, span unlinks/renames).
//

import SwiftUI
import RecipeScalerCore

extension YDocRecipeDetailView {
    func startDescriptionTimer(from reference: RecipeDescriptionTimerReference) {
        guard reference.isStartable else { return }
        let displayName = recipe?.name
            ?? syncService.collectionEntries.first(where: { $0.id == recipeId })?.name
        _ = timerManager.createAndStartTimer(
            name: reference.resolvedName,
            duration: TimeInterval(reference.durationSeconds),
            type: reference.type,
            recipeId: recipeId,
            recipeDisplayName: displayName
        )
    }

    func beginDescriptionTimerMarkup() {
        guard let bridge = descriptionChrome.bridge else { return }
        let selectedText = bridge.selectionState.selectedText
        guard let value = DescriptionMarkupFlow.parseTimerValue(from: selectedText) else { return }
        descriptionTimerMarkupDraft = DescriptionTimerMarkupDraft(
            selectedText: selectedText,
            value: value
        )
        syncDescriptionChromeSuppression()
    }

    func applyDescriptionTimerMarkup(draft: DescriptionTimerMarkupDraft, unit: DescriptionTimerUnit) {
        guard let bridge = descriptionChrome.bridge else { return }
        let duration = unit.durationSeconds(for: draft.value)
        let timerId = "timer-\(Int(Date().timeIntervalSince1970 * 1000))"
        bridge.sendCommand(
            name: "markAsTimer",
            args: [
                "type": unit.rawValue,
                "value": draft.value,
                "duration": duration,
                "timerId": timerId,
            ]
        )
        descriptionTimerMarkupDraft = nil
        finishDescriptionMarkupSheet()
    }

    func beginDescriptionIngredientMarkup() {
        guard let bridge = descriptionChrome.bridge else { return }
        let selectedText = bridge.selectionState.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedText.isEmpty else { return }
        descriptionMarkupSelectedText = selectedText
        descriptionIngredientPickerPresented = true
        syncDescriptionChromeSuppression()
    }

    func applyDescriptionIngredientMarkup(ingredient: IngredientData, ratio: Double) {
        guard let bridge = descriptionChrome.bridge else { return }
        let args: [String: Any] = [
            "ingredientId": ingredient.id,
            "originalAmount": ingredient.originalAmount,
            "ratio": ratio,
        ]
        bridge.sendCommand(name: "markAsIngredient", args: args)
        descriptionIngredientPickerPresented = false
        finishDescriptionMarkupSheet()
    }

    func finishDescriptionMarkupSheet() {
        descriptionChrome.bridge?.sendCommand(name: "releaseMarkupSelection")
        syncDescriptionChromeSuppression()
    }

    /// Sparkles button: call LLM `/parse` with current editor HTML; server applies result and
    /// emits recipe_updated + collection_updated + document_loaded over sync (019 US7).
    @MainActor
    func runDescriptionLLMParse(bridge: DescriptionEditorBridge) async {
        guard !isParsingDescription else { return }
        guard let recipeId = recipe?.id, !recipeId.isEmpty else { return }
        isParsingDescription = true
        descriptionParseError = nil
        defer { isParsingDescription = false }

        // Flush any pending local edits so the server parses the freshest content.
        await bridge.flushEditorEdits()

        let html = await bridge.requestHTML()
        do {
            try await RecipeLLMParseAPI.parseAndApply(recipeId: recipeId, stepsHtml: html, language: AppLanguagePreference.current.rawValue)
            // Sync delivers recipe_updated / collection_updated / document_loaded.
        } catch {
            descriptionParseError = UserFacingAPIError.message(for: error)
        }
    }

    func syncDescriptionChromeSuppression() {
        let suppress = descriptionTimerMarkupDraft != nil
            || descriptionIngredientPickerPresented
            || descriptionTimerNodeMenu != nil
            || descriptionIngredientNodeMenu != nil
            || ingredientFieldsFocused
            || (editViewModel?.isEditingTitleField ?? false)
        descriptionChrome.setSuppressFormattingBar(suppress)

        let shouldBlurEditor = ingredientFieldsFocused
            || (editViewModel?.isEditingTitleField ?? false)
            || descriptionTimerNodeMenu != nil
            || descriptionIngredientNodeMenu != nil
        if shouldBlurEditor {
            descriptionChrome.blurEditor()
        }
    }

    func handleDescriptionNodeClick(_ click: DescriptionNodeClick) {
        descriptionChrome.blurEditor()
        syncDescriptionChromeSuppression()

        let presentationId = descriptionChrome.bridge?.nodeClickSequence ?? 0

        switch click.nodeType {
        case .timer:
            let durationSeconds = DescriptionMarkupFlow.parseDurationSeconds(click.duration)
            let timerType = RecipeTimer.TimerType(rawValue: click.timerType) ?? .minutes
            let displayText = click.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? click.value.trimmingCharacters(in: .whitespacesAndNewlines)
                : click.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard durationSeconds > 0,
                  !click.timerType.isEmpty,
                  !displayText.isEmpty else { return }
            let reference = RecipeDescriptionTimerReference(
                displayText: displayText,
                durationSeconds: durationSeconds,
                type: timerType,
                name: click.name.isEmpty ? nil : click.name
            )
            presentDescriptionTimerNodeMenu(
                DescriptionTimerNodeMenuState(
                    presentationId: presentationId,
                    click: click,
                    reference: reference
                )
            )
        case .ingredient:
            let ingredientExists = recipe?.ingredients.contains(where: { $0.id == click.ingredientId }) ?? false
            if ingredientExists, let recipe,
               let ingredient = recipe.ingredients.first(where: { $0.id == click.ingredientId }) {
                presentDescriptionIngredientNodeMenu(
                    DescriptionIngredientNodeMenuState(
                        presentationId: presentationId,
                        click: click,
                        ingredient: ingredient
                    )
                )
            } else {
                presentDescriptionOrphanedIngredientNodeMenu(
                    click: click,
                    presentationId: presentationId
                )
            }
        }
    }

    func presentDescriptionTimerNodeMenu(_ menu: DescriptionTimerNodeMenuState) {
        if descriptionTimerNodeMenu != nil {
            descriptionTimerNodeMenu = nil
            DispatchQueue.main.async {
                descriptionTimerNodeMenu = menu
                syncDescriptionChromeSuppression()
            }
        } else {
            descriptionTimerNodeMenu = menu
            syncDescriptionChromeSuppression()
        }
    }

    func presentDescriptionIngredientNodeMenu(_ menu: DescriptionIngredientNodeMenuState) {
        if descriptionIngredientNodeMenu != nil {
            descriptionIngredientNodeMenu = nil
            DispatchQueue.main.async {
                descriptionIngredientNodeMenu = menu
                syncDescriptionChromeSuppression()
            }
        } else {
            descriptionIngredientNodeMenu = menu
            syncDescriptionChromeSuppression()
        }
    }

    func presentDescriptionOrphanedIngredientNodeMenu(click: DescriptionNodeClick, presentationId: UInt) {
        descriptionIngredientNodeMenu = DescriptionIngredientNodeMenuState(
            presentationId: presentationId,
            click: click,
            ingredient: IngredientData(id: click.ingredientId, name: Bundle.currentLocalizedString("ingredients.deleted"))
        )
        syncDescriptionChromeSuppression()
    }

    func timerSpanCommandArgs(_ click: DescriptionNodeClick) -> [String: Any] {
        var args: [String: Any] = [
            "duration": click.duration,
            "type": click.timerType,
            "value": click.value,
            "text": click.text.isEmpty ? click.value : click.text,
        ]
        if !click.timerId.isEmpty {
            args["timerId"] = click.timerId
        }
        return args
    }

    func unlinkDescriptionTimer(_ click: DescriptionNodeClick) {
        var args = timerSpanCommandArgs(click)
        args["text"] = click.text.isEmpty ? click.value : click.text
        descriptionChrome.bridge?.sendCommand(name: "removeTimerMarkup", args: args)
    }

    func unlinkDescriptionIngredient(_ click: DescriptionNodeClick) {
        descriptionChrome.bridge?.sendCommand(
            name: "removeIngredientMarkup",
            args: [
                "ingredientId": click.ingredientId,
                "displayText": click.text,
            ]
        )
    }

    func renameDescriptionTimer(_ click: DescriptionNodeClick, name: String) {
        var args = timerSpanCommandArgs(click)
        args["name"] = name
        descriptionChrome.bridge?.sendCommand(name: "renameTimer", args: args)
    }

    func updateDescriptionIngredientRatio(_ click: DescriptionNodeClick, ratio: Double) {
        guard let ingredient = recipe?.ingredients.first(where: { $0.id == click.ingredientId }) else { return }
        let displayText = DescriptionMarkupFlow.ingredientDisplayText(
            originalAmount: ingredient.originalAmount,
            ratio: ratio
        )
        descriptionChrome.bridge?.sendCommand(
            name: "updateIngredientMarkup",
            args: [
                "ingredientId": click.ingredientId,
                "ratio": ratio,
                "displayText": displayText,
            ]
        )
    }
}

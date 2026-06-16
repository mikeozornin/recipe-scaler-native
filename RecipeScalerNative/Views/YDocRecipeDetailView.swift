import SwiftUI
import RecipeScalerCore

/// Recipe detail backed by Y.Doc via `YjsSyncService`.
struct YDocRecipeDetailView: View {
    let recipeId: String
    var startInEditMode: Bool = false
    var startDescriptionEdit: Bool = false

    @EnvironmentObject private var syncService: YjsSyncService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// UI-only scale (web `recipe-scale:{id}` in localStorage). Not written to Y.Doc.
    @State private var scaleFactor: Double = 1
    @AppStorage(NutritionSettings.globalEnabledKey) private var showNutritionGlobal = true
    @State private var nutritionViewMode: IngredientNutritionViewMode = NutritionViewModeStorage.load()
    @State private var isLoading = false
    @State private var isEditing = false
    @State private var editViewModel: RecipeEditViewModel?
    @State private var editErrorMessage: String?
    @State private var pickerColor: Color = RecipeAccentColor.color(from: "oklch(0.65 0.25 270)")
    @State private var saveInFlight = false
    @State private var didApplyStartInEditMode = false
    @State private var shouldAutoFocusRecipeTitle = false
    @StateObject private var descriptionChrome = DescriptionEditorChromeState()
    @State private var didApplyStartDescriptionEdit = false
    @State private var dismissRecipeTitleKeyboard = false
    @State private var commitTitleNonce = 0
    @State private var titleSaveTask: Task<Void, Never>?
    @State private var isFinishingEdit = false
    @State private var isScreenAwakeActive = false
    @State private var descriptionTimerPopover: DescriptionTimerPopoverState?
    @State private var descriptionTimerMarkupDraft: DescriptionTimerMarkupDraft?
    @State private var descriptionIngredientPickerPresented = false
    @State private var descriptionMarkupSelectedText = ""
    @State private var descriptionTimerNodeMenu: DescriptionTimerNodeMenuState?
    @State private var descriptionIngredientNodeMenu: DescriptionIngredientNodeMenuState?
    @State private var ingredientFieldsFocused = false
    @State private var clearIngredientFocusToken = 0
    @State private var isParsingDescription = false
    @State private var descriptionParseError: String?


    private var recipe: RecipeData? {
        guard syncService.currentRecipe?.id == recipeId else { return nil }
        return syncService.currentRecipe
    }

    private var isLegacyReadOnly: Bool {
        guard let recipe else { return false }
        return !RecipeEditPolicy.supportsEditFormat(version: recipe.version)
    }

    private var canEnterEditMode: Bool {
        guard let recipe else { return false }
        return RecipeEditPolicy.canEdit(recipe: recipe)
    }

    private var accentColor: Color {
        if isEditing, let editViewModel {
            return RecipeAccentColor.color(from: editViewModel.draftColor)
        }
        return RecipeAccentColor.color(from: recipe?.color ?? "")
    }

    /// Image metadata from collection (instant) or merged recipe doc (after load).
    private var headerImageUrl: String? {
        if let recipeUrl = recipe?.imageUrl, !recipeUrl.isEmpty { return recipeUrl }
        if let entryUrl = syncService.collectionEntries.first(where: { $0.id == recipeId })?.imageUrl,
           !entryUrl.isEmpty {
            return entryUrl
        }
        return nil
    }

    private var showsRecipeImageSection: Bool {
        if headerImageUrl != nil { return true }
        return isEditing && canEnterEditMode
    }

    private var allowsImageNetworkRefresh: Bool {
        syncService.connectionState == .connected
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if showsRecipeImageSection {
                    RecipeDetailImageSection(
                        recipeId: recipeId,
                        imageUrl: headerImageUrl,
                        imageAspectRatio: recipe?.imageAspectRatio.map { CGFloat($0) },
                        isEditing: isEditing && canEnterEditMode,
                        allowsNetworkRefresh: allowsImageNetworkRefresh
                    )
                }

                VStack(alignment: .leading, spacing: 16) {
                    if isLoading && recipe == nil {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }

                    if isLegacyReadOnly {
                        RecipeLegacyBanner()
                    }

                    if isEditing, let editViewModel, let recipe {
                        editHeader(editViewModel, recipe: recipe)
                    } else {
                        Text(recipe?.name ?? "")
                            .font(AppTypography.display(AppTypography.recipeTitleSize))
                            .lineLimit(nil)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }

                    if let recipe {
                        if !isEditing {
                            servingsBlock(recipe: recipe)
                        }

                        if isEditing, let editViewModel {
                            YDocIngredientsEditSection(
                                recipe: recipe,
                                draftServings: Binding(
                                    get: { editViewModel.draftServings },
                                    set: { editViewModel.draftServings = max(1, min(99, $0)) }
                                ),
                                baseServings: max(1, recipe.servings),
                                viewServings: scaledServingsCount(base: max(1, editViewModel.draftServings)),
                                accentColor: accentColor,
                                nutritionEnabled: showNutritionGlobal,
                                nutritionViewMode: nutritionViewMode,
                                onCommit: { ingredient in
                                    await saveIngredient(ingredient, existing: recipe.ingredients.first { $0.id == ingredient.id })
                                },
                                onSaveNutrition: { ingredientId, calories, protein, fat, carbs in
                                    await saveIngredientNutrition(
                                        ingredientId: ingredientId,
                                        calories: calories,
                                        protein: protein,
                                        fat: fat,
                                        carbs: carbs,
                                        editViewModel: editViewModel
                                    )
                                },
                                onDelete: { id in
                                    await deleteIngredient(id: id)
                                },
                                onAdd: { name, amount in
                                    await addIngredient(name: name, amount: amount, in: recipe, editViewModel: editViewModel)
                                },
                                onReorder: { from, to in
                                    await reorderIngredients(from: from, to: to)
                                },
                                onIngredientFieldFocusChanged: { focused in
                                    ingredientFieldsFocused = focused
                                    syncDescriptionChromeSuppression()
                                },
                                onKeyboardDone: {
                                    descriptionChrome.blurEditor()
                                    dismissRecipeTitleKeyboard = true
                                },
                                clearFocusToken: clearIngredientFocusToken
                            )
                        } else {
                            YDocIngredientsSection(
                                ingredients: recipe.ingredients,
                                baseServings: max(1, recipe.servings),
                                viewServings: scaledServingsCount(base: max(1, recipe.servings)),
                                accentColor: accentColor,
                                onScaledQuantityEdited: { ingredient, text in
                                    applyViewModeScaledQuantityEdit(ingredient: ingredient, text: text)
                                },
                                onAddIngredientToShopping: isLegacyReadOnly
                                    ? nil
                                    : { ingredient in
                                        Task { await addIngredientToShopping(ingredient) }
                                    },
                                nutritionEnabled: showNutritionGlobal,
                                nutritionViewMode: nutritionViewMode
                            )
                        }

                        if !isEditing,
                           showNutritionGlobal,
                           RecipeNutritionDisplay.effectiveMacros(from: recipe) != nil {
                            nutritionBlock(recipe: recipe)
                        }

                        if isEditing, canEnterEditMode {
                            RecipeDescriptionEditorBlock(
                                recipeId: recipeId,
                                accentColor: accentColor,
                                syncService: syncService,
                                scaleFactor: scaleFactor,
                                ingredients: recipe.ingredients,
                                chrome: descriptionChrome,
                                onNodeClick: { click in
                                    handleDescriptionNodeClick(click)
                                }
                            )
                            .id("recipe_instructions")
                        } else if let description = recipe.description, !description.isEmpty {
                            StepsSection(
                                htmlContent: description,
                                accentColor: accentColor,
                                recipeId: recipeId,
                                timerPopover: $descriptionTimerPopover
                            )
                                .id("recipe_instructions")
                        }

                    }
                }
                .padding(.top, RecipeDetailLayoutMetrics.titleTopSpacing)
            }
        }
        .dismissPopoverOnVerticalDrag(isActive: descriptionTimerPopover != nil) {
            descriptionTimerPopover = nil
        }
        .contentMargins(.horizontal, 0, for: .scrollContent)
        #if DEBUG
        .onChange(of: recipe?.description) { _, description in
            guard description != nil,
                  DebugLaunchOptions.openRecipeId == recipeId,
                  !DebugLaunchOptions.startInEditMode else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeOut(duration: 0.25)) {
                    scrollProxy.scrollTo("recipe_instructions", anchor: .top)
                }
            }
        }
        .onChange(of: isEditing) { _, editing in
            guard editing, DebugLaunchOptions.scrollToNewIngredient else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeOut(duration: 0.25)) {
                    scrollProxy.scrollTo(
                        AccessibilityIdentifiers.recipeEditNewIngredientRow,
                        anchor: .bottom
                    )
                }
            }
        }
        #endif
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            if isScreenAwakeActive {
                ScreenAwakeStatusBanner()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isEditing,
               descriptionChrome.showsFormattingBar,
               let bridge = descriptionChrome.bridge {
                DescriptionFormattingBar(
                    bridge: bridge,
                    accentColor: accentColor,
                    onMarkTimer: beginDescriptionTimerMarkup,
                    onMarkIngredient: beginDescriptionIngredientMarkup,
                    onParseRecipe: {
                        Task { await runDescriptionLLMParse(bridge: bridge) }
                    }
                )
            }
        }
        .sheet(item: $descriptionTimerMarkupDraft, onDismiss: finishDescriptionMarkupSheet) { draft in
            DescriptionTimerTypeSheet(
                selectedPreview: draft.selectedText,
                parsedValue: draft.value
            ) { unit in
                applyDescriptionTimerMarkup(draft: draft, unit: unit)
            }
        }
        .sheet(isPresented: $descriptionIngredientPickerPresented, onDismiss: finishDescriptionMarkupSheet) {
            if let recipe {
                DescriptionIngredientMarkupSheet(
                    ingredients: DescriptionMarkupFlow.eligibleIngredients(
                        from: recipe.ingredients,
                        selectedText: descriptionMarkupSelectedText
                    ),
                    selectedText: descriptionMarkupSelectedText
                ) { ingredient, ratio in
                    applyDescriptionIngredientMarkup(ingredient: ingredient, ratio: ratio)
                    descriptionIngredientPickerPresented = false
                }
            }
        }
        .sheet(item: $descriptionTimerNodeMenu, onDismiss: {
            descriptionTimerNodeMenu = nil
            syncDescriptionChromeSuppression()
        }) { menu in
            DescriptionTimerNodeFlowSheet(
                menu: menu,
                onStart: {
                    startDescriptionTimer(from: menu.reference)
                    descriptionTimerNodeMenu = nil
                },
                onRenameSave: { name in
                    renameDescriptionTimer(menu.click, name: name)
                    descriptionTimerNodeMenu = nil
                },
                onUnlink: {
                    unlinkDescriptionTimer(menu.click)
                    descriptionTimerNodeMenu = nil
                }
            )
            .id(menu.id)
        }
        .sheet(item: $descriptionIngredientNodeMenu, onDismiss: {
            descriptionIngredientNodeMenu = nil
            syncDescriptionChromeSuppression()
        }) { menu in
            DescriptionIngredientNodeFlowSheet(
                menu: menu,
                onRatioSave: { ratio in
                    updateDescriptionIngredientRatio(menu.click, ratio: ratio)
                },
                onUnlink: {
                    unlinkDescriptionIngredient(menu.click)
                }
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 0) {
                    if let recipe, !isEditing {
                        RecipeDetailActionsMenu(
                            recipeId: recipeId,
                            recipeName: recipe.name,
                            ingredients: recipe.ingredients,
                            isEditing: false,
                            isPinned: syncService.collectionEntries.first { $0.id == recipeId }?.isPinned ?? false
                        )
                        RecipeDetailShareButton(
                            recipeId: recipeId,
                            isPublic: recipe.isPublic,
                            hasImage: !(recipe.imageUrl?.isEmpty ?? true),
                            hasSteps: recipe.hasSteps
                        )
                        ScreenAwakeToggle(isActive: $isScreenAwakeActive)
                        if canEnterEditMode {
                            Button {
                                Task { await toggleEditMode() }
                            } label: {
                                AppToolbarStyle.labeledIcon(
                                    systemName: "pencil",
                                    title: "edit.edit"
                                )
                            }
                            .appToolbarIconButton()
                        }
                    }
                }
            }
            if canEnterEditMode, isEditing {
                ToolbarItem(placement: .confirmationAction) {
                    Button("edit.done") {
                        Task { await toggleEditMode() }
                    }
                    .appToolbarConfirmButton()
                }
            }
        }
        .toolbar {
            if isEditing,
               canEnterEditMode,
               descriptionChrome.isFocused,
               !ingredientFieldsFocused,
               !(editViewModel?.isEditingTitleField ?? false) {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("edit.done") {
                        descriptionChrome.blurEditor()
                    }
                    .appToolbarTextButton()
                    .accessibilityIdentifier(AccessibilityIdentifiers.descriptionEditorKeyboardDone)
                }
            }
        }
        .onChange(of: descriptionChrome.isFocused) { _, focused in
            guard focused else { return }
            clearIngredientFocusToken += 1
            dismissRecipeTitleKeyboard = true
        }
        .alert(
            Bundle.currentLocalizedString("edit.error.title"),
            isPresented: Binding(
                get: { editErrorMessage != nil },
                set: { if !$0 { editErrorMessage = nil } }
            )
        ) {
            Button(Bundle.currentLocalizedString("edit.error.ok"), role: .cancel) {}
        } message: {
            Text(editErrorMessage ?? "")
        }
        .alert(
            Bundle.currentLocalizedString("llm.parse-recipe"),
            isPresented: Binding(
                get: { descriptionParseError != nil },
                set: { if !$0 { descriptionParseError = nil } }
            )
        ) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(descriptionParseError ?? "")
        }

        .onChange(of: syncService.syncErrorMessage) { _, message in
            if let message { editErrorMessage = message }
        }
        .onChange(of: syncService.activeRecipeWasRemoved) { _, removed in
            if removed {
                syncService.acknowledgeRecipeRemoved()
                dismiss()
            }
        }
        .onChange(of: syncService.connectionState) { _, newState in
            guard newState == .connected else { return }
            Task {
                await syncService.syncPendingDocumentsAfterReconnect(recipeIds: [recipeId])
            }
        }
        .background {
            if !isEditing {
                DescriptionWireExportHost(recipeId: recipeId, syncService: syncService)
            }
        }
        .onChange(of: isScreenAwakeActive) { _, active in
            ScreenAwakeController.setActive(active)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                // Real leave (home / switch app) — like web `document.hidden`.
                deactivateScreenAwake()
            case .active:
                // Control Center / notification shade is `.inactive`, not `.background`.
                if isScreenAwakeActive {
                    ScreenAwakeController.setActive(true)
                }
            default:
                break
            }
        }
        .onDisappear {
            guard !AssistantRecipeContext.shared.isAssistantSheetOpen else { return }
            AssistantRecipeContext.shared.clearVisibleRecipeId(recipeId)
            deactivateScreenAwake()
        }
        .task(id: recipeId) {
            deactivateScreenAwake()
            isLoading = true
            defer { isLoading = false }
            scaleFactor = RecipeScaleStorage.loadScaleFactor(recipeId: recipeId)
            syncService.acknowledgeRecipeRemoved()
            await syncService.loadRecipe(recipeId: recipeId)
            #if DEBUG
            #endif
        }
        .task(id: "\(recipeId)-\(headerImageUrl ?? "")-\(allowsImageNetworkRefresh)") {
            guard let imageUrl = headerImageUrl else { return }
            await RecipeImageService.shared.prefetchFull(
                recipeId: recipeId,
                imageUrl: imageUrl,
                allowNetwork: allowsImageNetworkRefresh
            )
        }
        .onChange(of: recipe?.version) { _, _ in
            if isLegacyReadOnly, isEditing {
                isEditing = false
            }
            applyStartInEditModeIfNeeded()
        }
        .onChange(of: recipe?.id) { _, _ in
            #if DEBUG
            #endif
            guard editViewModel?.isEditingTitleField != true else { return }
            if let recipe {
                let vm = RecipeEditViewModel(recipe: recipe, syncService: syncService)
                editViewModel = vm
                pickerColor = RecipeAccentColor.color(from: vm.draftColor)
            }
            applyStartInEditModeIfNeeded()
            applyStartDescriptionEditIfNeeded()
        }
        .onChange(of: isEditing) { _, editing in
            if !editing {
                descriptionChrome.reset()
            }
            applyStartDescriptionEditIfNeeded()
        }
        .onChange(of: syncService.currentRecipe?.id) { _, loadedId in
            guard loadedId == recipeId else { return }
            applyStartInEditModeIfNeeded()
            applyStartDescriptionEditIfNeeded()
        }
        .onAppear {
            AssistantRecipeContext.shared.setVisibleRecipeId(recipeId)
            applyStartInEditModeIfNeeded()
            applyStartDescriptionEditIfNeeded()
            scheduleDebugDescriptionEditorIfNeeded()
        }
        .overlay {
            DescriptionTimerPopoverOverlay(
                state: descriptionTimerPopover,
                accentColor: accentColor,
                onStart: {
                    if let popover = descriptionTimerPopover {
                        startDescriptionTimer(from: popover.reference)
                    }
                },
                onDismiss: { descriptionTimerPopover = nil }
            )
        }
    }

    private func nutritionBlock(recipe: RecipeData) -> some View {
        let outdated = recipe.nutrition?.nutritionOutdated == true
        return RecipeNutritionBlockView(
            recipe: recipe,
            baseServings: max(1, recipe.servings),
            scaleFactor: scaleFactor,
            accentColor: accentColor,
            isOnline: syncService.connectionState.isConnected,
            onRecalculate: outdated ? {
                do {
                    try await APIClient.shared.calculateNutrition(recipeId: recipeId)
                    await syncService.refreshCurrentRecipe(recipeId: recipeId)
                } catch {
                    // Banner stays until next successful recalculation
                }
            } : nil,
            viewMode: $nutritionViewMode
        )
    }

    private func deactivateScreenAwake() {
        if isScreenAwakeActive {
            isScreenAwakeActive = false
        }
        ScreenAwakeController.deactivate()
    }

    private func applyStartInEditModeIfNeeded() {
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

    private func applyStartDescriptionEditIfNeeded() {
        #if DEBUG
        let wantsEditor = startDescriptionEdit || DebugLaunchOptions.startDescriptionEdit
        #else
        let wantsEditor = startDescriptionEdit
        #endif
        guard wantsEditor,
              !didApplyStartDescriptionEdit,
              canEnterEditMode,
              isEditing,
              recipe != nil else { return }
        didApplyStartDescriptionEdit = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            descriptionChrome.bridge?.sendCommand(name: "focus")
        }
        #if DEBUG
        #endif
    }

    #if DEBUG
    /// Retries edit + editor sheet until recipe is loaded (verify scripts).
    private func scheduleDebugDescriptionEditorIfNeeded() {
        guard DebugLaunchOptions.startDescriptionEdit || startDescriptionEdit else { return }
        guard !didApplyStartDescriptionEdit else { return }
        Task { @MainActor in
            for _ in 0 ..< 24 {
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
    private func servingsBlock(recipe: RecipeData) -> some View {
        ServingsStepperView(
            servings: scaledServingsBinding(base: max(1, recipe.servings)),
            accentColor: accentColor
        )
    }

    private func startDescriptionTimer(from reference: RecipeDescriptionTimerReference) {
        guard reference.isStartable else { return }
        let displayName = recipe?.name
            ?? syncService.collectionEntries.first(where: { $0.id == recipeId })?.name
        _ = TimerManager.shared.createAndStartTimer(
            name: reference.resolvedName,
            duration: TimeInterval(reference.durationSeconds),
            type: reference.type,
            recipeId: recipeId,
            recipeDisplayName: displayName
        )
    }

    private func beginDescriptionTimerMarkup() {
        guard let bridge = descriptionChrome.bridge else { return }
        let selectedText = bridge.selectionState.selectedText
        guard let value = DescriptionMarkupFlow.parseTimerValue(from: selectedText) else { return }
        descriptionTimerMarkupDraft = DescriptionTimerMarkupDraft(
            selectedText: selectedText,
            value: value
        )
        syncDescriptionChromeSuppression()
    }

    private func applyDescriptionTimerMarkup(draft: DescriptionTimerMarkupDraft, unit: DescriptionTimerUnit) {
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

    private func beginDescriptionIngredientMarkup() {
        guard let bridge = descriptionChrome.bridge else { return }
        let selectedText = bridge.selectionState.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedText.isEmpty else { return }
        descriptionMarkupSelectedText = selectedText
        descriptionIngredientPickerPresented = true
        syncDescriptionChromeSuppression()
    }

    private func applyDescriptionIngredientMarkup(ingredient: IngredientData, ratio: Double) {
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

    private func finishDescriptionMarkupSheet() {
        descriptionChrome.bridge?.sendCommand(name: "releaseMarkupSelection")
        syncDescriptionChromeSuppression()
    }

    /// Sparkles button: call LLM `/parse` with current editor HTML; server applies result and
    /// emits recipe_updated + collection_updated + document_loaded over sync (019 US7).
    @MainActor
    private func runDescriptionLLMParse(bridge: DescriptionEditorBridge) async {
        guard !isParsingDescription else { return }
        guard let recipeId = recipe?.id, !recipeId.isEmpty else { return }
        isParsingDescription = true
        descriptionParseError = nil
        defer { isParsingDescription = false }

        // Flush any pending local edits so the server parses the freshest content.
        await bridge.flushEditorEdits()

        let html = await bridge.requestHTML()
        do {
            try await RecipeLLMParseAPI.parseAndApply(recipeId: recipeId, stepsHtml: html)
            // Sync delivers recipe_updated / collection_updated / document_loaded.
        } catch {
            descriptionParseError = error.localizedDescription
        }
    }

    private func syncDescriptionChromeSuppression() {
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

    private func handleDescriptionNodeClick(_ click: DescriptionNodeClick) {
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

    private func presentDescriptionTimerNodeMenu(_ menu: DescriptionTimerNodeMenuState) {
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

    private func presentDescriptionIngredientNodeMenu(_ menu: DescriptionIngredientNodeMenuState) {
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

    private func presentDescriptionOrphanedIngredientNodeMenu(click: DescriptionNodeClick, presentationId: UInt) {
        descriptionIngredientNodeMenu = DescriptionIngredientNodeMenuState(
            presentationId: presentationId,
            click: click,
            ingredient: IngredientData(id: click.ingredientId, name: Bundle.currentLocalizedString("ingredients.deleted"))
        )
        syncDescriptionChromeSuppression()
    }

    private func timerSpanCommandArgs(_ click: DescriptionNodeClick) -> [String: Any] {
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

    private func unlinkDescriptionTimer(_ click: DescriptionNodeClick) {
        var args = timerSpanCommandArgs(click)
        args["text"] = click.text.isEmpty ? click.value : click.text
        descriptionChrome.bridge?.sendCommand(name: "removeTimerMarkup", args: args)
    }

    private func unlinkDescriptionIngredient(_ click: DescriptionNodeClick) {
        descriptionChrome.bridge?.sendCommand(
            name: "removeIngredientMarkup",
            args: [
                "ingredientId": click.ingredientId,
                "displayText": click.text,
            ]
        )
    }

    private func renameDescriptionTimer(_ click: DescriptionNodeClick, name: String) {
        var args = timerSpanCommandArgs(click)
        args["name"] = name
        descriptionChrome.bridge?.sendCommand(name: "renameTimer", args: args)
    }

    private func updateDescriptionIngredientRatio(_ click: DescriptionNodeClick, ratio: Double) {
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

    private func scaledServingsCount(base: Int) -> Int {
        let normalizedBase = max(1, base)
        return max(1, Int((Double(normalizedBase) * scaleFactor).rounded()))
    }

    /// View-mode scaled qty edit recalculates UI scale (web `useRecipeScale.handleAmountChange`).
    private func applyViewModeScaledQuantityEdit(ingredient: IngredientData, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let scaled = Double(normalized), scaled > 0, scaled.isFinite else { return }
        guard let original = ingredient.numericValue, original > 0 else { return }
        scaleFactor = scaled / original
        RecipeScaleStorage.saveScaleFactor(recipeId: recipeId, scaleFactor: scaleFactor)
    }

    private func scaledServingsBinding(base: Int) -> Binding<Int> {
        Binding(
            get: { scaledServingsCount(base: base) },
            set: { newValue in
                let normalizedBase = max(1, base)
                scaleFactor = max(1.0 / Double(normalizedBase), Double(max(1, newValue)) / Double(normalizedBase))
                RecipeScaleStorage.saveScaleFactor(recipeId: recipeId, scaleFactor: scaleFactor)
            }
        )
    }

    @ViewBuilder
    private func editHeader(_ vm: RecipeEditViewModel, recipe: RecipeData) -> some View {
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

    private func scheduleTitleSave(_ name: String, editViewModel: RecipeEditViewModel) {
        titleSaveTask?.cancel()
        titleSaveTask = Task { @MainActor in
            await saveRecipeTitle(name, editViewModel: editViewModel)
        }
    }

    private func saveRecipeTitle(_ name: String, editViewModel: RecipeEditViewModel) async {
        guard let current = syncService.currentRecipe, current.id == recipeId else { return }
        do {
            try await editViewModel.saveRecipeName(name, against: current)
            #if DEBUG
            #endif
        } catch {
            editErrorMessage = error.localizedDescription
            #if DEBUG
            #endif
        }
    }

    private func awaitPendingTitleSave() async {
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

    private func toggleEditMode() async {
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
                editErrorMessage = error.localizedDescription
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
            #if DEBUG
            #endif
        }
    }

    private func saveIngredientNutrition(
        ingredientId: String,
        calories: Double,
        protein: Double,
        fat: Double,
        carbs: Double,
        editViewModel: RecipeEditViewModel
    ) async {
        guard !saveInFlight else { return }
        guard let base = syncService.currentRecipe?.ingredients.first(where: { $0.id == ingredientId }) else { return }
        let updated = base.withNutrition(calories: calories, protein: protein, fat: fat, carbs: carbs)
        saveInFlight = true
        defer { saveInFlight = false }
        do {
            try await editViewModel.saveIngredientNutrition(updated)
        } catch {
            editErrorMessage = error.localizedDescription
        }
    }

    private func saveIngredient(_ ingredient: IngredientData, existing: IngredientData?) async {
        guard let editViewModel, !saveInFlight else { return }
        saveInFlight = true
        defer { saveInFlight = false }
        do {
            try await editViewModel.saveIngredient(ingredient, existing: existing)
        } catch {
            editErrorMessage = error.localizedDescription
        }
    }

    private func deleteIngredient(id: String) async {
        guard let editViewModel, !saveInFlight else { return }
        saveInFlight = true
        defer { saveInFlight = false }
        do {
            try await editViewModel.deleteIngredient(id: id)
        } catch {
            editErrorMessage = error.localizedDescription
        }
    }

    private func addIngredientToShopping(_ ingredient: IngredientData) async {
        guard let recipe else { return }
        let items = ShoppingListFromRecipe.makeItems(
            recipeId: recipeId,
            recipeName: recipe.name,
            ingredients: recipe.ingredients,
            ingredientIds: [ingredient.id]
        )
        guard !items.isEmpty else {
            ShoppingFeedback.postStatus(Bundle.currentLocalizedString("shopping.no-items-to-add"))
            return
        }
        do {
            try await syncService.addRecipeToShoppingList(
                recipeId: recipeId,
                recipeName: recipe.name,
                ingredients: recipe.ingredients,
                selectedIngredientIds: [ingredient.id]
            )
            ShoppingFeedback.postStatus(ShoppingAddFeedback.message(for: items.count))
        } catch {
            ShoppingFeedback.postStatus(error.localizedDescription)
        }
    }

    private func addIngredient(name: String, amount: String, in recipe: RecipeData, editViewModel: RecipeEditViewModel) async {
        let order = editViewModel.nextIngredientOrder(in: recipe)
        let isSeparator = name.range(of: #"^[-—–−]{2,}$"#, options: .regularExpression) != nil
        let parsed = IngredientData.parsedQuantity(amount)
        let placeholder = IngredientData(id: "new", name: name)
        let ingredient = IngredientData(
            id: UUID().uuidString,
            name: name,
            amount: isSeparator ? "" : parsed.originalAmount,
            originalAmount: isSeparator ? "" : parsed.originalAmount,
            unit: isSeparator ? "" : placeholder.preservedUnit(whenParsing: parsed),
            order: order,
            isSeparator: isSeparator,
            hasQuantity: isSeparator ? false : parsed.hasQuantity
        )
        await saveIngredient(ingredient, existing: nil)
    }

    private func reorderIngredients(from: Int, to: Int) async {
        do {
            try await syncService.moveIngredient(fromIndex: from, toIndex: to)
        } catch {
            editErrorMessage = error.localizedDescription
        }
    }
}

private struct RecipeEditHeaderBindable: View {
    @Bindable var viewModel: RecipeEditViewModel
    let initialTitle: String
    @Binding var pickerColor: Color
    @Binding var dismissTitleKeyboard: Bool
    var commitTitleNonce: Int
    var requestInitialFocus: Bool = false
    var onTitleBlur: (String) -> Void
    var onEditingActiveChanged: (Bool) -> Void
    @Environment(\.locale) private var locale

    private var titleUIFont: UIFont {
        AppTypography.uiFont(AppFonts.display, size: AppTypography.recipeTitleSize)
    }

    private var titlePlaceholder: String {
        _ = locale
        return Bundle.currentLocalizedString("edit.name.placeholder")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                RecipeTitleTextField(
                    initialText: initialTitle,
                    dismissKeyboard: $dismissTitleKeyboard,
                    requestInitialFocus: requestInitialFocus,
                    commitTitleNonce: commitTitleNonce,
                    placeholder: titlePlaceholder,
                    font: titleUIFont,
                    onBlur: onTitleBlur,
                    onEditingActiveChanged: onEditingActiveChanged
                )
                    .id("recipe-title-editor")
                    .frame(maxWidth: .infinity, alignment: .leading)

                ColorPicker("", selection: $pickerColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 32, height: 32)
            }
            .padding(.horizontal)
            .onAppear {
                // Defer to the next runloop tick: writing `pickerColor` (a @State/@Binding
                // rooted in YDocRecipeDetailView) synchronously from `.onAppear` mutates
                // observed state during the SwiftUI layout pass, which triggers
                // "Publishing changes from within view updates is not allowed".
                let initial = RecipeAccentColor.color(from: viewModel.draftColor)
                DispatchQueue.main.async {
                    pickerColor = initial
                }
            }
            .onChange(of: pickerColor) { _, newColor in
                viewModel.draftColor = RecipeAccentColor.storedValue(from: newColor)
            }
        }
    }
}


private extension View {
    /// Dismisses an overlay on vertical scroll without stealing horizontal List row swipes.
    func dismissPopoverOnVerticalDrag(isActive: Bool, onDismiss: @escaping () -> Void) -> some View {
        modifier(DismissPopoverOnVerticalDragModifier(isActive: isActive, onDismiss: onDismiss))
    }
}

private struct DismissPopoverOnVerticalDragModifier: ViewModifier {
    let isActive: Bool
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    guard isActive else { return }
                    guard abs(value.translation.height) > abs(value.translation.width) else { return }
                    onDismiss()
                }
        )
    }
}


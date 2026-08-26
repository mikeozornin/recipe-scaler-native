import SwiftUI
import RecipeScalerCore
import WebKit

/// Recipe detail backed by Y.Doc via `YjsSyncService`.
struct YDocRecipeDetailView: View {
    let recipeId: String
    var startInEditMode: Bool = false
    var startDescriptionEdit: Bool = false

    @Environment(YjsSyncService.self) private var syncService
    @Environment(AssistantRecipeContext.self) private var assistantRecipeContext
    @Environment(TimerManager.self) private var timerManager
    @Environment(\.appContainer) private var appContainer
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
    @State private var descriptionChrome = DescriptionEditorChromeState()
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
    @State private var keyboardOverlapHeight: CGFloat = 0
    @State private var descriptionEditorScrollTask: Task<Void, Never>?
    /// Backs the «nutrition may be outdated → recalculate» flow. Constructed in
    /// `.task(id: recipeId)` from `appContainer` so the view never touches
    /// `APIClient.shared` directly.
    @State private var nutritionRecalculation: RecipeNutritionRecalculationModel?
    @State private var lazyResolvedIngredients: [IngredientData]?

    private var recipe: RecipeData? {
        guard syncService.currentRecipe?.id == recipeId else { return nil }
        return syncService.currentRecipe
    }

    private var ingredientsForDisplay: [IngredientData] {
        lazyResolvedIngredients ?? recipe?.ingredients ?? []
    }

    private var recipeIngredientsLazyResolveKey: String {
        guard let recipe, recipe.id == recipeId else { return recipeId }
        let unresolved = recipe.ingredients.filter {
            ($0.illustrationId?.isEmpty != false) && !$0.illustrationPickerCleared
        }.count
        let bindingSignature = recipe.ingredients.map {
            "\($0.id):\($0.illustrationId ?? ""):\($0.illustrationPickerCleared)"
        }.joined(separator: "|")
        return "\(recipeId)|\(recipe.ingredients.count)|unresolved:\(unresolved)|bindings:\(bindingSignature)|editing:\(isEditing)"
    }

    private func runIngredientIllustrationLazyResolve() async {
        guard let recipe, recipe.id == recipeId, !isLegacyReadOnly else {
            lazyResolvedIngredients = nil
            return
        }
        let plan = IngredientIllustrationLazyResolve.plan(ingredients: recipe.ingredients)
        lazyResolvedIngredients = plan.displayIngredients
        guard !isEditing, !saveInFlight, !plan.pendingWrites.isEmpty else { return }
        await IngredientIllustrationLazyResolve.applyPendingWrites(
            writes: plan.pendingWrites,
            syncService: syncService
        )
    }

    private func recipeWithDisplayIngredients(_ base: RecipeData) -> RecipeData {
        guard let lazyResolvedIngredients else { return base }
        let merged = IngredientIllustrationLazyResolve.mergeStoredIllustrationBindings(
            stored: base.ingredients,
            lazyPreview: lazyResolvedIngredients
        )
        return base.replacing(ingredients: merged)
    }

    private func syncLazyResolvedIllustrationBinding(
        ingredientId: String,
        illustrationId: String?,
        pickerCleared: Bool
    ) {
        guard var resolved = lazyResolvedIngredients,
              let index = resolved.firstIndex(where: { $0.id == ingredientId })
        else { return }
        resolved[index] = resolved[index].withIllustrationBinding(
            illustrationId: illustrationId,
            pickerCleared: pickerCleared
        )
        lazyResolvedIngredients = resolved
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

    private func prefetchHeaderImage() async {
        guard let imageUrl = headerImageUrl else { return }
        await appContainer?.recipeImage.prefetchFull(
            recipeId: recipeId,
            imageUrl: imageUrl,
            allowNetwork: allowsImageNetworkRefresh
        )
    }

    private func scheduleDescriptionEditorScroll(
        immediate: Bool = false,
        onlyCorrectIfOffsetTooHigh: Bool = false
    ) {
        guard isEditing, descriptionChrome.isFocused else { return }
        descriptionEditorScrollTask?.cancel()
        descriptionEditorScrollTask = Task { @MainActor in
            if !immediate {
                // Wait past keyboard animation (~0.25s) + safeAreaInset settle.
                try? await Task.sleep(for: .milliseconds(350))
            } else {
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard !Task.isCancelled else { return }
            guard isEditing, descriptionChrome.isFocused else { return }

            // Keyboard avoidance keeps rewriting contentOffset after our apply.
            // Re-pin for ~2s; only pull offset DOWN when it drifts above target
            // so we do not fight the user scrolling up to earlier text.
            let deadline = ContinuousClock.now + .seconds(2)
            var iteration = 0
            while !Task.isCancelled, ContinuousClock.now < deadline {
                guard isEditing, descriptionChrome.isFocused else { return }
                if iteration > 0, keyboardOverlapHeight <= 0 { return }
                if let editorView = descriptionChrome.bridge?.editorWebView,
                   let scrollView = DescriptionEditorScrollAnchor.detailScrollView(
                       containing: editorView
                   ) {
                    if scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating {
                        return
                    }
                }
                descriptionChrome.bridge?.editorWebView?.scrollView.setContentOffset(
                    .zero,
                    animated: false
                )
                _ = await DescriptionEditorScrollAnchor.scrollCaretIntoView(
                    bridge: descriptionChrome.bridge,
                    keyboardOverlap: keyboardOverlapHeight,
                    onlyCorrectIfOffsetTooHigh: onlyCorrectIfOffsetTooHigh || iteration > 0
                )
                iteration += 1
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// Document padding under the editor (bar clearance + breathing room).
    /// Keyboard overlap must not be added here — that renders a keyboard-tall
    /// hole. System keyboard avoidance + the formatting-bar `safeAreaInset`
    /// own visible extent above the keyboard.
    private var descriptionEditorScrollBottomInset: CGFloat {
        guard isEditing else { return 0 }
        return DescriptionFormattingBarLayoutMetrics.contentBottomPadding(
            showsFormattingBar: descriptionChrome.showsFormattingBar
        )
    }

    private func handleDescriptionContentHeightChange(
        oldHeight: CGFloat?,
        newHeight: CGFloat?
    ) {
        guard descriptionChrome.isFocused, let newHeight else { return }
        let shrank = oldHeight.map { newHeight < $0 - 8 } ?? false
        guard shrank || keyboardOverlapHeight > 0 else { return }
        // Height growth while typing must not yank a user who scrolled up;
        // shrink / first focus still pins the caret.
        scheduleDescriptionEditorScroll(
            immediate: shrank,
            onlyCorrectIfOffsetTooHigh: !shrank
        )
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
                                recipe: recipeWithDisplayIngredients(recipe),
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
                                onIllustrationPickerSelect: { ingredientId, illustrationId in
                                    await applyIngredientIllustrationSelection(
                                        ingredientId: ingredientId,
                                        illustrationId: illustrationId,
                                        editViewModel: editViewModel
                                    )
                                },
                                onIllustrationPickerClear: { ingredientId in
                                    await applyIngredientIllustrationClear(
                                        ingredientId: ingredientId,
                                        editViewModel: editViewModel
                                    )
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
                                ingredients: ingredientsForDisplay,
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
            .padding(.bottom, descriptionEditorScrollBottomInset)
        }
        .mobileTimerPanelBottomPadding(suppress: isEditing)
        .dismissPopoverOnVerticalDrag(isActive: descriptionTimerPopover != nil) {
            descriptionTimerPopover = nil
        }
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .onChange(of: descriptionChrome.isFocused) { _, focused in
            if !focused {
                keyboardOverlapHeight = 0
                descriptionEditorScrollTask?.cancel()
                descriptionEditorScrollTask = nil
            }
            guard focused else { return }
            clearIngredientFocusToken += 1
            dismissRecipeTitleKeyboard = true
            scheduleDescriptionEditorScroll()
        }
        .onChange(of: keyboardOverlapHeight) { _, overlap in
            guard descriptionChrome.isFocused else { return }
            guard overlap > 0 else { return }
            scheduleDescriptionEditorScroll()
        }
        .onChange(of: descriptionChrome.bridge?.contentHeight) { oldHeight, newHeight in
            handleDescriptionContentHeightChange(
                oldHeight: oldHeight,
                newHeight: newHeight
            )
        }
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
        // Do not ignore keyboard safe area while the formatting bar uses
        // `safeAreaInset` — on device that inflates scroll extent (~keyboard + bar)
        // and leaves a keyboard-tall hole under the description.
        .modifier(DescriptionEditorScrollKeyboardPolicy(
            ignoresKeyboardSafeArea: false
        ))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            if isScreenAwakeActive {
                ScreenAwakeStatusBanner()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            formattingBarInset
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
                    if isEditing, canEnterEditMode {
                        Button("edit.done") {
                            Task { await toggleEditMode() }
                        }
                        .appToolbarConfirmButton()
                        .accessibilityIdentifier(AccessibilityIdentifiers.recipeDetailDone)
                    } else if let recipe {
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
                            .accessibilityLabel("edit.edit")
                            .accessibilityIdentifier(AccessibilityIdentifiers.recipeDetailEdit)
                        }
                    }
                }
            }
        }
        .onChange(of: descriptionChrome.isFocused) { _, focused in
            if !focused {
                keyboardOverlapHeight = 0
            }
            guard focused else { return }
            clearIngredientFocusToken += 1
            dismissRecipeTitleKeyboard = true
        }
        .onChange(of: isEditing) { _, editing in
            timerManager.setSuppressPanelSafeAreaInset(editing)
        }
        .onAppear {
            timerManager.setSuppressPanelSafeAreaInset(isEditing)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillChangeFrameNotification
            )
        ) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                    as? CGRect else { return }
            let windowHeight = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)?
                .bounds.height ?? UIScreen.main.bounds.height
            let overlap = max(0, windowHeight - frame.minY)
            keyboardOverlapHeight = overlap
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
        ) { _ in
            keyboardOverlapHeight = 0
        }
        .errorAlert(title: "edit.error.title", message: $editErrorMessage)
        .errorAlert(title: "llm.parse-recipe", message: $descriptionParseError)

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
            timerManager.setSuppressPanelSafeAreaInset(false)
            guard !assistantRecipeContext.isAssistantSheetOpen else { return }
            assistantRecipeContext.clearVisibleRecipeId(recipeId)
            deactivateScreenAwake()
        }
        .task(id: recipeId) {
            deactivateScreenAwake()
            lazyResolvedIngredients = nil
            isLoading = true
            defer { isLoading = false }
            scaleFactor = RecipeScaleStorage.loadScaleFactor(recipeId: recipeId)
            if nutritionRecalculation == nil, let container = appContainer {
                nutritionRecalculation = RecipeNutritionRecalculationModel(api: container.api)
            }
            syncService.acknowledgeRecipeRemoved()
            await syncService.loadRecipe(recipeId: recipeId)
            #if DEBUG
            if let screenshotScale = DebugLaunchOptions.screenshotScaleFactor {
                scaleFactor = screenshotScale
                RecipeScaleStorage.saveScaleFactor(recipeId: recipeId, scaleFactor: screenshotScale)
            }
            if DebugLaunchOptions.screenshotScreenAwake {
                isScreenAwakeActive = true
                ScreenAwakeController.setActive(true)
            }
            #endif
        }
        .task(id: recipeIngredientsLazyResolveKey) {
            await runIngredientIllustrationLazyResolve()
        }
        .task(id: "\(recipeId)-\(headerImageUrl ?? "")") {
            await prefetchHeaderImage()
        }
        .onChange(of: allowsImageNetworkRefresh) { wasAllowed, isAllowed in
            guard !wasAllowed, isAllowed, headerImageUrl != nil else { return }
            Task { await prefetchHeaderImage() }
        }
        .onChange(of: recipe?.version) { _, _ in
            if isLegacyReadOnly, isEditing {
                isEditing = false
            }
            applyStartInEditModeIfNeeded()
        }
        .onChange(of: recipe?.id) { _, _ in
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
            assistantRecipeContext.setVisibleRecipeId(recipeId)
            applyStartInEditModeIfNeeded()
            applyStartDescriptionEditIfNeeded()
            #if DEBUG
            scheduleDebugDescriptionEditorIfNeeded()
            #endif
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
            onRecalculate: outdated ? { [weak nutritionRecalculation] in
                guard let model = nutritionRecalculation else { return }
                await model.recalculate(recipeId: recipeId, syncService: syncService)
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

    @ViewBuilder
    private var formattingBarInset: some View {
        if isEditing,
           descriptionChrome.showsFormattingBar,
           let bridge = descriptionChrome.bridge {
            DescriptionFormattingBar(
                bridge: bridge,
                accentColor: accentColor,
                onDone: { descriptionChrome.blurEditor() },
                onMarkTimer: beginDescriptionTimerMarkup,
                onMarkIngredient: beginDescriptionIngredientMarkup,
                onParseRecipe: {
                    Task { await runDescriptionLLMParse(bridge: bridge) }
                }
            )
        }
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
        #if DEBUG
        #endif
    }

    #if DEBUG
    /// Retries edit + editor sheet until recipe is loaded (verify scripts).
    private func scheduleDebugDescriptionEditorIfNeeded() {
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
        _ = timerManager.createAndStartTimer(
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
            try await RecipeLLMParseAPI.parseAndApply(recipeId: recipeId, stepsHtml: html, language: AppLanguagePreference.current.rawValue)
            // Sync delivers recipe_updated / collection_updated / document_loaded.
        } catch {
            descriptionParseError = UserFacingAPIError.message(for: error)
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
            editErrorMessage = UserFacingAPIError.message(for: error)
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
            editErrorMessage = UserFacingAPIError.message(for: error)
        }
    }

    private func saveIngredient(_ ingredient: IngredientData, existing: IngredientData?) async {
        guard let editViewModel, !saveInFlight else { return }
        saveInFlight = true
        defer { saveInFlight = false }
        do {
            try await editViewModel.saveIngredient(ingredient, existing: existing)
        } catch {
            editErrorMessage = UserFacingAPIError.message(for: error)
        }
    }

    private func deleteIngredient(id: String) async {
        guard let editViewModel, !saveInFlight else { return }
        saveInFlight = true
        defer { saveInFlight = false }
        do {
            try await editViewModel.deleteIngredient(id: id)
        } catch {
            editErrorMessage = UserFacingAPIError.message(for: error)
        }
    }

    private func applyIngredientIllustrationSelection(
        ingredientId: String,
        illustrationId: String,
        editViewModel: RecipeEditViewModel
    ) async {
        guard !saveInFlight else { return }
        saveInFlight = true
        defer { saveInFlight = false }
        do {
            try await editViewModel.applyIngredientIllustrationPickerSelection(
                ingredientId: ingredientId,
                illustrationId: illustrationId
            )
            syncLazyResolvedIllustrationBinding(
                ingredientId: ingredientId,
                illustrationId: illustrationId,
                pickerCleared: false
            )
        } catch {
            editErrorMessage = UserFacingAPIError.message(for: error)
        }
    }

    private func applyIngredientIllustrationClear(
        ingredientId: String,
        editViewModel: RecipeEditViewModel
    ) async {
        guard !saveInFlight else { return }
        saveInFlight = true
        defer { saveInFlight = false }
        do {
            try await editViewModel.applyIngredientIllustrationPickerClear(ingredientId: ingredientId)
            syncLazyResolvedIllustrationBinding(
                ingredientId: ingredientId,
                illustrationId: nil,
                pickerCleared: true
            )
        } catch {
            editErrorMessage = UserFacingAPIError.message(for: error)
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
            ShoppingFeedback.postStatus(UserFacingAPIError.message(for: error))
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
            editErrorMessage = UserFacingAPIError.message(for: error)
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

    private var titleFont: Font {
        AppTypography.display(AppTypography.recipeTitleSize)
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
                    font: titleFont,
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

private struct DescriptionEditorScrollKeyboardPolicy: ViewModifier {
    var ignoresKeyboardSafeArea: Bool

    func body(content: Content) -> some View {
        content.ignoresSafeArea(
            ignoresKeyboardSafeArea ? .keyboard : SafeAreaRegions(),
            edges: .bottom
        )
    }
}

/// Scrolls the inline description editor so the caret sits in the visible
/// band above the formatting bar / keyboard.
///
/// System keyboard avoidance + formatting-bar `safeAreaInset` own scroll extent.
/// This helper only moves `contentOffset` (explicit clamp — `scrollRectToVisible`
/// is unreliable while keyboard insets are animating).
private enum DescriptionEditorScrollAnchor {
    private static let caretTopMargin: CGFloat = 72
    private static let caretBottomPadding: CGFloat = 8

    @MainActor
    static func scrollCaretIntoView(
        bridge: DescriptionEditorBridge?,
        keyboardOverlap: CGFloat,
        onlyCorrectIfOffsetTooHigh: Bool = false
    ) async -> Bool {
        guard let editorView = bridge?.editorWebView ?? keyWindowDescriptionWebView(),
              let scrollView = detailScrollView(containing: editorView)
        else { return false }

        let editorRect = editorView.convert(editorView.bounds, to: scrollView)
        guard editorRect.height > 0, editorRect.width > 0 else { return false }

        let paintedBottom = min(
            editorRect.height,
            max(bridge?.paintedContentBottom ?? editorRect.height, 1)
        )
        let effectiveEditorRect = CGRect(
            x: editorRect.minX,
            y: editorRect.minY,
            width: editorRect.width,
            height: paintedBottom
        )

        var caretInEditor: CGRect?
        if let bridge {
            caretInEditor = await bridge.requestCaretRectInEditor()
        }
        if caretInEditor == nil, let webView = editorView as? WKWebView {
            caretInEditor = await queryCaretRect(on: webView)
        }

        let breathing = DescriptionFormattingBarLayoutMetrics.contentBottomBreathingRoom
        let barTopInBounds = formattingBarTopInScrollBounds(scrollView)
        let focusRect: CGRect
        var pinToBottom = false
        let userIsScrolling = scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating

        if let caretInEditor {
            let caret = editorView.convert(caretInEditor, to: scrollView)
            let nearPaintedEnd = caret.maxY >= effectiveEditorRect.maxY - 64
            pinToBottom = nearPaintedEnd
            if nearPaintedEnd {
                // Last lines: pin painted bottom just above the formatting bar.
                let pinHeight: CGFloat = 48 + breathing
                focusRect = CGRect(
                    x: effectiveEditorRect.minX,
                    y: max(effectiveEditorRect.minY, effectiveEditorRect.maxY - pinHeight),
                    width: effectiveEditorRect.width,
                    height: pinHeight
                )
            } else {
                let caretReveal = CGRect(
                    x: effectiveEditorRect.minX,
                    y: max(effectiveEditorRect.minY, caret.minY - caretTopMargin),
                    width: effectiveEditorRect.width,
                    height: max(
                        caret.height + breathing + caretBottomPadding,
                        44
                    )
                )
                focusRect = CGRect(
                    x: caretReveal.minX,
                    y: caretReveal.minY,
                    width: caretReveal.width,
                    height: min(
                        caretReveal.height,
                        max(0, effectiveEditorRect.maxY - caretReveal.minY)
                    )
                )
            }
        } else {
            let sliceHeight = min(120, effectiveEditorRect.height)
            focusRect = CGRect(
                x: effectiveEditorRect.minX,
                y: effectiveEditorRect.minY,
                width: effectiveEditorRect.width,
                height: sliceHeight + breathing
            )
        }

        let maxOffsetBelowEditor = maxOffsetShowingEditorBottom(
            scrollView: scrollView,
            editorRect: effectiveEditorRect,
            barTopInBounds: barTopInBounds,
            breathing: breathing
        )

        // Visibility alone is not enough: keyboard avoidance can leave the
        // caret in-band while contentOffset sits above the pin (white hole).
        let offsetTooHigh = scrollView.contentOffset.y > maxOffsetBelowEditor + 2
        if !onlyCorrectIfOffsetTooHigh,
           !offsetTooHigh,
           (keyboardOverlap <= 0 || caretInEditor != nil),
           isFocusVisible(focusRect: focusRect, scrollView: scrollView)
        {
            return true
        }

        let rawTargetOffsetY = targetContentOffset(
            scrollView: scrollView,
            focusRect: focusRect,
            preferCaretBottom: pinToBottom,
            barTopInBounds: barTopInBounds,
            breathing: breathing
        )
        let targetOffsetY = min(rawTargetOffsetY, maxOffsetBelowEditor)
        let appliedOffsetY = clampedContentOffset(
            scrollView: scrollView,
            targetOffsetY: targetOffsetY
        )

        if onlyCorrectIfOffsetTooHigh,
           !userIsScrolling,
           scrollView.contentOffset.y <= appliedOffsetY + 2
        {
            return true
        }

        guard abs(scrollView.contentOffset.y - appliedOffsetY) > 1 else {
            return true
        }

        return await applyContentOffset(
            scrollView: scrollView,
            offsetY: appliedOffsetY
        )
    }

    @MainActor
    private static func applyContentOffset(
        scrollView: UIScrollView,
        offsetY: CGFloat
    ) async -> Bool {
        // A caret query can span the start of a user pan. Never overwrite the
        // offset while UIKit owns the gesture (device logs: 2321 → 1888).
        guard !(scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating) else {
            return false
        }
        for attempt in 0 ..< 6 {
            guard !(scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating) else {
                return false
            }
            UIView.performWithoutAnimation {
                scrollView.layer.removeAllAnimations()
                scrollView.setContentOffset(
                    CGPoint(x: scrollView.contentOffset.x, y: offsetY),
                    animated: false
                )
                scrollView.layoutIfNeeded()
            }
            if abs(scrollView.contentOffset.y - offsetY) <= 1 {
                return true
            }
            if attempt < 5 {
                try? await Task.sleep(for: .milliseconds(32))
            }
        }
        return abs(scrollView.contentOffset.y - offsetY) <= 2
    }

    private static func bottomPinnedContentOffset(
        scrollView: UIScrollView,
        focusMaxY: CGFloat,
        barTopInBounds: CGFloat?,
        breathing: CGFloat
    ) -> CGFloat {
        if let barTopInBounds, barTopInBounds > 0 {
            // Pin focusMaxY just above the real formatting-bar frame (bounds space).
            // contentY = offset + boundsY  ⇒  offset = focusMaxY - barTop + breathing
            return focusMaxY - barTopInBounds + breathing
        }
        return DescriptionFormattingBarLayoutMetrics.bottomPinnedContentOffset(
            focusMaxY: focusMaxY,
            boundsHeight: scrollView.bounds.height,
            insetBottom: scrollView.adjustedContentInset.bottom
        )
    }

    @MainActor
    private static func formattingBarTopInScrollBounds(_ scrollView: UIScrollView) -> CGFloat? {
        guard let root = scrollView.window ?? keyWindow() else { return nil }
        guard let bar = findView(in: root, accessibilityID: "description_formatting_bar") else {
            return nil
        }
        let frame = bar.convert(bar.bounds, to: scrollView)
        guard frame.height > 0, frame.minY > 0 else { return nil }
        return frame.minY
    }

    @MainActor
    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    private static func findView(in root: UIView, accessibilityID: String) -> UIView? {
        if root.accessibilityIdentifier == accessibilityID { return root }
        for sub in root.subviews {
            if let found = findView(in: sub, accessibilityID: accessibilityID) {
                return found
            }
        }
        return nil
    }

    @MainActor
    private static func visibleContentHeight(scrollView: UIScrollView) -> CGFloat {
        max(
            0,
            scrollView.bounds.height
                - scrollView.adjustedContentInset.top
                - scrollView.adjustedContentInset.bottom
        )
    }

    @MainActor
    private static func visibleContentRect(in scrollView: UIScrollView) -> CGRect {
        let insetTop = scrollView.adjustedContentInset.top
        let insetBottom = scrollView.adjustedContentInset.bottom
        let minY = scrollView.contentOffset.y + insetTop
        let maxY = scrollView.contentOffset.y + scrollView.bounds.height - insetBottom
        return CGRect(x: 0, y: minY, width: scrollView.bounds.width, height: max(0, maxY - minY))
    }

    /// Do not scroll past the editor bottom — avoids a WebView-tall white band under text.
    @MainActor
    private static func maxOffsetShowingEditorBottom(
        scrollView: UIScrollView,
        editorRect: CGRect,
        barTopInBounds: CGFloat?,
        breathing: CGFloat
    ) -> CGFloat {
        let insetTop = scrollView.adjustedContentInset.top
        return max(
            -insetTop,
            bottomPinnedContentOffset(
                scrollView: scrollView,
                focusMaxY: editorRect.maxY,
                barTopInBounds: barTopInBounds,
                breathing: breathing
            )
        )
    }

    @MainActor
    private static func isFocusVisible(
        focusRect: CGRect,
        scrollView: UIScrollView
    ) -> Bool {
        let visible = visibleContentRect(in: scrollView)
        guard visible.height > 0 else { return false }
        return focusRect.minY >= visible.minY - 2
            && focusRect.maxY <= visible.maxY + 2
    }

    @MainActor
    private static func targetContentOffset(
        scrollView: UIScrollView,
        focusRect: CGRect,
        preferCaretBottom: Bool,
        barTopInBounds: CGFloat?,
        breathing: CGFloat
    ) -> CGFloat {
        let insetTop = scrollView.adjustedContentInset.top
        if preferCaretBottom {
            return bottomPinnedContentOffset(
                scrollView: scrollView,
                focusMaxY: focusRect.maxY,
                barTopInBounds: barTopInBounds,
                breathing: breathing
            )
        }
        return focusRect.minY - insetTop
    }

    @MainActor
    private static func clampedContentOffset(
        scrollView: UIScrollView,
        targetOffsetY: CGFloat
    ) -> CGFloat {
        let insetTop = scrollView.adjustedContentInset.top
        let insetBottom = scrollView.adjustedContentInset.bottom
        let minY = -insetTop
        let maxY = max(
            minY,
            scrollView.contentSize.height + insetBottom - scrollView.bounds.height
        )
        return min(max(targetOffsetY, minY), maxY)
    }

    @MainActor
    private static func queryCaretRect(on webView: WKWebView) async -> CGRect? {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(
                "window.__descriptionEditorGetCaretRect && window.__descriptionEditorGetCaretRect()"
            ) { result, _ in
                continuation.resume(
                    returning: DescriptionEditorWebView.Coordinator.parseCaretRect(result)
                )
            }
        }
    }

    @MainActor
    private static func keyWindowDescriptionWebView() -> WKWebView? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        else { return nil }
        return findWebView(in: window)
    }

    private static func findWebView(in view: UIView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        for sub in view.subviews {
            if let found = findWebView(in: sub) { return found }
        }
        return nil
    }

    /// Detail `ScrollView`, never the editor's nested `WKWebView.scrollView`.
    /// Prefer the ancestor with the largest content size that contains the
    /// editor — SwiftUI may insert intermediate scroll views.
    static func detailScrollView(containing editorView: UIView) -> UIScrollView? {
        var ancestor: UIView? = editorView.superview
        var best: UIScrollView?
        var bestContentHeight: CGFloat = 0
        while let current = ancestor {
            if let scroll = current as? UIScrollView, !scroll.isDescendant(of: editorView) {
                let editorRect = editorView.convert(editorView.bounds, to: scroll)
                if editorRect.height > 0, scroll.contentSize.height >= bestContentHeight {
                    best = scroll
                    bestContentHeight = scroll.contentSize.height
                }
            }
            ancestor = current.superview
        }
        return best
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

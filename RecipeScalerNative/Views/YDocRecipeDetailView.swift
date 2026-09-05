import SwiftUI
import RecipeScalerCore
import WebKit

/// Recipe detail backed by Y.Doc via `YjsSyncService`.
struct YDocRecipeDetailView: View {
    let recipeId: String
    var startInEditMode: Bool = false
    var startDescriptionEdit: Bool = false

    @Environment(YjsSyncService.self) var syncService
    @Environment(AssistantRecipeContext.self) private var assistantRecipeContext
    @Environment(TimerManager.self) var timerManager
    @Environment(\.appContainer) private var appContainer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// UI-only scale (web `recipe-scale:{id}` in localStorage). Not written to Y.Doc.
    @State var scaleFactor: Double = 1
    @AppStorage(NutritionSettings.globalEnabledKey) private var showNutritionGlobal = true
    @State var nutritionViewMode: IngredientNutritionViewMode = NutritionViewModeStorage.load()
    @State private var isLoading = false
    #if DEBUG
    @State var didScheduleNutritionScreenshot = false
    #endif
    @State var isEditing = false
    @State var editViewModel: RecipeEditViewModel?
    @State var editErrorMessage: String?
    @State var pickerColor: Color = RecipeAccentColor.color(from: "oklch(0.65 0.25 270)")
    @State var saveInFlight = false
    @State var didApplyStartInEditMode = false
    @State var shouldAutoFocusRecipeTitle = false
    @State var descriptionChrome = DescriptionEditorChromeState()
    @State var didApplyStartDescriptionEdit = false
    @State var dismissRecipeTitleKeyboard = false
    @State var commitTitleNonce = 0
    @State var titleSaveTask: Task<Void, Never>?
    @State var isFinishingEdit = false
    @State var isScreenAwakeActive = false
    @State private var descriptionTimerPopover: DescriptionTimerPopoverState?
    @State var descriptionTimerMarkupDraft: DescriptionTimerMarkupDraft?
    @State var descriptionIngredientPickerPresented = false
    @State var descriptionMarkupSelectedText = ""
    @State var descriptionTimerNodeMenu: DescriptionTimerNodeMenuState?
    @State var descriptionIngredientNodeMenu: DescriptionIngredientNodeMenuState?
    @State var ingredientFieldsFocused = false
    @State private var clearIngredientFocusToken = 0
    @State var isParsingDescription = false
    @State var descriptionParseError: String?
    @State private var keyboardOverlapHeight: CGFloat = 0
    @State private var descriptionEditorScrollTask: Task<Void, Never>?
    /// Backs the «nutrition may be outdated → recalculate» flow. Constructed in
    /// `.task(id: recipeId)` from `appContainer` so the view never touches
    /// `APIClient.shared` directly.
    @State var nutritionRecalculation: RecipeNutritionRecalculationModel?
    @State private var lazyResolvedIngredients: [IngredientData]?

    var recipe: RecipeData? {
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

    func syncLazyResolvedIllustrationBinding(
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

    var canEnterEditMode: Bool {
        guard let recipe else { return false }
        return RecipeEditPolicy.canEdit(recipe: recipe)
    }

    var accentColor: Color {
        if isEditing, let editViewModel {
            return RecipeAccentColor.color(from: editViewModel.draftColor)
        }
        return RecipeAccentColor.color(from: recipe?.color ?? "")
    }

    /// Image metadata from collection (instant) or merged recipe doc (after load).
    var headerImageUrl: String? {
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
                                .id("recipe_nutrition")
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
        .onChange(of: isLoading) { _, loading in
            scheduleScreenshotNutritionScrollIfNeeded(
                scrollProxy: scrollProxy,
                loading: loading
            )
        }
        .task(id: "\(recipeId)-nutrition-\(isLoading)-\(recipe == nil ? "0" : "1")") {
            scheduleScreenshotNutritionScrollIfNeeded(
                scrollProxy: scrollProxy,
                loading: isLoading
            )
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
            if DebugLaunchOptions.screenshotScrollToNutrition {
                showNutritionGlobal = true
            }
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
            #if DEBUG
            if !DebugLaunchOptions.screenshotScrollToNutrition {
                await DebugLaunchOptions.signalScreenshotRecipeMediaReadyIfNeeded(
                    recipeId: recipeId,
                    imageUrl: headerImageUrl
                )
            }
            #endif
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
}

// Review 2026.09.04 №20 — `RecipeEditHeaderBindable`,
// `DescriptionEditorScrollKeyboardPolicy`, `dismissPopoverOnVerticalDrag`
// and `DescriptionEditorScrollAnchor` live in
// `YDocRecipeDetailScrollSupport.swift` / `YDocRecipeDetailEditHeader.swift`.

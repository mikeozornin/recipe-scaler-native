import SwiftUI
import RecipeScalerCore
import WebKit

/// Recipe detail backed by Y.Doc via `YjsSyncService`.
struct YDocRecipeDetailView: View {
    let recipeId: String
    var startInEditMode: Bool = false
    var startDescriptionEdit: Bool = false
    /// Injected (not `@Environment`): iOS 26 builds the pushed destination's
    /// body while measuring bar items in a fallback environment (no injected
    /// observables); `@Environment(SomeObservable.self)` on the pushed root
    /// traps during `EnvironmentValues.subscript.getter` (assistant dismiss →
    /// recipe push repro).
    let syncService: YjsSyncService
    let assistantRecipeContext: AssistantRecipeContext
    let timerManager: TimerManager
    let apiClient: APIClient
    /// Injected (not `@Environment`): same iOS 26 toolbar fallback-env rule as
    /// other observables — Entry lookup is usually safe, but keep the pushed
    /// root free of `@Environment` storage that participates in bar sizing.
    let appContainer: AppContainer?
    /// Injected dismiss — avoid `@Environment(\.dismiss)` on the pushed root
    /// (bar-item sizing after assistant dismiss uses a fallback environment).
    var onDismiss: (() -> Void)? = nil
    var scenePhase: ScenePhase = .active
    /// Spec 081 — the panel of the iPad split: two columns and the iPad toolbar.
    /// `nil` on the phone and in a compact iPad window.
    var padPanel: RecipeDetailPadPanel? = nil
    /// Spec 081 (T037) — `.padRegular` in the iPad split and its phone stack: «В коллекцию»
    /// opens a popover. Injected, as the bar items may get a fallback environment.
    var layoutMode: AppLayoutMode = .phone
    /// Spec 081 (US5, T043) — keeps an edit across the rebuilds of this view on the iPad
    /// (size class change, split ↔ phone stack): `AppShellCoordinator.recipeEdit`.
    /// `nil` on the iPhone.
    var iPadEditHost: AppShellCoordinator? = nil
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
    /// This view in the iPad edit session (`IPadRecipeEditSession.owner`).
    @State var editOwnerToken = UUID()
    /// This view as the one showing the recipe to the assistant
    /// (`AssistantRecipeContext.setVisibleRecipeId(_:owner:)`).
    @State private var assistantContextOwner = UUID()
    /// The unsaved title of the view this one replaced (T043); `nil` once saved.
    @State var adoptedTitleDraft: String?
    /// The steps caret of the view this one replaced, put back once the editor is ready.
    @State var adoptedStepsCaret: IPadRecipeEditFocus?
    @State var isScreenAwakeActive = false
    /// Screen-scoped owner of the camera, mic, and speech session.
    /// ASYNC-LIFECYCLE §3 judgment call: logout pops this screen, so
    /// `onDisappear` → `stopIfViewRemoved()` tears the hardware down, and the
    /// controller `deinit` backstops a release that skips that callback.
    /// `isViewInHierarchy` stops a help-sheet dismiss from re-arming after the
    /// detail was popped while the sheet was still open.
    @State private var awakeScrollController = AwakeScrollController()
    @State private var isViewInHierarchy = false
    @AppStorage(AwakeHandsFreeStorage.voiceKey) private var awakeVoiceEnabled = false
    @AppStorage(AwakeHandsFreeStorage.handKey) private var awakeHandEnabled = false
    @AppStorage(AwakeHandsFreeStorage.faceKey) private var awakeFaceEnabled = false
    @State private var showingAwakeScrollHelp = false
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


    private func performDismiss() {
        if let onDismiss {
            onDismiss()
        }
    }

    var body: some View {
        RecipeDetailToolbarHost(
            recipeId: recipeId,
            recipe: recipe,
            isEditing: isEditing,
            canEnterEditMode: canEnterEditMode,
            isPinned: syncService.collectionEntries.first { $0.id == recipeId }?.isPinned ?? false,
            syncService: syncService,
            apiClient: apiClient,
            isScreenAwakeActive: $isScreenAwakeActive,
            padPanel: padPanel,
            layoutMode: layoutMode,
            onToggleEdit: { Task { await toggleEditMode() } }
        ) {
        ScrollViewReader { scrollProxy in
        detailScroll
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Two columns: under the steps only (`YDocRecipeDetailColumns.rightBar`, T042).
            if !showsTwoColumns {
                formattingBarInset
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
            syncIPadEditSession(editing: editing)
        }
        .onAppear {
            isViewInHierarchy = true
            timerManager.setSuppressPanelSafeAreaInset(isEditing)
            awakeScrollController.flags.detailVisible = true
            // Capture Bindings only — capturing `self` / the view method would
            // retain the `@State` box that owns the controller (cycle).
            let voice = $awakeVoiceEnabled
            let hand = $awakeHandEnabled
            let face = $awakeFaceEnabled
            awakeScrollController.onChannelPrefsChanged = {
                voice.wrappedValue = AwakeHandsFreeStorage.voiceEnabled
                hand.wrappedValue = AwakeHandsFreeStorage.handEnabled
                face.wrappedValue = AwakeHandsFreeStorage.faceEnabled
            }
            syncAwakeScrollArm()
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
                performDismiss()
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
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                // Real leave (home / switch app) — like web `document.hidden`.
                deactivateScreenAwake()
            case .active:
                // Control Center / notification shade is `.inactive`, not `.background`.
                awakeScrollController.refreshPermissions()
                if isScreenAwakeActive {
                    ScreenAwakeController.setActive(true)
                }
            default:
                break
            }
        }
        .onDisappear {
            isViewInHierarchy = false
            let sheetOverlay = showingAwakeScrollHelp
                && awakeScrollController.probe.host?.window != nil
            if !sheetOverlay {
                awakeScrollController.stopIfViewRemoved()
            }
            if !leaveIPadEditSession() {
                timerManager.setSuppressPanelSafeAreaInset(false)
            }
            // Under the assistant sheet the recipe keeps its context and keep-awake; beside
            // the iPad panel it is gone like without the panel (spec 081, T036).
            guard !assistantRecipeContext.coversRecipe else { return }
            assistantRecipeContext.clearVisibleRecipeId(recipeId, owner: assistantContextOwner)
            if !sheetOverlay {
                deactivateScreenAwake()
            }
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
            // An edit adopted from the view this one replaced keeps its drafts (T043).
            guard !(isEditing && editViewModel != nil && editViewModel === iPadEditHost?.recipeEdit?.viewModel)
            else { return }
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
            assistantRecipeContext.setVisibleRecipeId(recipeId, owner: assistantContextOwner)
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
        // Cooking-mode chrome (awake banner + hands-free) must sit *outside*
        // RecipeDetailToolbarHost so the top safeAreaInset is applied after
        // `.toolbar`. Inside the host, iOS 26 Liquid Glass nav capsules share
        // the top safe-area band with that inset and ride up under the Dynamic
        // Island; on iOS 18 the banner can end up under the opaque nav bar.
        .modifier(
            AwakeScrollChromeModifier(
                controller: awakeScrollController,
                isScreenAwakeActive: isScreenAwakeActive,
                assistantSheetOpen: assistantRecipeContext.coversRecipe,
                cookingCoverPresented: appContainer?.cooking.presentation != nil,
                voiceEnabled: $awakeVoiceEnabled,
                handEnabled: $awakeHandEnabled,
                faceEnabled: $awakeFaceEnabled,
                showingHelp: $showingAwakeScrollHelp,
                onArmFlagsChanged: syncAwakeScrollArm
            )
        )
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

    // MARK: - Columns (spec 081, T025)

    /// Two columns in the iPad split panel ≥ 720 pt, in reading and in edit (US5, T041):
    /// the edit header and the ingredients on the left, the steps editor on the right.
    var showsTwoColumns: Bool {
        guard let padPanel else { return false }
        return padPanel.detailWidth >= IPadLayoutMetrics.twoColumnMinDetail
    }

    /// The phone column, or `YDocRecipeDetailColumns` on a wide iPad panel.
    @ViewBuilder
    private var detailScroll: some View {
        if showsTwoColumns, let padPanel {
            YDocRecipeDetailColumns(
                detailWidth: padPanel.detailWidth,
                rightBottomPadding: descriptionEditorScrollBottomInset
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    detailImageSection
                    VStack(alignment: .leading, spacing: 16) {
                        detailHeaderSections
                        if let recipe {
                            detailLeftSections(recipe: recipe)
                        }
                    }
                    .padding(.top, RecipeDetailLayoutMetrics.titleTopSpacing)
                }
            } right: {
                VStack(alignment: .leading, spacing: 16) {
                    if let recipe {
                        detailStepsSection(recipe: recipe)
                    }
                }
                .padding(.top, stepsColumnTopPadding)
                // Hands-free scrolling moves the steps (FR-026). Behind them, so the
                // probe adds no height above «Инструкции».
                .background(alignment: .topLeading) {
                    detailScrollProbe
                }
            } rightBar: {
                formattingBarInset
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    detailScrollProbe
                    detailImageSection
                    VStack(alignment: .leading, spacing: 16) {
                        detailHeaderSections
                        if let recipe {
                            detailLeftSections(recipe: recipe)
                            detailStepsSection(recipe: recipe)
                        }
                    }
                    .padding(.top, RecipeDetailLayoutMetrics.titleTopSpacing)
                }
                .padding(.bottom, descriptionEditorScrollBottomInset)
                .modifier(RecipeDetailSingleColumnWidth(isPadPanel: padPanel != nil))
            }
        }
    }

    /// «Инструкции» lines up with the top of the left column (`RecipeStepsColumnMetrics`).
    private var stepsColumnTopPadding: CGFloat {
        RecipeStepsColumnMetrics.topPadding(
            leftStartsWithBox: showsRecipeImageSection || isLegacyReadOnly,
            headerRowHeight: isEditing && canEnterEditMode ? nil : ProcessTableLayout.ctaMinHit
        )
    }

    private var detailScrollProbe: some View {
        DetailScrollViewProbe(box: awakeScrollController.probe)
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var detailImageSection: some View {
        if showsRecipeImageSection {
            RecipeDetailImageSection(
                recipeId: recipeId,
                imageUrl: headerImageUrl,
                imageAspectRatio: recipe?.imageAspectRatio.map { CGFloat($0) },
                isEditing: isEditing && canEnterEditMode,
                allowsNetworkRefresh: allowsImageNetworkRefresh,
                syncService: syncService
            )
        }
    }

    /// Loading, the legacy banner and the title (or the edit header).
    @ViewBuilder
    private var detailHeaderSections: some View {
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
    }

    /// Servings, ingredients and nutrition: the left column.
    @ViewBuilder
    private func detailLeftSections(recipe: RecipeData) -> some View {
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
                scaleFactor: scaleFactor,
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
                scaleFactor: scaleFactor,
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
    }

    /// The steps or the steps editor: the right column.
    @ViewBuilder
    private func detailStepsSection(recipe: RecipeData) -> some View {
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
                },
                processTableRecipe: recipe
            )
            .id("recipe_instructions")
            .background {
                iPadEditStepsProbe
            }
        } else if let description = recipe.description, !description.isEmpty {
            StepsSection(
                htmlContent: description,
                accentColor: accentColor,
                recipeId: recipeId,
                cookingRecipe: recipe,
                scaleFactor: scaleFactor,
                restoreAwakeOnDismiss: isScreenAwakeActive,
                allowsRebuild: canEnterEditMode,
                syncService: syncService,
                timerPopover: $descriptionTimerPopover
            )
                .id("recipe_instructions")
        }
    }

    func syncAwakeScrollArm() {
        guard isViewInHierarchy else {
            awakeScrollController.stopIfViewRemoved()
            deactivateScreenAwake()
            return
        }
        AwakeHandsFreeStorage.migrateIfNeeded(
            trueDepthAvailable: AwakeScrollCaptureSession.supportsFaceTracking
        )
        awakeScrollController.flags.recipeId = recipeId
        awakeScrollController.flags.isScreenAwakeActive = isScreenAwakeActive
        awakeScrollController.flags.voiceEnabled = awakeVoiceEnabled
        awakeScrollController.flags.handEnabled = awakeHandEnabled
        awakeScrollController.flags.faceEnabled = awakeFaceEnabled
        awakeScrollController.flags.cookingPresented = appContainer?.cooking.presentation != nil
        // The sheet covers the recipe; the iPad panel stands beside it (spec 081, T036).
        awakeScrollController.flags.assistantSheetOpen = assistantRecipeContext.coversRecipe
        awakeScrollController.syncArmState()
        pullAwakeChannelBindingsFromStorage()
    }

    func pullAwakeChannelBindingsFromStorage() {
        awakeVoiceEnabled = AwakeHandsFreeStorage.voiceEnabled
        awakeHandEnabled = AwakeHandsFreeStorage.handEnabled
        awakeFaceEnabled = AwakeHandsFreeStorage.faceEnabled
    }
}

// Review 2026.09.04 №20 — `RecipeEditHeaderBindable`,
// `DescriptionEditorScrollKeyboardPolicy`, `dismissPopoverOnVerticalDrag`
// and `DescriptionEditorScrollAnchor` live in
// `YDocRecipeDetailScrollSupport.swift` / `YDocRecipeDetailEditHeader.swift`.

private struct RecipeDetailToolbarHost<Content: View>: View {
    let recipeId: String
    let recipe: RecipeData?
    let isEditing: Bool
    let canEnterEditMode: Bool
    let isPinned: Bool
    let syncService: YjsSyncService
    let apiClient: APIClient
    @Binding var isScreenAwakeActive: Bool
    /// Spec 081 (T026): «…», «Поделиться» (wide), «Не гасить экран», ✦, «Изменить».
    let padPanel: RecipeDetailPadPanel?
    let layoutMode: AppLayoutMode
    let onToggleEdit: () -> Void
    @ViewBuilder let content: () -> Content

    /// The iPad items after the shared group; edit mode keeps only «Готово» (Q2).
    private var padActions: RecipeDetailPadPanel? {
        guard let padPanel, recipe != nil, !(isEditing && canEnterEditMode) else { return nil }
        return padPanel
    }

    /// «Изменить» as its own capsule; `.padBesideTabBar` keeps the pencil in the group.
    private var padEdit: RecipeDetailPadPanel? {
        guard canEnterEditMode, let padActions, padActions.toolbarStyle != .padBesideTabBar else { return nil }
        return padActions
    }

    var body: some View {
        content()
            .modifier(RecipeDetailTrailingToolbar(
                main: trailingToolbarItems,
                assistantCoordinator: padActions?.assistantCoordinator,
                edit: padEdit.map { editButton(showsTitle: $0.toolbarStyle == .padWide) }
            ))
    }

    @ViewBuilder
    private var trailingToolbarItems: some View {
        HStack(spacing: 0) {
            if isEditing, canEnterEditMode {
                Button("edit.done", action: onToggleEdit)
                    .appToolbarConfirmButton()
                    .accessibilityIdentifier(AccessibilityIdentifiers.recipeDetailDone)
            } else if let recipe {
                RecipeDetailActionsMenu(
                    recipeId: recipeId,
                    recipeName: recipe.name,
                    ingredients: recipe.ingredients,
                    isEditing: false,
                    isPinned: isPinned,
                    syncService: syncService,
                    layoutMode: layoutMode
                )
                if padPanel.map({ $0.toolbarStyle == .padWide }) ?? true {
                    RecipeDetailShareButton(
                        recipeId: recipeId,
                        isPublic: recipe.isPublic,
                        hasImage: !(recipe.imageUrl?.isEmpty ?? true),
                        hasSteps: recipe.hasSteps,
                        syncService: syncService,
                        apiClient: apiClient
                    )
                }
                ScreenAwakeToggle(isActive: $isScreenAwakeActive)
                if canEnterEditMode, padPanel == nil {
                    editButton(showsTitle: true)
                } else if canEnterEditMode, padPanel?.toolbarStyle == .padBesideTabBar {
                    editButton(showsTitle: false)
                }
            }
        }
    }

    @ViewBuilder
    private func editButton(showsTitle: Bool) -> some View {
        Button(action: onToggleEdit) {
            if showsTitle {
                AppToolbarStyle.labeledIcon(
                    systemName: "pencil",
                    title: "edit.edit"
                )
            } else {
                AppToolbarStyle.iconOnly(systemName: "pencil")
            }
        }
        .appToolbarIconButton()
        .accessibilityLabel("edit.edit")
        .accessibilityIdentifier(AccessibilityIdentifiers.recipeDetailEdit)
    }
}

/// The trailing bar items. On the phone one group, as before; on `.padRegular` ✦ and
/// «Изменить» follow as separate glass capsules (iOS 26), as in the prototype `.dt-bar`.
/// `ToolbarSpacer` needs iOS 26, and `#available` inside a toolbar builder needs
/// iOS 17.5, so the check sits at the view level.
private struct RecipeDetailTrailingToolbar<Main: View, Edit: View>: ViewModifier {
    let main: Main
    let assistantCoordinator: AppShellCoordinator?
    let edit: Edit?

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        main
                    }
                    if let assistantCoordinator {
                        ToolbarSpacer(.fixed, placement: .topBarTrailing)
                        ToolbarItem(placement: .topBarTrailing) {
                            IPadAssistantToolbarButton(coordinator: assistantCoordinator)
                        }
                    }
                    if let edit {
                        ToolbarSpacer(.fixed, placement: .topBarTrailing)
                        ToolbarItem(placement: .topBarTrailing) {
                            edit
                        }
                    }
                }
        } else {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        main
                    }
                    if let assistantCoordinator {
                        ToolbarItem(placement: .topBarTrailing) {
                            IPadAssistantToolbarButton(coordinator: assistantCoordinator)
                        }
                    }
                    if let edit {
                        ToolbarItem(placement: .topBarTrailing) {
                            edit
                        }
                    }
                }
        }
    }
}

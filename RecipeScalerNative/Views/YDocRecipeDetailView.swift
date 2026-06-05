import SwiftUI

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
    @State private var showsDescriptionEditor = false
    @State private var didApplyStartDescriptionEdit = false
    @State private var dismissRecipeTitleKeyboard = false
    @State private var commitTitleNonce = 0
    @State private var titleSaveTask: Task<Void, Never>?
    @State private var isFinishingEdit = false
    @State private var isScreenAwakeActive = false
    @State private var descriptionTimerPopover: DescriptionTimerPopoverState?


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
                        if isEditing {
                            RecipeEditToolbar(syncState: syncService.writeSyncState(for: recipeId))
                                .padding(.horizontal)
                        }

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
                                scaledServingsPreview: scaledServingsCount(
                                    base: max(1, editViewModel.draftServings)
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
                                }
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
                            RecipeNutritionBlockView(
                                recipe: recipe,
                                baseServings: max(1, recipe.servings),
                                scaleFactor: scaleFactor,
                                accentColor: accentColor,
                                viewMode: $nutritionViewMode
                            )
                        }

                        if isEditing, canEnterEditMode {
                            DescriptionEditorEntrySection(
                                recipe: recipe,
                                accentColor: accentColor,
                                onEdit: { showsDescriptionEditor = true }
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
        .simultaneousGesture(
            DragGesture(minimumDistance: 10).onChanged { _ in
                if descriptionTimerPopover != nil {
                    descriptionTimerPopover = nil
                }
            }
        )
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
        .overlay {
            if let popover = descriptionTimerPopover {
                DescriptionTimerPopoverOverlay(
                    state: popover,
                    accentColor: accentColor,
                    onStart: { startDescriptionTimer(from: popover.reference) },
                    onDismiss: { descriptionTimerPopover = nil }
                )
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            if isScreenAwakeActive {
                ScreenAwakeStatusBanner()
            }
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
                    Button(String(localized: "edit.done")) {
                        Task { await toggleEditMode() }
                    }
                    .appToolbarConfirmButton()
                }
            }
        }
        .alert(
            String(localized: "edit.error.title"),
            isPresented: Binding(
                get: { editErrorMessage != nil },
                set: { if !$0 { editErrorMessage = nil } }
            )
        ) {
            Button(String(localized: "edit.error.ok"), role: .cancel) {}
        } message: {
            Text(editErrorMessage ?? "")
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
            AgentSyncDebugLog.write(
                hypothesisId: "G",
                location: "YDocRecipeDetailView.swift:task",
                message: "after_load_recipe",
                data: [
                    "recipeId": recipeId,
                    "hasRecipe": String(syncService.currentRecipe?.id == recipeId),
                    "ingredientCount": String(syncService.currentRecipe?.ingredients.count ?? 0),
                    "hasHeaderImage": String(headerImageUrl != nil),
                ]
            )
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
            AgentSyncDebugLog.write(
                hypothesisId: "H4",
                location: "YDocRecipeDetailView.swift:onChange(recipe.id)",
                message: "recipe_id_changed",
                data: [
                    "recipeId": recipeId,
                    "isEditing": String(isEditing),
                    "isEditingTitle": String(editViewModel?.isEditingTitleField ?? false),
                ]
            )
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
        .onChange(of: isEditing) { _, _ in
            applyStartDescriptionEditIfNeeded()
        }
        .onAppear {
            applyStartInEditModeIfNeeded()
            applyStartDescriptionEditIfNeeded()
            scheduleDebugDescriptionEditorIfNeeded()
        }
        .sheet(isPresented: $showsDescriptionEditor) {
            if let recipe {
                DescriptionEditorView(
                    recipeId: recipeId,
                    accentColor: accentColor,
                    syncService: syncService
                )
                .environmentObject(syncService)
            }
        }
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
        showsDescriptionEditor = true
        #if DEBUG
        AgentSyncDebugLog.write(
            hypothesisId: "006",
            location: "YDocRecipeDetailView.swift:applyStartDescriptionEdit",
            message: "description_editor_sheet_presented",
            data: ["recipeId": recipeId]
        )
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
        _ = TimerManager.shared.createAndStartTimer(
            name: reference.resolvedName,
            duration: TimeInterval(reference.durationSeconds),
            type: reference.type,
            recipeId: recipeId
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
        guard let scaled = Double(normalized), scaled.isFinite else { return }
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
            onTitleBlur: { name in
                scheduleTitleSave(name, editViewModel: vm)
            },
            onEditingActiveChanged: { vm.isEditingTitleField = $0 }
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
            AgentSyncDebugLog.write(
                hypothesisId: "W",
                location: "YDocRecipeDetailView.swift:saveRecipeTitle",
                message: "title_blur_save_done",
                data: [
                    "recipeId": recipeId,
                    "nameLen": String(syncService.currentRecipe?.name.count ?? 0),
                ]
            )
            #endif
        } catch {
            editErrorMessage = error.localizedDescription
            #if DEBUG
            AgentSyncDebugLog.write(
                hypothesisId: "W",
                location: "YDocRecipeDetailView.swift:saveRecipeTitle",
                message: "title_blur_save_error",
                data: ["recipeId": recipeId, "error": error.localizedDescription]
            )
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
            AgentSyncDebugLog.write(
                hypothesisId: "H",
                location: "YDocRecipeDetailView.swift:toggleEditMode",
                message: "commit_begin",
                data: [
                    "recipeId": recipeId,
                    "hasRecipe": String(recipe != nil),
                    "titleLen": String(syncService.currentRecipe?.name.count ?? 0),
                ]
            )
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
                AgentSyncDebugLog.write(
                    hypothesisId: "H",
                    location: "YDocRecipeDetailView.swift:toggleEditMode",
                    message: "commit_done",
                    data: [
                        "recipeId": recipeId,
                        "syncState": String(describing: syncService.writeSyncState(for: recipeId)),
                    ]
                )
                #endif
            } catch {
                editErrorMessage = error.localizedDescription
                #if DEBUG
                AgentSyncDebugLog.write(
                    hypothesisId: "H",
                    location: "YDocRecipeDetailView.swift:toggleEditMode",
                    message: "commit_error",
                    data: ["recipeId": recipeId, "error": error.localizedDescription]
                )
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
            AgentSyncDebugLog.write(
                hypothesisId: "H6",
                location: "YDocRecipeDetailView.swift:toggleEditMode",
                message: "edit_mode_on",
                data: [
                    "recipeId": recipeId,
                    "titleLen": String(syncService.currentRecipe?.name.count ?? 0),
                ]
            )
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
            ShoppingFeedback.postStatus(String(localized: "shopping.no-items-to-add"))
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
    @ObservedObject var viewModel: RecipeEditViewModel
    let initialTitle: String
    @Binding var pickerColor: Color
    @Binding var dismissTitleKeyboard: Bool
    var commitTitleNonce: Int
    var onTitleBlur: (String) -> Void
    var onEditingActiveChanged: (Bool) -> Void

    private var titleUIFont: UIFont {
        AppTypography.uiFont(AppFonts.display, size: AppTypography.recipeTitleSize)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                RecipeTitleTextField(
                    initialText: initialTitle,
                    dismissKeyboard: $dismissTitleKeyboard,
                    commitTitleNonce: commitTitleNonce,
                    placeholder: String(localized: "edit.name.placeholder"),
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
                pickerColor = RecipeAccentColor.color(from: viewModel.draftColor)
            }
            .onChange(of: pickerColor) { _, newColor in
                viewModel.draftColor = RecipeAccentColor.storedValue(from: newColor)
            }
        }
    }
}


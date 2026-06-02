import SwiftUI

/// Recipe detail backed by Y.Doc via `YjsSyncService`.
struct YDocRecipeDetailView: View {
    let recipeId: String
    var startInEditMode: Bool = false
    var startDescriptionEdit: Bool = false

    @EnvironmentObject private var syncService: YjsSyncService
    @Environment(\.dismiss) private var dismiss
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

    private var recipe: RecipeData? {
        guard syncService.currentRecipe?.id == recipeId else { return nil }
        return syncService.currentRecipe
    }

    private var isLegacyReadOnly: Bool {
        guard let recipe else { return false }
        return !RecipeEditPolicy.canEdit(recipe: recipe)
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

    private var showsHeaderImage: Bool {
        headerImageUrl != nil
    }

    private var allowsImageNetworkRefresh: Bool {
        syncService.connectionState == .connected
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if showsHeaderImage, let headerImageUrl {
                    RecipeCachedImageView(
                        recipeId: recipeId,
                        imageUrl: headerImageUrl,
                        variant: .full,
                        allowsNetworkRefresh: allowsImageNetworkRefresh,
                        layoutAspectRatio: recipe?.imageAspectRatio.map { CGFloat($0) },
                        preservesAspectRatio: true,
                        maxHeight: 400
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 16) {
                    if isLoading && recipe == nil {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }

                    if isLegacyReadOnly {
                        RecipeLegacyBanner()
                    }

                    if isEditing, let editViewModel {
                        editHeader(editViewModel)
                    } else {
                        Text(recipe?.name ?? "")
                            .font(.custom(AppFonts.display, size: 28))
                            .lineLimit(nil)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }

                    if let recipe {
                        if isEditing {
                            RecipeEditToolbar(syncState: syncService.writeSyncState(for: recipeId))
                                .padding(.horizontal)
                        }

                        servingsBlock(recipe: recipe)

                        if isEditing, let editViewModel {
                            YDocIngredientsEditSection(
                                recipe: recipe,
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
                            StepsSection(htmlContent: description, accentColor: accentColor)
                                .id("recipe_instructions")
                        }

                        if let link = recipe.originalRecipeLink,
                           let url = URL(string: link) {
                            Link(destination: url) {
                                AppLabel.make("Original Recipe", symbol: "link")
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
        }
        #if DEBUG
        .onChange(of: recipe?.description) { _, description in
            guard description != nil,
                  DebugLaunchOptions.openRecipeId == recipeId else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeOut(duration: 0.25)) {
                    scrollProxy.scrollTo("recipe_instructions", anchor: .top)
                }
            }
        }
        #endif
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let recipe {
                    RecipeDetailActionsMenu(
                        recipeId: recipeId,
                        recipeName: recipe.name,
                        ingredients: recipe.ingredients,
                        isPublic: recipe.isPublic,
                        isEditing: isEditing,
                        isOnline: allowsImageNetworkRefresh
                    )
                    if !isEditing {
                        RecipeDetailShareButton(recipeId: recipeId)
                        ScreenAwakeToggle()
                    }
                }
                if canEnterEditMode {
                    Button {
                        Task { await toggleEditMode() }
                    } label: {
                        if isEditing {
                            Text(String(localized: "edit.done"))
                        } else {
                            AppLabel.make(String(localized: "edit.edit"), symbol: "pencil")
                        }
                    }
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
        .task(id: recipeId) {
            isLoading = true
            defer { isLoading = false }
            scaleFactor = RecipeScaleStorage.loadScaleFactor(recipeId: recipeId)
            syncService.acknowledgeRecipeRemoved()
            await syncService.loadRecipe(recipeId: recipeId)
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
        if isEditing, let editViewModel {
            ServingsStepperBindable(viewModel: editViewModel, accentColor: accentColor)
        } else {
            ServingsStepperView(
                servings: scaledServingsBinding(base: max(1, recipe.servings)),
                accentColor: accentColor
            )
        }
    }

    private func scaledServingsCount(base: Int) -> Int {
        let normalizedBase = max(1, base)
        return max(1, Int((Double(normalizedBase) * scaleFactor).rounded()))
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
    private func editHeader(_ vm: RecipeEditViewModel) -> some View {
        RecipeEditHeaderBindable(viewModel: vm, pickerColor: $pickerColor)
    }

    private func toggleEditMode() async {
        if isEditing {
            guard let recipe, let editViewModel else {
                isEditing = false
                return
            }
            guard !saveInFlight else { return }
            saveInFlight = true
            defer { saveInFlight = false }
            do {
                try await editViewModel.commit(against: recipe)
                isEditing = false
                if let updated = syncService.currentRecipe {
                    editViewModel.reset(from: updated)
                    pickerColor = RecipeAccentColor.color(from: updated.color)
                }
            } catch {
                editErrorMessage = error.localizedDescription
            }
        } else {
            if let recipe {
                let vm = RecipeEditViewModel(recipe: recipe, syncService: syncService)
                editViewModel = vm
                pickerColor = RecipeAccentColor.color(from: vm.draftColor)
            }
            isEditing = true
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

private struct ServingsStepperBindable: View {
    @ObservedObject var viewModel: RecipeEditViewModel
    let accentColor: Color

    var body: some View {
        ServingsStepperView(
            servings: Binding(
                get: { viewModel.draftServings },
                set: { viewModel.draftServings = max(1, min(99, $0)) }
            ),
            accentColor: accentColor
        )
    }
}

private struct RecipeEditHeaderBindable: View {
    @ObservedObject var viewModel: RecipeEditViewModel
    @Binding var pickerColor: Color
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                TextField(
                    String(localized: "edit.name.placeholder"),
                    text: Binding(
                        get: { viewModel.draftName },
                        set: { viewModel.draftName = $0 }
                    ),
                    axis: .vertical
                )
                    .font(.custom(AppFonts.display, size: 28))
                    .lineLimit(1...)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .focused($isNameFocused)
                    .submitLabel(.done)
                    .onSubmit { isNameFocused = false }

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


import SwiftUI

/// Recipe detail backed by Y.Doc via `YjsSyncService`.
struct YDocRecipeDetailView: View {
    let recipeId: String

    @EnvironmentObject private var syncService: YjsSyncService
    @Environment(\.dismiss) private var dismiss
    @State private var viewServings: Int = 1
    @State private var isLoading = false
    @State private var isEditing = false
    @State private var editViewModel: RecipeEditViewModel?
    @State private var editErrorMessage: String?
    @State private var pickerColor: Color = RecipeAccentColor.color(from: "oklch(0.65 0.25 270)")
    @State private var saveInFlight = false

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

    private var hasHeaderImage: Bool {
        guard let recipe else { return false }
        guard let imageUrl = recipe.imageUrl, !imageUrl.isEmpty else { return false }
        return true
    }

    private var allowsImageNetworkRefresh: Bool {
        syncService.connectionState == .connected
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if hasHeaderImage, let recipe {
                    RecipeCachedImageView(
                        recipeId: recipe.id,
                        imageUrl: recipe.imageUrl,
                        variant: .full,
                        allowsNetworkRefresh: allowsImageNetworkRefresh
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 250)
                    .clipped()
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
                                viewServings: max(1, editViewModel.draftServings),
                                accentColor: accentColor,
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
                                viewServings: viewServings,
                                accentColor: accentColor
                            )
                        }

                        if let description = recipe.description, !description.isEmpty {
                            StepsSection(htmlContent: description)
                        }

                        if !isEditing, let nutrition = recipe.nutrition {
                            NutritionSection(nutrition: nutrition)
                        }

                        if let link = recipe.originalRecipeLink,
                           let url = URL(string: link) {
                            Link(destination: url) {
                                Label("Original Recipe", systemImage: "link")
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if canEnterEditMode {
                    Button(isEditing ? String(localized: "edit.done") : String(localized: "edit.edit")) {
                        Task { await toggleEditMode() }
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
            syncService.acknowledgeRecipeRemoved()
            await syncService.loadRecipe(recipeId: recipeId)
            isLoading = false
        }
        .task(id: "\(recipeId)-\(recipe?.imageUrl ?? "")-\(allowsImageNetworkRefresh)") {
            guard let recipe, let imageUrl = recipe.imageUrl, !imageUrl.isEmpty else { return }
            await RecipeImageService.shared.prefetchFull(
                recipeId: recipeId,
                imageUrl: imageUrl,
                allowNetwork: allowsImageNetworkRefresh
            )
        }
        .onChange(of: recipe?.servings) { _, servings in
            if let servings, !isEditing {
                viewServings = max(1, servings)
            }
        }
        .onChange(of: recipe?.version) { _, _ in
            if isLegacyReadOnly, isEditing {
                isEditing = false
            }
        }
        .onChange(of: recipe?.id) { _, _ in
            if let recipe {
                let vm = RecipeEditViewModel(recipe: recipe, syncService: syncService)
                editViewModel = vm
                pickerColor = RecipeAccentColor.color(from: vm.draftColor)
                if !isEditing {
                    viewServings = max(1, recipe.servings)
                }
            }
        }
    }

    @ViewBuilder
    private func servingsBlock(recipe: RecipeData) -> some View {
        if isEditing, let editViewModel {
            ServingsStepperBindable(viewModel: editViewModel, accentColor: accentColor)
        } else {
            ServingsStepperView(
                servings: $viewServings,
                accentColor: accentColor
            )
        }
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
                viewServings = max(1, syncService.currentRecipe?.servings ?? recipe.servings)
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

private struct NutritionSection: View {
    let nutrition: NutritionData

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "nutrition.title"))
                .font(.custom(AppFonts.display, size: 22))
            if let calories = nutrition.calories {
                Text(String(format: String(localized: "nutrition.calories"), calories))
            }
            if let protein = nutrition.protein {
                Text(String(format: String(localized: "nutrition.protein"), protein))
            }
            if let fat = nutrition.fat {
                Text(String(format: String(localized: "nutrition.fat"), fat))
            }
            if let carbs = nutrition.carbs {
                Text(String(format: String(localized: "nutrition.carbs"), carbs))
            }
        }
        .font(.custom(AppFonts.sans, size: 17))
        .padding(.horizontal)
    }
}
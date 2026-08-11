//
//  DiscoverRecipeView.swift
//  RecipeScalerNative
//

import SwiftUI
import RecipeScalerCore

/// Read-only public recipe page (web `public-recipe.tsx` mobile layout).
///
/// Order: hero image → copy CTA → title → servings → ingredients → nutrition → steps.
/// Loads Yjs state via `GET /api/v2/recipes/public/{id}/state` and reuses the same
/// view-mode ingredient / description components as `YDocRecipeDetailView`.
struct DiscoverRecipeView: View {
    let recipeId: String
    var allowRecipeDownloads: Bool = true
    var imageSource: DiscoverRecipeImageSource = .curatedDiscover
    var returnContext: DiscoverRecipeReturnContext?

    @Environment(YjsSyncService.self) private var syncService
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @Environment(TimerManager.self) private var timerManager
    @Environment(\.apiClient) private var apiClient
    @Environment(\.discoverListState) private var discoverListState
    @AppStorage(NutritionSettings.globalEnabledKey) private var showNutritionGlobal = true
    @State private var model: DiscoverRecipeModel?
    @State private var scaleFactor: Double = 1
    @State private var nutritionViewMode: IngredientNutritionViewMode = NutritionViewModeStorage.load()
    @State private var descriptionTimerPopover: DescriptionTimerPopoverState?

    private var accentColor: Color {
        if case .loaded(let recipe) = model?.state {
            return RecipeAccentColor.color(from: recipe.color)
        }
        return RecipeAccentColor.color(from: "")
    }

    private var loadedRecipe: RecipeData? {
        if case .loaded(let recipe) = model?.state { return recipe }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let recipe = loadedRecipe {
                    hero(for: recipe)

                    VStack(alignment: .leading, spacing: 16) {
                        if allowRecipeDownloads {
                            cloneButton
                                .padding(.horizontal, RecipeRowLayoutMetrics.listHorizontalInset)
                        }

                        titleBlock(for: recipe)

                        if recipe.servings > 0 {
                            ServingsStepperView(
                                servings: scaledServingsBinding(base: max(1, recipe.servings)),
                                accentColor: accentColor
                            )
                        }

                        YDocIngredientsSection(
                            ingredients: recipe.ingredients,
                            baseServings: max(1, recipe.servings),
                            viewServings: scaledServingsCount(base: max(1, recipe.servings)),
                            accentColor: accentColor,
                            onScaledQuantityEdited: { ingredient, text in
                                applyViewModeScaledQuantityEdit(ingredient: ingredient, text: text)
                            },
                            nutritionEnabled: showNutritionGlobal,
                            nutritionViewMode: nutritionViewMode
                        )

                        if showNutritionGlobal,
                           RecipeNutritionDisplay.effectiveMacros(from: recipe) != nil {
                            nutritionBlock(recipe: recipe)
                        }

                        if let description = recipe.description, !description.isEmpty {
                            StepsSection(
                                htmlContent: description,
                                accentColor: accentColor,
                                recipeId: recipeId,
                                timerPopover: $descriptionTimerPopover
                            )
                            .id("discover_recipe_instructions")
                        }
                    }
                    .padding(.top, RecipeDetailLayoutMetrics.titleTopSpacing)
                    .recipeDetailColumnWidth
                } else if case .loading = model?.state {
                    ProgressView(Bundle.currentLocalizedString("discover.recipe.loading"))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if case .failed(let loadError) = model?.state {
                    ContentUnavailableView {
                        AppEmptyState.label("discover.recipe.failed", symbol: "exclamationmark.triangle")
                    } description: {
                        Text(loadError).appBody()
                    }
                    .padding(.horizontal, RecipeRowLayoutMetrics.listHorizontalInset)
                } else {
                    ProgressView(Bundle.currentLocalizedString("discover.recipe.loading"))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                }
            }
            .mobileTimerPanelBottomPadding()
        }
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(loadedRecipe?.name.isEmpty == false ? (loadedRecipe?.name ?? "") : "")
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
        .task {
            if model == nil {
                model = DiscoverRecipeModel(api: apiClient)
            }
            if let returnContext {
                discoverListState?.recordAnchor(
                    recipeID: returnContext.recipeID,
                    for: returnContext.scope
                )
            }
            await model?.load(recipeId: recipeId)
        }
    }

    @ViewBuilder
    private func hero(for recipe: RecipeData) -> some View {
        if recipe.imageUrl?.isEmpty == false,
           let imageURL = model?.detailImageURL(recipeId: recipe.id, imageSource: imageSource) {
            PublicCachedImageView(
                url: imageURL,
                allowsNetworkRefresh: true,
                layoutAspectRatio: recipe.imageAspectRatio.map { CGFloat($0) },
                fullWidthHero: true,
                maxHeight: 400
            )
        }
    }

    @ViewBuilder
    private func titleBlock(for recipe: RecipeData) -> some View {
        Text(recipe.name.isEmpty
             ? Bundle.currentLocalizedString("recipes.no-title")
             : recipe.name)
            .font(AppTypography.display(AppTypography.recipeTitleSize))
            .lineLimit(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, RecipeRowLayoutMetrics.listHorizontalInset)
    }

    private func nutritionBlock(recipe: RecipeData) -> some View {
        RecipeNutritionBlockView(
            recipe: recipe,
            baseServings: max(1, recipe.servings),
            scaleFactor: scaleFactor,
            accentColor: accentColor,
            isOnline: syncService.connectionState.isConnected,
            onRecalculate: nil,
            viewMode: $nutritionViewMode
        )
    }

    @ViewBuilder
    private var cloneButton: some View {
        if case .failed(let message) = cloneState {
            VStack(alignment: .leading, spacing: 4) {
                cloneActionButton
                Text(message)
                    .appFootnote()
                    .foregroundStyle(.red)
            }
        } else {
            cloneActionButton
        }
    }

    private var cloneState: DiscoverRecipeModel.CloneState {
        model?.cloneState ?? .idle
    }

    private var cloneActionButton: some View {
        Button {
            switch cloneState {
            case .idle, .failed:
                Task {
                    await model?.clone(
                        recipeId: recipeId,
                        fallbackImageUrl: loadedRecipe?.imageUrl,
                        syncService: syncService
                    )
                }
            case .done(let newRecipeId):
                deepLinkRouter.handle(.openRecipe(recipeId: newRecipeId))
            case .copying:
                break
            }
        } label: {
            HStack(spacing: 6) {
                Group {
                    if case .copying = cloneState {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: cloneButtonIconName)
                    }
                }
                .frame(width: 20, height: 20)

                Text(cloneButtonTitleKey)
            }
            .frame(minHeight: 22)
        }
        .buttonStyle(.bordered)
        .disabled(cloneState == .copying)
        .accessibilityIdentifier(AccessibilityIdentifiers.discoverRecipeCloneButton)
    }

    private var cloneButtonIconName: String {
        switch cloneState {
        case .done:
            return "checkmark"
        case .idle, .copying, .failed:
            return "arrow.down.to.line"
        }
    }

    private var cloneButtonTitleKey: LocalizedStringKey {
        switch cloneState {
        case .idle, .failed:
            return "discover.recipe.copy-to-me"
        case .copying:
            return "discover.recipe.copying"
        case .done:
            return "discover.recipe.open-in-my-recipes"
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
                scaleFactor = max(
                    1.0 / Double(normalizedBase),
                    Double(max(1, newValue)) / Double(normalizedBase)
                )
            }
        )
    }

    private func applyViewModeScaledQuantityEdit(ingredient: IngredientData, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let scaled = Double(normalized), scaled > 0, scaled.isFinite else { return }
        guard let original = ingredient.numericValue, original > 0 else { return }
        scaleFactor = scaled / original
    }

    private func startDescriptionTimer(from reference: RecipeDescriptionTimerReference) {
        guard reference.isStartable else { return }
        _ = timerManager.createAndStartTimer(
            name: reference.resolvedName,
            duration: TimeInterval(reference.durationSeconds),
            type: reference.type,
            recipeId: recipeId,
            recipeDisplayName: loadedRecipe?.name
        )
    }
}

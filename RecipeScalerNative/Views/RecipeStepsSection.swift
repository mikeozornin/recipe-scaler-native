//
//  RecipeStepsSection.swift
//  RecipeScalerNative
//
//  Extracted from the legacy `RecipeDetailView` so the Y.Doc-backed detail
//  views (`YDocRecipeDetailView`, `DiscoverRecipeView`, `DescriptionEditorView`,
//  `DescriptionFixturePreviewView`) can reuse `StepsSection` and the related
//  ingredient/scale controls without pulling in the unreachable SwiftData
//  `Recipe` model.
//

import SwiftUI
import RecipeScalerCore

// MARK: - Scale Factor Control

struct ScaleFactorControl: View {
    @Binding var scaleFactor: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Scale")
                    .font(AppTypography.bodySemibold)

                Spacer()

                Text("\(scaleFactor, specifier: "%.1f")×")
                    .font(AppTypography.title3)
            }

            HStack(spacing: 12) {
                Button {
                    withAnimation {
                        scaleFactor = max(0.25, scaleFactor - 0.25)
                    }
                } label: {
                    AppSymbol.image("minus")
                        .font(AppTypography.sans(AppTypography.title2Size))
                }
                .disabled(scaleFactor <= 0.25)
                .accessibilityIdentifier(AccessibilityIdentifiers.scaleMinusButton)

                Slider(value: $scaleFactor, in: 0.25...10, step: 0.25)
                    .accessibilityIdentifier(AccessibilityIdentifiers.scaleSlider)

                Button {
                    withAnimation {
                        scaleFactor = min(10, scaleFactor + 0.25)
                    }
                } label: {
                    AppSymbol.image("plus")
                        .font(AppTypography.sans(AppTypography.title2Size))
                }
                .disabled(scaleFactor >= 10)
                .accessibilityIdentifier(AccessibilityIdentifiers.scalePlusButton)
            }
            .buttonStyle(.borderless)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Ingredients Section

struct IngredientsSection: View {
    let ingredients: [DisplayIngredient]
    let scaleFactor: Double

    var sortedIngredients: [DisplayIngredient] {
        ingredients.sorted { $0.order < $1.order }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ingredients")
                .font(AppTypography.title2)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(sortedIngredients) { ingredient in
                    IngredientRow(
                        ingredient: ingredient,
                        scaleFactor: scaleFactor
                    )
                }
            }
            .padding(.horizontal)
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.ingredientsSection)
    }
}

// MARK: - Ingredient Row

struct IngredientRow: View {
    let ingredient: DisplayIngredient
    let scaleFactor: Double

    var scaledAmount: String {
        if let amountDisplay = ingredient.amountDisplay, !amountDisplay.isEmpty {
            return amountDisplay
        }
        guard let amount = ingredient.originalAmount else {
            return ""
        }
        let scaled = amount * scaleFactor
        return formatNumber(scaled)
    }

    var isScaled: Bool {
        abs(scaleFactor - 1.0) > 0.01
    }

    var body: some View {
        if ingredient.isSeparator {
            Text(ingredient.name)
                .font(AppTypography.sansMedium(AppTypography.subheadlineSize))
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        } else {
            HStack(alignment: .top) {
                HStack(spacing: 4) {
                    if !scaledAmount.isEmpty {
                        Text(scaledAmount)
                            .font(AppTypography.bodySemibold)
                            .foregroundStyle(isScaled ? .blue : .primary)

                        if !ingredient.unit.isEmpty {
                            Text(ingredient.unit)
                                .font(AppTypography.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 80, alignment: .leading)

                Text(ingredient.name)
                    .font(AppTypography.body)
                    .lineLimit(nil)

                Spacer()
            }
            .padding(.vertical, 2)
        }
    }

    private func formatNumber(_ value: Double) -> String {
        AppNumberFormat.string(value, maximumFractionDigits: 2)
    }
}

// MARK: - Steps Section

struct StepsSection: View {
    let htmlContent: String
    var accentColor: Color = RecipeAccentColor.color(from: "oklch(0.65 0.25 270)")
    var recipeId: String?
    var cookingRecipe: RecipeData?
    var scaleFactor: Double = 1
    var restoreAwakeOnDismiss: Bool = false
    var allowsRebuild: Bool = false
    var syncService: YjsSyncService? = nil
    @Binding var timerPopover: DescriptionTimerPopoverState?

    @Environment(TimerManager.self) private var timerManager
    @Environment(\.appContainer) private var container
    @State private var document: RecipeDescriptionDocument?

    init(
        htmlContent: String,
        accentColor: Color = RecipeAccentColor.color(from: "oklch(0.65 0.25 270)"),
        recipeId: String? = nil,
        cookingRecipe: RecipeData? = nil,
        scaleFactor: Double = 1,
        restoreAwakeOnDismiss: Bool = false,
        allowsRebuild: Bool = false,
        syncService: YjsSyncService? = nil,
        timerPopover: Binding<DescriptionTimerPopoverState?> = .constant(nil)
    ) {
        self.htmlContent = htmlContent
        self.accentColor = accentColor
        self.recipeId = recipeId
        self.cookingRecipe = cookingRecipe
        self.scaleFactor = scaleFactor
        self.restoreAwakeOnDismiss = restoreAwakeOnDismiss
        self.allowsRebuild = allowsRebuild
        self.syncService = syncService
        _timerPopover = timerPopover
    }

    private var canStartCooking: Bool {
        ProcessTableClassicChrome.canStartCooking(cookingRecipe)
    }

    private var showsMissingBanner: Bool {
        ProcessTableClassicChrome.showsMissingBanner(
            allowsRebuild: allowsRebuild,
            recipe: cookingRecipe
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: ProcessTableLayout.stepsHeaderToCtaGap) {
                Text("Instructions")
                    .font(AppTypography.title2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if canStartCooking {
                    ProcessTableStartButton {
                        presentCookingCover()
                    }
                }
            }
            .frame(minHeight: ProcessTableLayout.ctaMinHit)
            .padding(.horizontal)

            if showsMissingBanner, let recipeId {
                ProcessTableMissingCardBanner(
                    recipeId: recipeId,
                    syncService: syncService
                )
                .padding(.horizontal)
            }

            if let document {
                RecipeDescriptionView(
                    document: document,
                    accentColor: accentColor,
                    onTimerTap: { reference, anchor in
                        timerPopover = DescriptionTimerPopoverState(reference: reference, anchor: anchor)
                    }
                )
                .padding(.horizontal)
            }
        }
        .padding(.bottom, RecipeDetailLayoutMetrics.descriptionBottomPadding)
        .accessibilityIdentifier(AccessibilityIdentifiers.stepsSection)
        .task(id: htmlContent) {
            document = RecipeDescriptionParser.parse(htmlContent)
        }
        .onDisappear {
            if container?.cooking.presentation == nil {
                container?.processTableRebuild.cancel()
            }
        }
    }

    private func presentCookingCover() {
        guard let cookingRecipe else { return }
        container?.cooking.present(
            recipe: cookingRecipe,
            scaleFactor: scaleFactor,
            allowsRebuild: allowsRebuild,
            restoreAwakeOnDismiss: restoreAwakeOnDismiss
        )
    }

    private func startTimer(from reference: RecipeDescriptionTimerReference) {
        guard reference.isStartable else { return }
        _ = timerManager.createAndStartTimer(
            name: reference.resolvedName,
            duration: TimeInterval(reference.durationSeconds),
            type: reference.type,
            recipeId: recipeId
        )
    }
}

/// Rebuild environment lives here so `StepsSection` previews/fixtures without
/// `appEnvironment` do not crash: the child is only in the tree when missing.
private struct ProcessTableMissingCardBanner: View {
    let recipeId: String
    var syncService: YjsSyncService?

    @Environment(ProcessTableRebuildModel.self) private var processTableRebuild

    private var isOnline: Bool {
        syncService?.connectionState.isConnected ?? false
    }

    var body: some View {
        ProcessTableStatusBanner(
            kind: .missing,
            canRecalculate: isOnline,
            isOnline: isOnline,
            isRebuilding: processTableRebuild.isRebuilding,
            onRecalculate: {
                processTableRebuild.rebuild(
                    recipeId: recipeId,
                    userId: syncService?.currentUserId,
                    syncService: syncService
                )
            }
        )
    }
}


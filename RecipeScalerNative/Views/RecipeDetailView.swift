//
//  RecipeDetailView.swift
//  RecipeScalerNative
//
//

import SwiftUI
import Foundation
import UIKit

// Simple struct for displaying ingredients (not SwiftData model)
struct DisplayIngredient: Identifiable {
    let id: String
    let name: String
    let originalAmount: Double?
    let unit: String
    let order: Int
    let isSeparator: Bool
    /// Preformatted amount for Y.Doc rows (e.g. `"200 g"`); when set, shown instead of numeric scaling.
    var amountDisplay: String? = nil
}

struct RecipeDetailView: View {
    let recipe: Recipe
    private let autoLoad: Bool

    @Environment(\.modelContext) private var modelContext

    @State private var scaleFactor: Double
    @State private var showingScaleSheet = false
    @State private var loadedIngredients: [DisplayIngredient] = []
    @State private var loadedDescription: String?
    @State private var loadedImageUrl: String?
    @State private var loadedName: String?

    @State private var isLoading = false
    @State private var loadError: String?
    @State private var scaleReloadTask: Task<Void, Never>?

    init(recipe: Recipe, autoLoad: Bool = true) {
        self.recipe = recipe
        _scaleFactor = State(initialValue: recipe.scaleFactor)
        self.autoLoad = autoLoad
    }

    private var displayIngredients: [DisplayIngredient] {
        if !loadedIngredients.isEmpty {
            return loadedIngredients
        }
        // Fallback to recipe ingredients
        return recipe.ingredients.map { ing in
            DisplayIngredient(
                id: ing.id,
                name: ing.name,
                originalAmount: ing.originalAmount,
                unit: ing.unit,
                order: ing.order,
                isSeparator: ing.isSeparator
            )
        }
    }

    private var displayDescription: String? {
        loadedDescription ?? recipe.detailHtml ?? recipe.recipeDescription
    }

    private var displayName: String {
        loadedName ?? recipe.name
    }



    private var headerImageURL: URL? {
        if let loadedImageUrl, !loadedImageUrl.isEmpty {
            if let url = URL(string: loadedImageUrl), url.scheme != nil {
                return url
            }
        }
        if let recipeImageUrl = recipe.imageUrl, !recipeImageUrl.isEmpty {
            return APIClient.shared.recipeImageURL(id: recipe.id, preview: false)
        }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Image
                if let localPath = recipe.imageLocalPath,
                   let uiImage = UIImage(contentsOfFile: localPath) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 400, alignment: .leading)
                } else if let imageUrl = headerImageURL {
                    AsyncImage(url: imageUrl) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: 400, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 16) {
                    // Recipe title (wraps instead of truncating)
                    Text(displayName)
                        .font(AppTypography.display(AppTypography.recipeTitleSize))
                        .lineLimit(nil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    // Error message
                    if let error = loadError {
                        Text("Error: \(error)")
                            .font(AppTypography.body)
                            .foregroundColor(.red)
                            .padding()
                    }

                    // Scale Factor Control
                    ScaleFactorControl(scaleFactor: $scaleFactor)
                        .padding(.horizontal)

                    // Ingredients Section
                    if !displayIngredients.isEmpty {
                        IngredientsSection(
                            ingredients: displayIngredients,
                            scaleFactor: scaleFactor
                        )
                    } else if !isLoading {
                        Text("No ingredients")
                            .font(AppTypography.body)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }

                    // Description/Steps Section
                    if let description = displayDescription,
                       !description.isEmpty {
                        StepsSection(htmlContent: description)
                    }

                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard autoLoad else { return }
            await loadFullRecipe(scaleFactor: scaleFactor, showLoading: true)
        }
        .onChange(of: scaleFactor) { _, newValue in
            scaleReloadTask?.cancel()
            scaleReloadTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if Task.isCancelled { return }
                guard autoLoad else { return }
                await loadFullRecipe(scaleFactor: newValue, showLoading: false)
            }
        }
    }

    /// Populate loaded* state from recipe model so UI shows cached data (offline / 304).
    @MainActor
    private func fillLoadedFromRecipe() {
        loadedName = recipe.name
        loadedDescription = recipe.detailHtml ?? recipe.recipeDescription

        if let url = recipe.imageUrl, !url.isEmpty {
            loadedImageUrl = url
        }
        loadedIngredients = recipe.ingredients.map { ing in
            DisplayIngredient(
                id: ing.id,
                name: ing.name,
                originalAmount: ing.originalAmount,
                unit: ing.unit,
                order: ing.order,
                isSeparator: ing.isSeparator
            )
        }
    }

    @MainActor
    private func loadFullRecipe(scaleFactor: Double, showLoading: Bool) async {
        if showLoading {
            isLoading = true
        }
        loadError = nil
        fillLoadedFromRecipe()
        if showLoading {
            isLoading = false
        }
        _ = scaleFactor
    }

    private func cacheFullImageIfNeeded(recipeId: String) async {
        guard recipe.imageUrl?.isEmpty == false else { return }
        guard let remoteURL = APIClient.shared.recipeImageURL(id: recipeId, preview: false) else { return }
        let existingEtag = recipe.imageEtag
        let existingLastModified = recipe.imageLastModified

        do {
            let request = APIClient.shared.recipeImageDownloadRequest(
                remoteURL: remoteURL,
                etag: existingEtag,
                lastModified: existingLastModified
            )
            let result = try await ImageCacheService.shared.fetchAndCache(
                recipeId: recipeId,
                variant: .full,
                request: request
            )

            await MainActor.run {
                recipe.imageLocalPath = result.localURL.path
                recipe.imageEtag = result.etag
                recipe.imageLastModified = result.lastModified
                do {
                    try modelContext.save()
                } catch {
                    print("Failed to save image cache: \(error)")
                }
            }
        } catch {
            // Ignore full image cache errors to avoid blocking detail view
        }
    }
}

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
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - Steps Section
struct StepsSection: View {
    let htmlContent: String
    var accentColor: Color = RecipeAccentColor.color(from: "oklch(0.65 0.25 270)")
    var recipeId: String?
    @Binding var timerPopover: DescriptionTimerPopoverState?

    @EnvironmentObject private var timerManager: TimerManager
    @State private var document: RecipeDescriptionDocument?

    init(
        htmlContent: String,
        accentColor: Color = RecipeAccentColor.color(from: "oklch(0.65 0.25 270)"),
        recipeId: String? = nil,
        timerPopover: Binding<DescriptionTimerPopoverState?> = .constant(nil)
    ) {
        self.htmlContent = htmlContent
        self.accentColor = accentColor
        self.recipeId = recipeId
        _timerPopover = timerPopover
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Instructions")
                .font(AppTypography.title2)
                .padding(.horizontal)

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
        .accessibilityIdentifier(AccessibilityIdentifiers.stepsSection)
        .task(id: htmlContent) {
            document = RecipeDescriptionParser.parse(htmlContent)
        }
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

// MARK: - Preview
#Preview {
    NavigationStack {
        RecipeDetailView(
            recipe: Recipe(
                name: "Test Recipe",
                recipeDescription: "Test description"
            )
        )
    }
}

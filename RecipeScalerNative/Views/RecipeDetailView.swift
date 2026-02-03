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
    @State private var loadedOriginalRecipeLink: String?
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

    private var displayOriginalLink: String? {
        loadedOriginalRecipeLink ?? recipe.originalRecipeLink
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
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 250)
                        .clipped()
                } else if let imageUrl = headerImageURL {
                    AsyncImage(url: imageUrl) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 250)
                    .clipped()
                }

                VStack(alignment: .leading, spacing: 16) {
                    // Recipe title (wraps instead of truncating)
                    Text(displayName)
                        .font(.custom(AppFonts.display, size: 28))
                        .lineLimit(nil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    // Error message
                    if let error = loadError {
                        Text("Error: \(error)")
                            .font(.custom(AppFonts.sans, size: 17))
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
                            .font(.custom(AppFonts.sans, size: 17))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }

                    // Description/Steps Section
                    if let description = displayDescription,
                       !description.isEmpty {
                        StepsSection(htmlContent: description)
                    }

                    // Original Recipe Link
                    if let link = displayOriginalLink,
                       let url = URL(string: link) {
                        Link(destination: url) {
                            Label("Original Recipe", systemImage: "link")
                        }
                        .padding(.horizontal)
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
        loadedOriginalRecipeLink = recipe.originalRecipeLink
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
        let hasCachedContent = !(recipe.detailHtml?.isEmpty ?? true) || !recipe.ingredients.isEmpty
        if hasCachedContent {
            fillLoadedFromRecipe()
        }

        // Only send ETag when requesting the same scale factor we cached (server ETag is per scale)
        let useCachedEtag = abs(scaleFactor - (recipe.detailScaleFactor ?? 1.0)) < 0.01
        let etag = useCachedEtag ? recipe.detailEtag : nil
        let lastModified = useCachedEtag ? recipe.detailLastModified : nil

        do {
            let response = try await APIClient.shared.fetchRecipeFullCached(
                id: recipe.id,
                scaleFactor: scaleFactor,
                etag: etag,
                lastModified: lastModified
            )

            if response.statusCode == 304 {
                // Cache is valid; displayName/displayIngredients already use recipe.* when loaded* are empty
                if showLoading {
                    isLoading = false
                }
                return
            }

            guard let fullRecipe = response.data else {
                throw APIError.serverError(message: "Missing recipe data")
            }

            // Convert IngredientFullDTO to DisplayIngredient
            loadedIngredients = fullRecipe.ingredients.enumerated().map { index, dto in
                DisplayIngredient(
                    id: dto.id,
                    name: dto.name,
                    originalAmount: dto.originalAmount,
                    unit: dto.unit,
                    order: index,
                    isSeparator: dto.isSeparator ?? false
                )
            }

            loadedDescription = fullRecipe.text
            loadedImageUrl = fullRecipe.imageUrl
            loadedName = fullRecipe.name
            loadedOriginalRecipeLink = fullRecipe.originalRecipeLink

            updateRecipeCache(
                fullRecipe: fullRecipe,
                scaleFactor: scaleFactor,
                etag: response.etag,
                lastModified: response.lastModified
            )

            await cacheFullImageIfNeeded(recipeId: recipe.id)

            if showLoading {
                isLoading = false
            }
        } catch {
            if hasCachedContent {
                fillLoadedFromRecipe()
            } else {
                loadError = error.localizedDescription
            }
            if showLoading {
                isLoading = false
            }
            print("Error loading full recipe: \(error)")
        }
    }

    @MainActor
    private func updateRecipeCache(
        fullRecipe: RecipeFullDTO,
        scaleFactor: Double,
        etag: String?,
        lastModified: String?
    ) {
        // Update basic fields
        recipe.name = fullRecipe.name
        recipe.detailHtml = fullRecipe.text
        recipe.detailScaleFactor = scaleFactor
        recipe.detailEtag = etag
        recipe.detailLastModified = lastModified
        recipe.detailFetchedAt = Date()
        if let imageUrl = fullRecipe.imageUrl, !imageUrl.isEmpty {
            if recipe.imageUrl != imageUrl {
                recipe.imageLocalPath = nil
                recipe.imageEtag = nil
                recipe.imageLastModified = nil
            }
            recipe.imageUrl = imageUrl
        } else {
            recipe.imageUrl = nil
            recipe.imageLocalPath = nil
            recipe.imageEtag = nil
            recipe.imageLastModified = nil
        }
        recipe.originalRecipeLink = fullRecipe.originalRecipeLink

        // Replace ingredients
        for existing in recipe.ingredients {
            modelContext.delete(existing)
        }
        let newIngredients = fullRecipe.ingredients.enumerated().map { index, dto in
            Ingredient(
                id: dto.id,
                name: dto.name,
                originalAmount: dto.originalAmount,
                unit: dto.unit,
                order: index,
                isSeparator: dto.isSeparator ?? false
            )
        }
        recipe.ingredients = newIngredients

        do {
            try modelContext.save()
        } catch {
            print("Failed to save recipe cache: \(error)")
        }
    }

    private func cacheFullImageIfNeeded(recipeId: String) async {
        guard recipe.imageUrl?.isEmpty == false else { return }
        guard let remoteURL = APIClient.shared.recipeImageURL(id: recipeId, preview: false) else { return }
        let existingEtag = recipe.imageEtag
        let existingLastModified = recipe.imageLastModified

        do {
            let result = try await ImageCacheService.shared.fetchAndCache(
                recipeId: recipeId,
                variant: .full,
                remoteURL: remoteURL,
                etag: existingEtag,
                lastModified: existingLastModified
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
                    .font(.custom(AppFonts.sansMedium, size: 17))

                Spacer()

                Text("\(scaleFactor, specifier: "%.1f")×")
                    .font(.custom(AppFonts.sansMedium, size: 20))
            }

            HStack(spacing: 12) {
                Button {
                    withAnimation {
                        scaleFactor = max(0.25, scaleFactor - 0.25)
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.custom(AppFonts.sans, size: 22))
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
                    Image(systemName: "plus.circle.fill")
                        .font(.custom(AppFonts.sans, size: 22))
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
                .font(.custom(AppFonts.display, size: 22))
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
                .font(.custom(AppFonts.sansMedium, size: 15))
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        } else {
            HStack(alignment: .top) {
                HStack(spacing: 4) {
                    if !scaledAmount.isEmpty {
                        Text(scaledAmount)
                            .font(.custom(AppFonts.sansMedium, size: 17))
                            .foregroundStyle(isScaled ? .blue : .primary)

                        if !ingredient.unit.isEmpty {
                            Text(ingredient.unit)
                                .font(.custom(AppFonts.sans, size: 17))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 80, alignment: .leading)

                Text(ingredient.name)
                    .font(.custom(AppFonts.sans, size: 17))
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

    private var attributedContent: AttributedString {
        guard let data = htmlContent.data(using: .utf8) else {
            return AttributedString(htmlContent)
        }

        if let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) {
            var result = AttributedString(attributed)
            result.font = .custom(AppFonts.sans, size: 17)
            return result
        }

        return AttributedString(htmlContent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Instructions")
                .font(.custom(AppFonts.display, size: 22))
                .padding(.horizontal)

            Text(attributedContent)
                .padding(.horizontal)
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.stepsSection)
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

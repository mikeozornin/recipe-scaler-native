//
//  DiscoverRecipeView.swift
//  RecipeScalerNative
//

import SwiftUI
import RecipeScalerCore

/// Read-only view of a public recipe: hero image, prep/cook/servings badges,
/// read-only ingredients block with servings scaler, HTML description, and
/// "Copy to my recipes" CTA that clones via the v2 copy endpoint and routes
/// the user to the cloned recipe in My Recipes.
struct DiscoverRecipeView: View {
    let recipeId: String

    @EnvironmentObject private var syncService: YjsSyncService
    @Environment(\.locale) private var locale
    @State private var recipe: RecipeData?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var scaleFactor: Double = 1
    @State private var cloneState: CloneState = .idle

    @MainActor
    private enum CloneState: Equatable {
        case idle
        case copying
        case done(newRecipeId: String)
        case failed(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let recipe {
                    hero(for: recipe)
                    header(for: recipe)
                    ingredientsBlock(for: recipe)
                    if let description = recipe.description, !description.isEmpty {
                        descriptionBlock(description)
                    }
                    cloneButton
                        .padding(.top, 8)
                } else if isLoading {
                    ProgressView(Bundle.currentLocalizedString("discover.loading"))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if let loadError {
                    ContentUnavailableView {
                        AppLabel.make("discover.recipe.failed", symbol: "exclamationmark.triangle")
                    } description: {
                        Text(loadError).appBody()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .task { await load() }
    }

    @ViewBuilder
    private func hero(for recipe: RecipeData) -> some View {
        let imageURL = DiscoverAPI.recipeImageURL(recipeId: recipe.id, preview: false)
        AsyncImage(url: imageURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            case .failure, .empty:
                placeholderHero(color: RecipeAccentColor.color(from: recipe.color))
            @unknown default:
                placeholderHero(color: RecipeAccentColor.color(from: recipe.color))
            }
        }
    }

    private func placeholderHero(color: Color) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(color.opacity(0.15))
            .frame(height: 220)
            .overlay(
                AppSymbol.image("photo")
                    .font(.system(size: 36, weight: .regular))
                    .foregroundStyle(.secondary)
            )
    }

    @ViewBuilder
    private func header(for recipe: RecipeData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recipe.name.isEmpty
                 ? Bundle.currentLocalizedString("recipes.no-title")
                 : recipe.name)
                .font(AppTypography.display(24))
                .foregroundStyle(.primary)
            HStack(spacing: 8) {
                if recipe.servings > 0 {
                    servingsPill(servings: recipe.servings)
                }
            }
        }
    }

    private func servingsPill(servings: Int) -> some View {
        VStack(spacing: 2) {
            Text(Bundle.currentLocalizedString("discover.recipe.servings"))
                .font(AppTypography.footnote)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text("\(Int((Double(servings) * scaleFactor).rounded()))")
                .font(AppTypography.subheadlineSemibold)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private func ingredientsBlock(for recipe: RecipeData) -> some View {
        let displayIngredients = recipe.ingredients.filter { !$0.isSeparator }
        if !displayIngredients.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("discover.recipe.ingredients")
                        .appHeadline()
                    Spacer()
                    if recipe.servings > 0 {
                        Stepper(
                            value: $scaleFactor,
                            in: 0.25...50,
                            step: 1
                        ) {
                            EmptyView()
                        }
                        .labelsHidden()
                    }
                }
                ForEach(displayIngredients) { ingredient in
                    ingredientRow(ingredient)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func ingredientRow(_ ingredient: IngredientData) -> some View {
        let scaledAmount = scaledAmountText(ingredient)
        return HStack(alignment: .firstTextBaseline) {
            Text(ingredient.name)
                .appBody()
                .foregroundStyle(.primary)
            Spacer()
            if !scaledAmount.isEmpty {
                Text(scaledAmount)
                    .appBody()
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
            if !ingredient.unit.isEmpty {
                Text(ingredient.unit)
                    .appFootnote()
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
        .padding(.vertical, 4)
    }

    /// Render the scaled amount using the ingredient's numeric `originalAmount`
    /// (the Yjs map value) times `scaleFactor`. String `amount` is used as a
    /// fallback when no numeric value is available.
    private func scaledAmountText(_ ingredient: IngredientData) -> String {
        if let original = Double(ingredient.originalAmount) {
            let scaled = original * scaleFactor
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 2
            formatter.locale = locale
            return formatter.string(from: NSNumber(value: scaled)) ?? "\(scaled)"
        }
        return ingredient.amount
    }

    @ViewBuilder
    private func descriptionBlock(_ html: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("discover.recipe.steps")
                .appHeadline()
            Text(attributedDescription(html))
                .appBody()
        }
        .padding(.vertical, 8)
    }

    private func attributedDescription(_ html: String) -> AttributedString {
        let cleaned = DiscoverDescriptionText.htmlToPlainText(html)
        if let attr = try? AttributedString(markdown: cleaned) {
            return attr
        }
        return AttributedString(cleaned)
    }

    @ViewBuilder
    private var cloneButton: some View {
        switch cloneState {
        case .idle:
            Button {
                Task { await clone() }
            } label: {
                Label("discover.recipe.copy-to-me", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(AccessibilityIdentifiers.discoverRecipeCloneButton)
        case .copying:
            Button {
                // no-op — in-flight
            } label: {
                HStack(spacing: 6) {
                    ProgressView()
                    Text("discover.recipe.copying")
                }
            }
            .buttonStyle(.bordered)
            .disabled(true)
        case .done(let newRecipeId):
            Button {
                DeepLinkRouter.shared.handle(.openRecipe(recipeId: newRecipeId))
            } label: {
                Label("discover.recipe.open-in-my-recipes", systemImage: "checkmark")
            }
            .buttonStyle(.bordered)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    Task { await clone() }
                } label: {
                    Label("discover.recipe.copy-to-me", systemImage: "arrow.down.to.line")
                }
                .buttonStyle(.borderedProminent)
                Text(message)
                    .appFootnote()
                    .foregroundStyle(.red)
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let state = try await DiscoverAPI.fetchPublicRecipeState(id: recipeId)
            // Prefer the Yjs state (canonical source of ingredients + description).
            // Fall back to top-level metadata if yjsState is missing/empty.
            if let bytes = state.yjsState, !bytes.isEmpty {
                let data = Data(bytes.map { UInt8(truncatingIfNeeded: $0) })
                if let parsed = await RecipeReader.parse(state: data, recipeId: recipeId) {
                    recipe = parsed
                    return
                }
            }
            // No Yjs state — synthesize a minimal recipe from top-level metadata.
            recipe = RecipeData(
                id: state.id,
                name: state.name ?? "",
                servings: 0,
                color: state.color ?? "#3b82f6",
                version: "v1",
                description: nil,
                ingredients: [],
                nutrition: nil,
                isPublic: false,
                hasSteps: false,
                createdAt: "",
                updatedAt: "",
                imageUrl: state.imageUrl,
                imageAspectRatio: nil,
                originalRecipeLink: nil,
                originalRecipe: nil
            )
        } catch {
            loadError = error.localizedDescription
        }
    }

    @MainActor
    private func clone() async {
        cloneState = .copying
        do {
            let newId = try await DiscoverAPI.copyRecipe(id: recipeId)
            await syncService.loadRecipe(recipeId: newId)
            cloneState = .done(newRecipeId: newId)
            ShoppingFeedback.postStatus(
                Bundle.currentLocalizedString("discover.recipe.copied")
            )
        } catch {
            cloneState = .failed(error.localizedDescription)
        }
    }
}

/// Naive HTML → plain text conversion for curated recipe description.
/// Curated recipes come from the server already sanitized; we only need a
/// faithful plain rendering, not full styling. Falls back to raw HTML body if
/// parsing fails.
private enum DiscoverDescriptionText {
    static func htmlToPlainText(_ html: String) -> String {
        var text = html
        // Convert block-level boundaries to newlines for readability.
        let blockEndings: [(String, String)] = [
            ("(?i)</p>", "\n"),
            ("(?i)</li>", "\n"),
            ("(?i)</h[1-6]>", "\n"),
            ("(?i)<br\\s*/?>", "\n"),
        ]
        for (pattern, replacement) in blockEndings {
            text = text.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        text = text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
        // Collapse 3+ newlines into 2 (Markdown paragraph break).
        repeat {
            let next = text.replacingOccurrences(
                of: "\n{3,}",
                with: "\n\n",
                options: .regularExpression
            )
            if next == text { break }
            text = next
        } while true
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

import SwiftUI

/// Recipe detail backed by Y.Doc via `YjsSyncService`.
struct YDocRecipeDetailView: View {
    let recipeId: String

    @EnvironmentObject private var syncService: YjsSyncService
    @State private var scaleFactor: Double = 1.0
    @State private var isLoading = false

    private var recipe: RecipeData? {
        guard syncService.currentRecipe?.id == recipeId else { return nil }
        return syncService.currentRecipe
    }

    private var displayIngredients: [DisplayIngredient] {
        guard let recipe else { return [] }
        return RecipeDetailScaling.displayIngredients(from: recipe, scaleFactor: scaleFactor)
    }

    private var headerImageURL: URL? {
        guard let recipe else { return nil }
        if let imageUrl = recipe.imageUrl, !imageUrl.isEmpty,
           let url = URL(string: imageUrl), url.scheme != nil {
            return url
        }
        return APIClient.shared.recipeImageURL(id: recipe.id, preview: false)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let imageUrl = headerImageURL {
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
                    if isLoading && recipe == nil {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }

                    Text(recipe?.name ?? "")
                        .font(.custom(AppFonts.display, size: 28))
                        .lineLimit(nil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    if let recipe {
                        ScaleFactorControl(scaleFactor: $scaleFactor)
                            .padding(.horizontal)
                            .onAppear {
                                scaleFactor = 1.0
                            }

                        if !displayIngredients.isEmpty {
                            IngredientsSection(
                                ingredients: displayIngredients,
                                scaleFactor: 1.0
                            )
                        } else {
                            Text(String(localized: "No ingredients"))
                                .font(.custom(AppFonts.sans, size: 17))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                        }

                        if let description = recipe.description, !description.isEmpty {
                            StepsSection(htmlContent: description)
                        }

                        if let nutrition = recipe.nutrition {
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
        .task(id: recipeId) {
            isLoading = true
            await syncService.loadRecipe(recipeId: recipeId)
            isLoading = false
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
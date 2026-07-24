import Foundation

/// Deterministic test data for E2E specs.
///
/// Web parity: `tests/e2e/fixtures/import-text.ts`, `image-fixture.ts`,
/// `description-sample.ts`. Keep names unique per test run (UUID suffix)
/// so concurrent runs or partial resets don't collide.
enum TestData {
    /// Generate a unique recipe name with a stable prefix.
    /// Web equivalent: `Recipe ${Date.now()}` in spec files.
    static func recipeName(_ prefix: String = "E2E") -> String {
        let stamp = Int(Date().timeIntervalSince1970)
        let suffix = UUID().uuidString.prefix(6)
        return "\(prefix) \(stamp) \(suffix)"
    }

    /// Generate a unique shopping list item label.
    static func shoppingItemLabel(_ prefix: String = "E2E Item") -> String {
        let suffix = UUID().uuidString.prefix(6)
        return "\(prefix) \(suffix)"
    }

    /// Generate a unique collection (folder) name.
    static func collectionName(_ prefix: String = "E2E Folder") -> String {
        let suffix = UUID().uuidString.prefix(6)
        return "\(prefix) \(suffix)"
    }

    /// Canonical ingredient set used by RecipeEditing/Seed specs.
    /// Web parity: `createRecipe({ ingredients: [...] })` shape.
    static let canonicalIngredients: [SeedIngredient] = [
        SeedIngredient(name: "Flour", originalAmount: 250, unit: "g"),
        SeedIngredient(name: "Sugar", originalAmount: 100, unit: "g"),
        SeedIngredient(name: "Eggs", originalAmount: 3, unit: "pcs"),
    ]

    /// Canonical recipe import text for LLM-driven tests (spec 010).
    /// Stable so the LLM extraction produces deterministic ingredient counts.
    static let simpleRecipeText = """
    Pancakes

    Ingredients:
    200 g flour
    2 eggs
    300 ml milk
    1 tbsp sugar
    pinch of salt

    Instructions:
    Mix flour, eggs, milk, sugar and salt.
    Heat a pan and cook small portions until golden.
    """
}

/// Web-parity `SeedIngredient` shape (see `recipe-api.ts`).
struct SeedIngredient {
    let name: String
    let originalAmount: Double?
    let unit: String

    init(name: String, originalAmount: Double?, unit: String) {
        self.name = name
        self.originalAmount = originalAmount
        self.unit = unit
    }
}

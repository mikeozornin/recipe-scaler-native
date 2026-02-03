import XCTest
@testable import RecipeScalerNative

final class RecipeScalerNativeTests: XCTestCase {
    func testRecipeHasSteps() {
        let recipe = Recipe(name: "Toast", recipeDescription: "Spread and toast")
        XCTAssertTrue(recipe.hasSteps)
    }
}

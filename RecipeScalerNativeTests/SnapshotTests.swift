import SnapshotTesting
import SwiftData
import SwiftUI
import XCTest
@testable import RecipeScalerNative

final class SnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        isRecording = false
    }

    func testAuthView() {
        let view = AuthView()
        assertSnapshot(
            of: view,
            as: .image(layout: .device(config: .iPhone13))
        )
    }

    func testRecipeListView() throws {
        let container = try TestSupport.makeInMemoryContainer()
        TestSupport.seedRecipes(into: container.mainContext)

        let view = RecipeListView(autoLoad: false)
            .modelContainer(container)

        assertSnapshot(
            of: view,
            as: .image(layout: .device(config: .iPhone13))
        )
    }

    func testRecipeDetailView() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let recipe = TestSupport.sampleRecipe()

        let view = NavigationStack {
            RecipeDetailView(recipe: recipe, autoLoad: false)
        }
        .modelContainer(container)

        assertSnapshot(
            of: view,
            as: .image(layout: .device(config: .iPhone13))
        )
    }
}

import Foundation
import SwiftData
@testable import RecipeScalerNative

enum TestSupport {
    static func makeInMemoryContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: RecipeTimer.self,
            configurations: config
        )
    }
}

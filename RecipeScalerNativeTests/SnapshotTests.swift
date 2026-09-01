import SnapshotTesting
import SwiftData
import SwiftUI
import XCTest
@testable import RecipeScalerNative

@MainActor
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
        let database = try YrsDatabase()
        let store = YDocStore(dbQueue: database.dbQueue)
        let syncService = YjsSyncService.makeForTesting(store: store)

        let view = RecipeListView(syncService: syncService)
            .modelContainer(container)

        assertSnapshot(
            of: view,
            as: .image(layout: .device(config: .iPhone13))
        )
    }
}

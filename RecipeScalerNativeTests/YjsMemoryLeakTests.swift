import XCTest
import GRDB
@testable import RecipeScalerNative

@MainActor
final class YjsMemoryLeakTests: XCTestCase {
    
    private func makeStubStore() -> YDocStore {
        let db = (try? YrsDatabase.makeInMemoryFallback())!
        return YDocStore(dbQueue: db.dbQueue)
    }

    func testFastReopenDoesNotDropNewerSession() async throws {
        let store = makeStubStore()
        let sync = YjsSyncService(store: store)

        var oldBridge: DescriptionEditorBridge? = DescriptionEditorBridge(recipeId: "recipe-1", syncService: sync)
        XCTAssertEqual(sync.test_descriptionEditorSessionsCount, 1)

        let newBridge = DescriptionEditorBridge(recipeId: "recipe-1", syncService: sync)
        XCTAssertEqual(sync.test_descriptionEditorSessionsCount, 1)
        XCTAssertTrue(sync.test_descriptionEditorSessionBridge(for: "recipe-1") === newBridge)

        oldBridge = nil
        try? await Task.sleep(nanoseconds: 100_000_000)

        sync.test_pruneSessions()
        XCTAssertEqual(sync.test_descriptionEditorSessionsCount, 1)
        XCTAssertTrue(sync.test_descriptionEditorSessionBridge(for: "recipe-1") === newBridge)
    }

    func testDescriptionEditorSessionLeaksClearedOnDeinit() async throws {
        let store = makeStubStore()
        let sync = YjsSyncService(store: store)
        
        // 1. Initially 0 sessions
        XCTAssertEqual(sync.test_descriptionEditorSessionsCount, 0)
        
        // 2. Register a bridge within a local scope
        do {
            let bridge = DescriptionEditorBridge(recipeId: "recipe-1", syncService: sync)
            XCTAssertEqual(sync.test_descriptionEditorSessionsCount, 1)
            _ = bridge
        }
        
        // 3. The bridge has gone out of scope and is deallocated.
        // Wait for deinit's MainActor task to run
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // 4. Assert that the session was pruned or removed
        sync.test_pruneSessions()
        XCTAssertEqual(sync.test_descriptionEditorSessionsCount, 0)
    }
    
    func testTeardownClearsWireSnapshotTasksAndDocumentLoadTasks() async throws {
        let store = makeStubStore()
        let sync = YjsSyncService(store: store)
        
        // 1. Simulate adding a wire snapshot refresh task
        let dummyTask = Task {
            _ = try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        sync.test_simulateWireSnapshotRefreshTask(recipeId: "recipe-1", task: dummyTask)
        XCTAssertEqual(sync.test_wireSnapshotRefreshTasksCount, 1)
        
        // 2. Simulate adding a document load continuation by running a Task
        let expectation = expectation(description: "continuation resumed")
        Task {
            let result = await withCheckedContinuation { continuation in
                sync.test_simulateLoadDocument(recipeId: "recipe-1", continuation: continuation)
            }
            XCTAssertFalse(result)
            expectation.fulfill()
        }
        
        // Let the Task register the continuation
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(sync.test_documentLoadContinuationsCount, 1)
        
        // 3. Call stop() which runs teardownSocket()
        sync.stop()
        
        // 4. Wait for the expectation to be fulfilled (the continuation must have resumed returning false)
        await fulfillment(of: [expectation], timeout: 2.0)
        
        // 5. Verify that all dictionaries are cleared
        XCTAssertEqual(sync.test_wireSnapshotRefreshTasksCount, 0)
        XCTAssertEqual(sync.test_documentLoadContinuationsCount, 0)
        XCTAssertEqual(sync.test_documentLoadTasksCount, 0)
        
        // Ensure dummyTask is cancelled
        XCTAssertTrue(dummyTask.isCancelled)
    }
}

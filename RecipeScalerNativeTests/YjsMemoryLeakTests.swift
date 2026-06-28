import XCTest
import GRDB
@testable import RecipeScalerNative

@MainActor
final class YjsMemoryLeakTests: XCTestCase {
    
    private func makeStubStore() throws -> YDocStore {
        let db = try YrsDatabase.makeInMemoryFallback()
        return YDocStore(dbQueue: db.dbQueue)
    }

    func testFastReopenDoesNotDropNewerSession() async throws {
        let store = try makeStubStore()
        let sync = YjsSyncService(store: store)

        var oldBridge: DescriptionEditorBridge? = DescriptionEditorBridge(recipeId: "recipe-1", syncService: sync)
        oldBridge?.test_registerWithSyncService()
        XCTAssertEqual(sync.test_descriptionEditorSessionsCount, 1)

        let newBridge = DescriptionEditorBridge(recipeId: "recipe-1", syncService: sync)
        newBridge.test_registerWithSyncService()
        XCTAssertEqual(sync.test_descriptionEditorSessionsCount, 1)
        XCTAssertTrue(sync.test_descriptionEditorSessionBridge(for: "recipe-1") === newBridge)

        oldBridge = nil
        try await Task.sleep(for: .milliseconds(100))

        sync.test_pruneSessions()
        XCTAssertEqual(sync.test_descriptionEditorSessionsCount, 1)
        XCTAssertTrue(sync.test_descriptionEditorSessionBridge(for: "recipe-1") === newBridge)
    }

    func testDescriptionEditorSessionLeaksClearedOnDeinit() async throws {
        let store = try makeStubStore()
        let sync = YjsSyncService(store: store)

        // 1. Initially 0 sessions
        XCTAssertEqual(sync.test_descriptionEditorSessionsCount, 0)

        // 2. Register a bridge within a local scope
        do {
            let bridge = DescriptionEditorBridge(recipeId: "recipe-1", syncService: sync)
            bridge.test_registerWithSyncService()
            XCTAssertEqual(sync.test_descriptionEditorSessionsCount, 1)
            _ = bridge
        }
        
        // 3. The bridge has gone out of scope and is deallocated.
        // Wait for deinit's MainActor task to run
        try await Task.sleep(for: .milliseconds(100))
        
        // 4. Assert that the session was pruned or removed
        sync.test_pruneSessions()
        XCTAssertEqual(sync.test_descriptionEditorSessionsCount, 0)
    }
    
    func testTeardownClearsWireSnapshotTasksAndDocumentLoadTasks() async throws {
        let store = try makeStubStore()
        let sync = YjsSyncService(store: store)
        
        // 1. Simulate adding a wire snapshot refresh task
        let dummyTask = Task {
            _ = try? await Task.sleep(for: .seconds(1))
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
        try await Task.sleep(for: .milliseconds(100))
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

    /// MIK-167: deleting a recipe (server `sync_error.recipeDeleted`
    /// or local `deleteRecipeFromCollection`) must clear that recipeId's
    /// entries in all four per-recipe dicts immediately — not wait for
    /// global teardown. Otherwise mid-load continuations, wire-snapshot
    /// refresh tasks, and description-editor sessions leak until stop().
    @MainActor
    func testCancelPendingWorkForRecipeClearsAllFourEntries() async throws {
        let store = try makeStubStore()
        let sync = YjsSyncService(store: store)

        // Arrange: populate all four per-recipe dicts for two recipeIds.
        let wireTaskA = Task { _ = try? await Task.sleep(for: .seconds(1)) }
        let wireTaskB = Task { _ = try? await Task.sleep(for: .seconds(1)) }
        let loadTaskA = Task<Bool, Never> {
            try? await Task.sleep(for: .seconds(1))
            return false
        }
        let loadTaskB = Task<Bool, Never> {
            try? await Task.sleep(for: .seconds(1))
            return false
        }
        sync.test_simulateWireSnapshotRefreshTask(recipeId: "recipe-a", task: wireTaskA)
        sync.test_simulateWireSnapshotRefreshTask(recipeId: "recipe-b", task: wireTaskB)
        sync.test_simulateLoadTask(recipeId: "recipe-a", task: loadTaskA)
        sync.test_simulateLoadTask(recipeId: "recipe-b", task: loadTaskB)
        sync.test_simulateAddSession(recipeId: "recipe-a", session: DescriptionEditorSession())
        sync.test_simulateAddSession(recipeId: "recipe-b", session: DescriptionEditorSession())

        let contExpectation = expectation(description: "continuation for recipe-a resumed with false")
        Task {
            let result = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                sync.test_simulateLoadDocument(recipeId: "recipe-a", continuation: cont)
            }
            XCTAssertFalse(result)
            contExpectation.fulfill()
        }
        // Let the Task register the continuation
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(sync.test_wireSnapshotRefreshTasksCount, 2)
        XCTAssertEqual(sync.test_documentLoadTasksCount, 2)
        XCTAssertEqual(sync.test_documentLoadContinuationsCount, 1)
        XCTAssertEqual(sync.test_descriptionEditorSessionsCount, 2)

        // Act: cancel pending work for recipe-a only.
        sync.test_cancelPendingWork(forRecipeId: "recipe-a")

        // Continuation must have resumed returning false.
        await fulfillment(of: [contExpectation], timeout: 2.0)

        // Assert: recipe-a entries cleared; recipe-b untouched.
        XCTAssertEqual(sync.test_wireSnapshotRefreshTasksCount, 1)
        XCTAssertEqual(sync.test_documentLoadTasksCount, 1)
        XCTAssertEqual(sync.test_documentLoadContinuationsCount, 0)
        XCTAssertEqual(sync.test_descriptionEditorSessionsCount, 1)

        XCTAssertTrue(wireTaskA.isCancelled)
        XCTAssertTrue(loadTaskA.isCancelled)
        XCTAssertFalse(wireTaskB.isCancelled)
        XCTAssertFalse(loadTaskB.isCancelled)

        // Cleanup so it does not outlive the test.
        sync.stop()
    }
}

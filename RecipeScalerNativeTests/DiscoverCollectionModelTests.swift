import XCTest
@testable import RecipeScalerNative

@MainActor
final class DiscoverCollectionModelTests: XCTestCase {
    func testLoadIfNeededLoadsOnceForSameSlug() async {
        let expected = makeCollection(slug: "weeknight", title: "First")
        let probe = CollectionFetchProbe(results: [.success(expected)])
        let model = DiscoverCollectionModel(api: .shared) { slug in
            XCTAssertEqual(slug, "weeknight")
            return try await probe.next()
        }

        await model.loadIfNeeded(slug: "weeknight")
        await model.loadIfNeeded(slug: "weeknight")

        let callCount = await probe.callCount
        XCTAssertEqual(callCount, 1)
        guard case .loaded(let collection) = model.state else {
            return XCTFail("Expected loaded collection")
        }
        XCTAssertEqual(collection.title, "First")
    }

    func testRefreshKeepsLoadedCollectionUntilSuccess() async {
        let initial = makeCollection(slug: "weeknight", title: "Initial")
        let refreshed = makeCollection(slug: "weeknight", title: "Refreshed")
        let gate = CollectionFetchGate(initial: initial)
        let model = DiscoverCollectionModel(api: .shared) { _ in
            await gate.fetch()
        }

        await model.loadIfNeeded(slug: "weeknight")
        let enteredTask = Task { await gate.waitForCall(2) }
        let refreshTask = Task { await model.refresh(slug: "weeknight") }
        await enteredTask.value

        guard case .loaded(let duringRefresh) = model.state else {
            refreshTask.cancel()
            return XCTFail("Refresh must keep the old loaded payload")
        }
        XCTAssertEqual(duringRefresh.title, "Initial")
        XCTAssertTrue(model.isRefreshing)

        await gate.release(refreshed)
        await refreshTask.value

        guard case .loaded(let afterRefresh) = model.state else {
            return XCTFail("Expected refreshed collection")
        }
        XCTAssertEqual(afterRefresh.title, "Refreshed")
        XCTAssertFalse(model.isRefreshing)
    }

    func testRefreshFailureKeepsLoadedCollection() async {
        let initial = makeCollection(slug: "weeknight", title: "Initial")
        let probe = CollectionFetchProbe(results: [
            .success(initial),
            .failure(TestError.failed)
        ])
        let model = DiscoverCollectionModel(api: .shared) { _ in
            try await probe.next()
        }

        await model.loadIfNeeded(slug: "weeknight")
        await model.refresh(slug: "weeknight")

        guard case .loaded(let collection) = model.state else {
            return XCTFail("Refresh failure must preserve loaded collection")
        }
        XCTAssertEqual(collection.title, "Initial")
    }

    func testStaleResponseCannotOverwriteNewerRequest() async {
        let first = makeCollection(slug: "weeknight", title: "First")
        let second = makeCollection(slug: "weeknight", title: "Second")
        let gate = OutOfOrderCollectionFetch()
        let model = DiscoverCollectionModel(api: .shared) { _ in
            await gate.fetch()
        }

        let firstTask = Task { await model.loadIfNeeded(slug: "weeknight") }
        await gate.waitForCall(1)
        let secondTask = Task { await model.refresh(slug: "weeknight") }
        await gate.waitForCall(2)

        await gate.release(second, for: 2)
        await secondTask.value
        await gate.release(first, for: 1)
        await firstTask.value

        guard case .loaded(let collection) = model.state else {
            return XCTFail("Expected the newer request to load")
        }
        XCTAssertEqual(collection.title, "Second")
    }

    func testRefreshCancellationKeepsLoadedCollection() async {
        let initial = makeCollection(slug: "weeknight", title: "Initial")
        let gate = CollectionFetchGate(initial: initial)
        let model = DiscoverCollectionModel(api: .shared) { _ in
            await gate.fetch()
        }

        await model.loadIfNeeded(slug: "weeknight")
        let refreshTask = Task { await model.refresh(slug: "weeknight") }
        await gate.waitForCall(2)
        refreshTask.cancel()
        await gate.release(initial)
        await refreshTask.value

        guard case .loaded(let collection) = model.state else {
            return XCTFail("Cancellation must preserve the loaded collection")
        }
        XCTAssertEqual(collection.title, "Initial")
    }

    func testInitialCancellationReturnsToIdle() async {
        let gate = CancellationGate()
        let model = DiscoverCollectionModel(api: .shared) { _ in
            try await gate.wait()
            return CollectionWithRecipesDTO(
                slug: "weeknight",
                title: "Never",
                description: nil,
                authorName: nil,
                recipes: []
            )
        }
        let task = Task { await model.loadIfNeeded(slug: "weeknight") }
        await gate.waitUntilEntered()
        task.cancel()
        await task.value

        if case .failed = model.state {
            XCTFail("Cancellation must not become a failed state")
        }
    }

    private func makeCollection(slug: String, title: String) -> CollectionWithRecipesDTO {
        CollectionWithRecipesDTO(
            slug: slug,
            title: title,
            description: nil,
            authorName: nil,
            recipes: []
        )
    }
}

private enum TestError: Error {
    case failed
}

private actor CollectionFetchProbe {
    private var results: [Result<CollectionWithRecipesDTO, TestError>]
    private(set) var callCount = 0

    init(results: [Result<CollectionWithRecipesDTO, TestError>]) {
        self.results = results
    }

    func next() throws -> CollectionWithRecipesDTO {
        callCount += 1
        return try results.removeFirst().get()
    }
}

private actor CollectionFetchGate {
    private let initial: CollectionWithRecipesDTO
    private var callCount = 0
    private var pending: CheckedContinuation<CollectionWithRecipesDTO, Never>?
    private var callWaiters: [Int: CheckedContinuation<Void, Never>] = [:]

    init(initial: CollectionWithRecipesDTO) {
        self.initial = initial
    }

    func fetch() async -> CollectionWithRecipesDTO {
        callCount += 1
        callWaiters.removeValue(forKey: callCount)?.resume()
        if callCount == 1 {
            return initial
        }
        return await withCheckedContinuation { continuation in
            pending = continuation
        }
    }

    func waitForCall(_ expected: Int) async {
        if callCount >= expected {
            return
        }
        await withCheckedContinuation { continuation in
            callWaiters[expected] = continuation
        }
    }

    func release(_ result: CollectionWithRecipesDTO) {
        pending?.resume(returning: result)
        pending = nil
    }
}

private actor OutOfOrderCollectionFetch {
    private var callCount = 0
    private var pending: [Int: CheckedContinuation<CollectionWithRecipesDTO, Never>] = [:]
    private var callWaiters: [Int: CheckedContinuation<Void, Never>] = [:]

    func fetch() async -> CollectionWithRecipesDTO {
        callCount += 1
        callWaiters.removeValue(forKey: callCount)?.resume()
        return await withCheckedContinuation { continuation in
            pending[callCount] = continuation
        }
    }

    func waitForCall(_ expected: Int) async {
        if callCount >= expected {
            return
        }
        await withCheckedContinuation { continuation in
            callWaiters[expected] = continuation
        }
    }

    func release(_ result: CollectionWithRecipesDTO, for call: Int) {
        pending.removeValue(forKey: call)?.resume(returning: result)
    }
}

private actor CancellationGate {
    private var entered = false
    private var enteredContinuation: CheckedContinuation<Void, Never>?

    func wait() async throws {
        entered = true
        enteredContinuation?.resume()
        enteredContinuation = nil
        try await Task.sleep(for: .seconds(60))
    }

    func waitUntilEntered() async {
        if entered {
            return
        }
        await withCheckedContinuation { continuation in
            enteredContinuation = continuation
        }
    }
}

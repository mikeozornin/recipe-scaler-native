//
//  VkusvillSettingsStoreTests.swift
//
//  Failure-path / lifecycle coverage for spec 072 review findings:
//
//    1. Overlapping `refresh()` calls: only the newest GET may apply its result
//       (refresh-epoch guard). Previously concurrent refreshes shared one
//       generation snapshot, so a slower earlier GET could overwrite the newer
//       value.
//    2. Stale response crossing an account switch / logout must be discarded.
//    3. An in-flight GET started BEFORE a successful PUT must not clobber the
//       mutated value when it finally resolves.
//    4. `setEnabled` rollback on failure restores the previous value.
//
//  Network is stubbed through the store's injected providers (same pattern as
//  `AuthService.checkUserExistsProvider`), with real suspension points so the
//  interleavings below are exercised deterministically via gates.
//

import XCTest
import RecipeScalerCore
@testable import RecipeScalerNative

@MainActor
final class VkusvillSettingsStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "vkusvill.settings.userId")
        UserDefaults.standard.removeObject(forKey: "vkusvill.settings.enabled")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "vkusvill.settings.userId")
        UserDefaults.standard.removeObject(forKey: "vkusvill.settings.enabled")
        super.tearDown()
    }

    private func makeDTO(nutrition: Bool? = nil, vkusvill: Bool? = nil) -> UserSettingsDTO {
        UserSettingsDTO(nutritionEnabled: nutrition, vkusvillEnabled: vkusvill)
    }

    /// Locked call counter so provider closures can branch per invocation.
    private final class CallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func next() -> Int {
            lock.withLock {
                value += 1
                return value
            }
        }
    }

    /// Async one-shot gate: `wait()` suspends until `open()` (or resumes
    /// immediately when already open).
    private final class AsyncGate: @unchecked Sendable {
        private let lock = NSLock()
        private var isOpen = false
        private var continuations: [CheckedContinuation<Void, Never>] = []

        func open() {
            let resumed: [CheckedContinuation<Void, Never>] = lock.withLock {
                isOpen = true
                let pending = continuations
                continuations = []
                return pending
            }
            resumed.forEach { $0.resume() }
        }

        func wait() async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let resumeNow: Bool = lock.withLock {
                    if isOpen {
                        return true
                    }
                    continuations.append(continuation)
                    return false
                }
                if resumeNow {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Overlapping refreshes (refresh epoch)

    func test_refresh_overlapping_onlyNewestResponseIsApplied() async throws {
        let store = VkusvillSettingsStore()
        let counter = CallCounter()

        store.fetchUserSettingsProvider = {
            // First (older) refresh resolves slowly and carries `true`;
            // second (newer) refresh resolves immediately with `false`.
            if counter.next() == 1 {
                try? await Task.sleep(nanoseconds: 150_000_000)
                return self.makeDTO(vkusvill: true)
            }
            return self.makeDTO(vkusvill: false)
        }

        let olderRefresh = Task { await store.refresh(userId: "user-A", isOnline: true) }
        // Give the older refresh time to enter its suspended GET…
        try await Task.sleep(nanoseconds: 30_000_000)
        // …then start the newer one that wins the race.
        await store.refresh(userId: "user-A", isOnline: true)
        await olderRefresh.value

        XCTAssertFalse(
            store.enabled,
            "Stale slow GET must be discarded by the newer refresh epoch, not applied last"
        )
        XCTAssertFalse(store.isLoading)
    }

    // MARK: - Account switch / logout invalidates in-flight reads

    func test_refresh_staleResponseFromPreviousAccount_isDiscarded() async throws {
        let store = VkusvillSettingsStore()
        let gate = AsyncGate()

        store.fetchUserSettingsProvider = { _ = await gate.wait(); return self.makeDTO(vkusvill: true) }

        let slowFetch = Task { await store.refresh(userId: "user-A", isOnline: true) }
        try await Task.sleep(nanoseconds: 50_000_000)

        // Logout + new account activation happen while user-A's GET is in flight.
        store.clearForLogout()
        await store.refresh(userId: "user-B", isOnline: false)
        gate.open()
        await slowFetch.value

        XCTAssertFalse(
            store.enabled,
            "Response for user-A must never land after the account switched"
        )
        XCTAssertNil(store.lastError)
    }

    func test_refresh_inFlightGetDoesNotClobberSuccessfulPut() async throws {
        let store = VkusvillSettingsStore()
        let gate = AsyncGate()
        let counter = CallCounter()

        store.fetchUserSettingsProvider = {
            // GET #1 starts before the toggle flips and resolves long after it,
            // carrying the pre-mutation server snapshot (`false`).
            if counter.next() == 1 {
                await gate.wait()
                return self.makeDTO(nutrition: true, vkusvill: false)
            }
            return self.makeDTO(nutrition: true, vkusvill: false)
        }
        store.updateVkusvillEnabledProvider = { _ in }

        let staleGet = Task { await store.refresh(userId: "user-A", isOnline: true) }
        try await Task.sleep(nanoseconds: 50_000_000)

        // Mutation completes while the GET is still hanging.
        await store.setEnabled(true, userId: "user-A")

        gate.open()
        await staleGet.value

        XCTAssertTrue(
            store.enabled,
            "Late GET snapshot taken before the PUT must not roll the toggle back"
        )
        XCTAssertFalse(store.isUpdating)
    }

    // MARK: - Rollback on failure

    func test_setEnabled_failureRollsBackValueAndSetsError() async throws {
        let store = VkusvillSettingsStore()
        store.updateVkusvillEnabledProvider = { _ in
            throw APIError.httpError(statusCode: 500)
        }
        store.applyRemoteValue(false, userId: "user-A")
        XCTAssertFalse(store.enabled, "Precondition: baseline value false")

        await store.setEnabled(true, userId: "user-A")

        XCTAssertFalse(store.enabled, "Failed PUT must restore the previous value")
        XCTAssertNotNil(store.lastError)
        XCTAssertFalse(store.isUpdating)
    }

    func test_setEnabled_successKeepsValueAndClearsError() async throws {
        let store = VkusvillSettingsStore()
        store.updateVkusvillEnabledProvider = { _ in }
        store.applyRemoteValue(false, userId: "user-A")

        await store.setEnabled(true, userId: "user-A")

        XCTAssertTrue(store.enabled)
        XCTAssertNil(store.lastError)
        XCTAssertFalse(store.isUpdating)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "vkusvill.settings.userId"), "user-A")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "vkusvill.settings.enabled"))
    }

    // MARK: - Nutrition mirror (single-owner `/api/settings` read)

    func test_refresh_mirrorsNutritionFlagFromServer() async throws {
        let store = VkusvillSettingsStore()
        store.fetchUserSettingsProvider = { self.makeDTO(nutrition: false, vkusvill: true) }

        await store.refresh(userId: "user-A", isOnline: true)

        XCTAssertEqual(store.nutritionEnabledFromServer, false)
        XCTAssertEqual(store.enabled, true)
    }

    func test_clearForLogout_resetsDerivedState() async throws {
        let store = VkusvillSettingsStore()
        store.fetchUserSettingsProvider = { self.makeDTO(nutrition: true, vkusvill: true) }
        await store.refresh(userId: "user-A", isOnline: true)

        store.clearForLogout()

        XCTAssertFalse(store.enabled)
        XCTAssertNil(store.nutritionEnabledFromServer)
        XCTAssertNil(store.activeUserIdForTesting)
        XCTAssertFalse(store.isLoading)
        XCTAssertFalse(store.isUpdating)
    }
}

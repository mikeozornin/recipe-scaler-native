//
//  FeatureAdoptionInstalledFlagTests.swift
//  RecipeScalerNativeTests
//
//  Regression coverage for spec 038 changelog 2026-08-03:
//  `feature-adoption.installed-reported` must be wiped on logout so a previous
//  account's flag does not suppress the `installed_native_app` POST for a
//  different account signing in on the same device.
//

import XCTest
import RecipeScalerCore
@testable import RecipeScalerNative

@MainActor
final class FeatureAdoptionInstalledFlagTests: XCTestCase {

    /// Counts calls to the injected `markFeatureAdoptionProvider` so tests can
    /// assert that the POST actually dispatched (rather than silently suppressed).
    private final class PostCallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var _count = 0
        func increment() { lock.withLock { _count += 1 } }
        var count: Int { lock.withLock { _count } }
    }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: FeatureAdoptionStore.installedReportedKey)
        UserDefaults.standard.removeObject(forKey: "feature-adoption-cache")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: FeatureAdoptionStore.installedReportedKey)
        UserDefaults.standard.removeObject(forKey: "feature-adoption-cache")
        super.tearDown()
    }

    /// When `installed-reported` is not set, `markFeatureInstalled` must dispatch
    /// a POST and flip the local cache. Both sides verified through the injected
    /// provider and the synchronous local cache update.
    func testMarkFeatureInstalledDispatchesPostWhenFlagUnset() async throws {
        let auth = AuthService()
        let counter = PostCallCounter()
        auth.markFeatureAdoptionProvider = { _ in counter.increment() }
        let store = FeatureAdoptionStore()

        XCTAssertFalse(store.report.installedNativeApp)
        XCTAssertEqual(counter.count, 0)

        auth.markFeatureInstalled(featureAdoptionStore: store)
        // The local cache flips synchronously (optimistic update)…
        XCTAssertTrue(store.report.installedNativeApp)
        // …and the POST fires once the Task resolves. Yield to let it run.
        await Task.yield()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(counter.count, 1, "POST must dispatch exactly once when flag is unset")
    }

    /// When `installed-reported` is already set, `markFeatureInstalled` must
    /// NOT dispatch a POST. This is the within-account idempotency guard.
    func testMarkFeatureInstalledSkipsPostWhenFlagAlreadySet() async throws {
        let auth = AuthService()
        let counter = PostCallCounter()
        auth.markFeatureAdoptionProvider = { _ in counter.increment() }
        UserDefaults.standard.set(true, forKey: FeatureAdoptionStore.installedReportedKey)
        let store = FeatureAdoptionStore()
        store.report.installedNativeApp = true

        auth.markFeatureInstalled(featureAdoptionStore: store)
        await Task.yield()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(counter.count, 0, "POST must NOT dispatch when flag is already set")
    }

    /// Reproduces the original bug shape: a previous account's idempotency flag
    /// must be wiped by `clearForLogout()` so the next account signing in on the
    /// same device dispatches a fresh POST.
    func testClearForLogoutAllowsPostForNextAccount() async throws {
        let auth = AuthService()
        let counter = PostCallCounter()
        auth.markFeatureAdoptionProvider = { _ in counter.increment() }
        let store = FeatureAdoptionStore()

        // Simulate "previous account already reported successfully":
        // idempotency flag is set and local cache is positive.
        UserDefaults.standard.set(true, forKey: FeatureAdoptionStore.installedReportedKey)
        store.report.installedNativeApp = true

        // Logout wipes per-account state.
        store.clearForLogout()
        XCTAssertFalse(UserDefaults.standard.bool(forKey: FeatureAdoptionStore.installedReportedKey))

        // Next account signs in: POST must dispatch.
        auth.markFeatureInstalled(featureAdoptionStore: store)
        await Task.yield()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(counter.count, 1, "Next account's POST must not be suppressed by previous account's flag")
    }

    /// Code review HIGH-1: if a logout completes while the fire-and-forget POST
    /// is in flight, the success branch must NOT re-arm the device idempotency
    /// flag. Without the session-identity guard this would resurrect the
    /// original multi-account bug through a realistic ~100ms–2s race window.
    func testInFlightPostDoesNotReArmFlagAfterLogout() async throws {
        let auth = AuthService()
        let store = FeatureAdoptionStore()
        let reportedKey = FeatureAdoptionStore.installedReportedKey

        // Seed a userId so the session-identity guard has something to compare
        // against before the POST "completes".
        SharedAuthStore.clear()
        SharedAuthStore.userId = "user-A"

        // Inject a provider that simulates the race: logout happens while the
        // POST is still in flight, then the POST resolves successfully.
        auth.markFeatureAdoptionProvider = { _ in
            // Logout races the POST: clears userId AND the idempotency flag.
            SharedAuthStore.userId = nil
            UserDefaults.standard.removeObject(forKey: reportedKey)
            store.clearForLogout()
            // POST now returns successfully — but the session it was recording
            // for is gone. The success branch must observe this and skip the
            // `installed-reported = true` write.
        }

        XCTAssertFalse(UserDefaults.standard.bool(forKey: reportedKey))
        auth.markFeatureInstalled(featureAdoptionStore: store)

        // Wait for the fire-and-forget Task to settle.
        await Task.yield()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(
            UserDefaults.standard.bool(forKey: reportedKey),
            "Race: in-flight POST must not re-arm device flag after logout"
        )

        SharedAuthStore.clear()
    }
}

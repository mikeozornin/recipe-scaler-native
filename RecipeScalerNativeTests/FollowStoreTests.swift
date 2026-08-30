//
//  FollowStoreTests.swift
//  RecipeScalerNativeTests
//
//  Spec 072 — `FollowStore` state machine (plan: Positive invariants +
//  Async lifecycle; spec US1/US2/US9).
//
//  The store's transport is `APIClient.shared` (no injection seam), so network
//  behavior is stubbed via `FollowFeedTestURLProtocol` — same pattern as
//  `LiveActivityPushRegistrarTests` (058). Server dot-key errors resolve
//  through the real `mapHTTPFailure` / `ServerErrorCode` path.
//
//  Covered:
//    - stale `refresh(username:)` completion must not overwrite a newer
//      profile's status (stale-guard, plan Async lifecycle row 1)
//    - optimistic follow / unfollow / setPushOptIn with rollback on failure
//      and `lastError` dot-key (US9, plan Positive invariants row 2)
//    - `clearForLogout` (US8 — full matrix lives in `FollowFeedStoresTests`)
//

import XCTest
import RecipeScalerCore
@testable import RecipeScalerNative

@MainActor
final class FollowStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        FollowFeedTestURLProtocol.reset()
        URLProtocol.registerClass(FollowFeedTestURLProtocol.self)
    }

    override func tearDown() {
        FollowFeedTestURLProtocol.reset()
        URLProtocol.unregisterClass(FollowFeedTestURLProtocol.self)
        super.tearDown()
    }

    // MARK: - Stale refresh guard (plan Async lifecycle row 1)

    /// refresh("a") and refresh("b") race; "a" resolves last. The stale-guard
    /// must keep b's status instead of overwriting it with a's response.
    ///
    /// Deterministic interleaving (no concurrent-request dependency): a's
    /// response is held on a gate while b's refresh runs to completion; only
    /// then is a's completion released — it must be dropped by the guard.
    /// (The previous both-requests-in-flight choreography flaked under full
    /// suite load: the second transport dispatch lagged past the wait timeout.)
    func test_stale_refresh_ignored() async {
        let store = FollowStore()

        let gateA = FFDispatchGate()
        let startedA = FFCounter()

        FollowFeedTestURLProtocol.handler = { request in
            guard request.url?.path.contains("/users/me/following/") == true else {
                return FollowFeedTestURLProtocol.okEmpty()
            }
            let username = request.url?.path
                .split(separator: "/")
                .last.map(String.init) ?? ""
            if username == "a" {
                startedA.bump()
                gateA.wait()
                return FollowFeedTestURLProtocol.followStatus(following: false, pushOptIn: false)
            }
            // "b" (and anything else) resolves immediately.
            return FollowFeedTestURLProtocol.followStatus(following: true, pushOptIn: true)
        }

        let refreshTaskA = Task { await store.refresh(username: "a") }
        await ffWaitUntil { startedA.value == 1 }

        // b's refresh completes while a's response is still held on the gate.
        await store.refresh(username: "b")
        XCTAssertEqual(
            store.status,
            FollowStatusDTO(following: true, pushOptIn: true),
            "Sanity: profile b's status landed first"
        )

        // Now a's stale completion arrives — it must be dropped.
        gateA.release()
        await refreshTaskA

        XCTAssertEqual(
            store.status,
            FollowStatusDTO(following: true, pushOptIn: true),
            "a late completion for profile \"a\" must not overwrite profile \"b\" state"
        )
        XCTAssertNil(store.lastError)
    }

    // MARK: - Optimistic mutations (US1/US2/US9)

    /// A follow failure for profile "a" that completes after refresh("b") has
    /// landed must not roll back b's status — the stale-guard keeps the newer
    /// profile's state (plan Async lifecycle, stale-guard row).
    func test_stale_mutation_failure_does_not_overwrite_newer_profile() async {
        let store = FollowStore()
        // Seed: profile "a" is followed; then the user navigates to "b".
        FollowFeedTestURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path.contains("/users/me/following/") {
                let username = path.split(separator: "/").last.map(String.init) ?? ""
                return Self.okStatus(following: username == "b", pushOptIn: false)
            }
            if path.hasSuffix("/follow") {
                return Self.apiFailure("follow.too-many-follows", status: 409)
            }
            return Self.okEmpty()
        }
        await store.refresh(username: "a")
        _ = await store.follow(username: "a")
        await store.refresh(username: "b")
        XCTAssertEqual(
            store.status,
            FollowStatusDTO(following: true, pushOptIn: false),
            "Sanity: profile b is loaded before the stale failure lands"
        )

        // The stale failure path needs activeUsername to have moved AFTER the
        // mutation captured its username — drive it directly through mutate's
        // public surface: refresh("b") runs while follow("a") is gated.
        let gate = FFDispatchGate()
        let followStarted = FFCounter()
        store.clearForLogout()
        FollowFeedTestURLProtocol.handler = { [followStarted] request in
            let path = request.url?.path ?? ""
            if path.contains("/users/me/following/") {
                let username = path.split(separator: "/").last.map(String.init) ?? ""
                return Self.okStatus(following: username == "b", pushOptIn: false)
            }
            if path.hasSuffix("/follow") {
                followStarted.bump()
                gate.wait()
                return Self.apiFailure("follow.too-many-follows", status: 409)
            }
            return Self.okEmpty()
        }

        let followTask = Task { await store.follow(username: "a") }
        await ffWaitUntil { followStarted.value == 1 }
        // While the follow("a") mutation is in flight, the user moves on to
        // profile "b"; its refresh completes first.
        await store.refresh(username: "b")
        gate.release()
        let ok = await followTask.value

        XCTAssertFalse(ok, "the gated follow must fail (409)")
        XCTAssertEqual(
            store.status,
            FollowStatusDTO(following: true, pushOptIn: false),
            "the failed stale follow for \"a\" must not overwrite profile \"b\" state"
        )
        XCTAssertEqual(store.lastError, .followTooManyFollows, "US9: dot-key still surfaces")
    }

    /// A status refresh that was in flight when an optimistic follow started
    /// must not clobber the mutation: refresh("author") resolves following=false
    /// after the optimistic flip — the follow's success keeps following=true.
    func test_refresh_does_not_clobber_pending_optimistic_follow() async {
        let store = FollowStore()

        let refreshGate = FFDispatchGate()
        let refreshStarted = FFCounter()
        let followGate = FFDispatchGate()
        let followStarted = FFCounter()
        FollowFeedTestURLProtocol.handler = { [refreshStarted, followStarted] request in
            let path = request.url?.path ?? ""
            if path.contains("/users/me/following/") {
                refreshStarted.bump()
                refreshGate.wait()
                return Self.okStatus(following: false, pushOptIn: false)
            }
            if path.hasSuffix("/follow") {
                followStarted.bump()
                followGate.wait()
                return Self.okSuccess(status: 201)
            }
            return Self.okEmpty()
        }

        let refreshTask = Task { await store.refresh(username: "author") }
        await ffWaitUntil { refreshStarted.value == 1 }

        // The user taps Follow while the status refresh is still hanging.
        let followTask = Task { await store.follow(username: "author") }
        await ffWaitUntil { store.isFollowingPending }

        // Refresh resolves first (stale pre-mutation snapshot), then the
        // follow completes.
        refreshGate.release()
        await refreshTask.value
        followGate.release()
        let ok = await followTask.value

        XCTAssertTrue(ok)
        XCTAssertEqual(
            store.status,
            FollowStatusDTO(following: true, pushOptIn: false),
            "a pre-mutation refresh completion must not revert the optimistic follow"
        )
        XCTAssertNil(store.lastError)
    }

    func test_follow_is_optimistic_and_persists_on_success() async {
        let store = FollowStore()
        FollowFeedTestURLProtocol.handler = { request in
            if request.url?.path.contains("/users/me/following/") == true {
                return Self.okStatus(following: false, pushOptIn: false)
            }
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.path.hasSuffix("/follow") == true)
            return Self.okSuccess(status: 201)
        }
        await store.refresh(username: "author")

        let ok = await store.follow(username: "author")

        XCTAssertTrue(ok)
        XCTAssertEqual(store.status, FollowStatusDTO(following: true, pushOptIn: false))
        XCTAssertNil(store.lastError)
    }

    /// Wire format: `DELETE /follow` → `204` no body (web spec 072). The empty
    /// response must decode cleanly so the optimistic unsubscribe persists —
    /// a decode failure would roll the state back while the server unfollowed.
    func test_unfollow_is_optimistic_and_persists_on_success() async {
        let store = FollowStore()
        FollowFeedTestURLProtocol.handler = { request in
            if request.url?.path.contains("/users/me/following/") == true {
                return Self.okStatus(following: true, pushOptIn: true)
            }
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertTrue(request.url?.path.hasSuffix("/follow") == true)
            return Self.noContent()
        }
        await store.refresh(username: "author")

        let ok = await store.unfollow(username: "author")

        XCTAssertTrue(ok, "a successful 204 unfollow must report success")
        XCTAssertEqual(
            store.status,
            FollowStatusDTO(following: false, pushOptIn: false),
            "optimistic unsubscribed state must persist after the 204 (no rollback)"
        )
        XCTAssertNil(store.lastError)
    }

    func test_follow_failure_rolls_back_and_sets_lastError_dotKey() async {
        let store = FollowStore()
        FollowFeedTestURLProtocol.handler = { request in
            if request.url?.path.contains("/users/me/following/") == true {
                return Self.okStatus(following: false, pushOptIn: false)
            }
            return Self.apiFailure("follow.too-many-follows", status: 409)
        }
        await store.refresh(username: "author")

        let ok = await store.follow(username: "author")

        XCTAssertFalse(ok, "failed follow must report failure to the caller")
        XCTAssertEqual(
            store.status,
            FollowStatusDTO(following: false, pushOptIn: false),
            "state must roll back to the pre-mutation snapshot (US6/US9)"
        )
        XCTAssertEqual(
            store.lastError,
            .followTooManyFollows,
            "US9: the server dot-key must surface via lastError for the view layer"
        )

        store.clearError()
        XCTAssertNil(store.lastError)
    }

    func test_unfollow_failure_rolls_back_to_following() async {
        let store = FollowStore()
        FollowFeedTestURLProtocol.handler = { request in
            if request.url?.path.contains("/users/me/following/") == true {
                return Self.okStatus(following: true, pushOptIn: true)
            }
            return Self.apiFailure("follow.rate-limited", status: 429)
        }
        await store.refresh(username: "author")

        let ok = await store.unfollow(username: "author")

        XCTAssertFalse(ok)
        XCTAssertEqual(store.status, FollowStatusDTO(following: true, pushOptIn: true))
        XCTAssertEqual(store.lastError, .followRateLimited)
    }

    func test_setPushOptIn_success_and_failure() async {
        let store = FollowStore()
        FollowFeedTestURLProtocol.handler = { request in
            if request.url?.path.contains("/users/me/following/") == true {
                return Self.okStatus(following: true, pushOptIn: false)
            }
            XCTAssertEqual(request.httpMethod, "PATCH")
            return Self.okStatus(following: true, pushOptIn: true)
        }
        await store.refresh(username: "author")

        let ok = await store.setPushOptIn(username: "author", true)

        XCTAssertTrue(ok)
        XCTAssertEqual(store.status, FollowStatusDTO(following: true, pushOptIn: true))
        XCTAssertNil(store.lastError)

        // Failure path: optimistic bell flip rolls back.
        FollowFeedTestURLProtocol.handler = { request in
            if request.url?.path.contains("/users/me/following/") == true {
                return Self.okStatus(following: true, pushOptIn: true)
            }
            return Self.apiFailure("follow.not-following", status: 404)
        }
        await store.refresh(username: "author")

        let okAgain = await store.setPushOptIn(username: "author", false)

        XCTAssertFalse(okAgain)
        XCTAssertEqual(store.status, FollowStatusDTO(following: true, pushOptIn: true))
        XCTAssertEqual(store.lastError, .followNotFollowing)
    }

    func test_nonServerError_failures_leave_lastError_nil() async {
        let store = FollowStore()
        FollowFeedTestURLProtocol.handler = { request in
            if request.url?.path.contains("/users/me/following/") == true {
                return Self.okStatus(following: false, pushOptIn: false)
            }
            return Self.apiFailure("", status: 500)
        }
        await store.refresh(username: "author")

        let ok = await store.follow(username: "author")

        XCTAssertFalse(ok)
        XCTAssertNil(store.lastError, "only APIError.serverError carries a dot-key")
        XCTAssertEqual(
            store.status,
            FollowStatusDTO(following: false, pushOptIn: false),
            "rollback must happen regardless of error shape"
        )
    }

    // MARK: - clearForLogout (spot check; full matrix in FollowFeedStoresTests)

    func test_clearForLogout_resets_relationship_state() async {
        let store = FollowStore()
        FollowFeedTestURLProtocol.handler = { _ in Self.okStatus(following: true, pushOptIn: true) }
        await store.refresh(username: "author")
        XCTAssertEqual(store.status, FollowStatusDTO(following: true, pushOptIn: true))

        store.clearForLogout()

        XCTAssertNil(store.status)
        XCTAssertNil(store.lastError)
        XCTAssertFalse(store.isFollowingPending)
    }

    // MARK: - helpers

    private static func okStatus(following: Bool, pushOptIn: Bool = false) -> (HTTPURLResponse, Data) {
        FollowFeedTestURLProtocol.followStatus(following: following, pushOptIn: pushOptIn)
    }

    private static func okEmpty() -> (HTTPURLResponse, Data) {
        FollowFeedTestURLProtocol.okEmpty()
    }

    private static func noContent() -> (HTTPURLResponse, Data) {
        FollowFeedTestURLProtocol.noContent()
    }

    private static func okSuccess(status: Int) -> (HTTPURLResponse, Data) {
        FollowFeedTestURLProtocol.okSuccess(status: status)
    }

    private static func apiFailure(_ dotKey: String, status: Int) -> (HTTPURLResponse, Data) {
        FollowFeedTestURLProtocol.apiFailure(dotKey, status: status)
    }
}

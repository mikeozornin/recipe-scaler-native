//
//  FeedBadgeStoreTests.swift
//  RecipeScalerNativeTests
//
//  Spec 072 — `FeedBadgeStore` red-dot state machine (plan: Async lifecycle
//  row 4 — `test_stale_badge_discarded`; teardown — logout reset; spec US4).
//
//  Covered:
//    - refresh applies the badge response (`hasNew` true/false)
//    - `markSeenLocally()` extinguishes the dot idempotently
//    - `clearForLogout()` resets the dot and discards an in-flight/stale
//      badge response (epoch bump — a late badge for the previous account
//      must not restore the dot)
//    - refresh failures are silent (dot unchanged)
//

import XCTest
import RecipeScalerCore
@testable import RecipeScalerNative

@MainActor
final class FeedBadgeStoreTests: XCTestCase {

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

    func test_refresh_applies_badge_response() async {
        let store = FeedBadgeStore()
        XCTAssertFalse(store.hasNew, "cold start: no dot before any badge answer")

        FollowFeedTestURLProtocol.handler = { _ in
            FollowFeedTestURLProtocol.badge(hasNew: true)
        }
        await store.refresh()

        XCTAssertTrue(store.hasNew, "has_new=true must light the dot")

        FollowFeedTestURLProtocol.handler = { _ in
            FollowFeedTestURLProtocol.badge(hasNew: false)
        }
        await store.refresh()

        XCTAssertFalse(store.hasNew, "has_new=false must clear the dot (server re-sync)")
    }

    func test_markSeenLocally_extinguishes_dot_idempotently() async {
        let store = FeedBadgeStore()
        FollowFeedTestURLProtocol.handler = { _ in
            FollowFeedTestURLProtocol.badge(hasNew: true)
        }
        await store.refresh()
        XCTAssertTrue(store.hasNew)

        store.markSeenLocally()
        XCTAssertFalse(store.hasNew)

        store.markSeenLocally()
        XCTAssertFalse(store.hasNew, "markSeenLocally must stay idempotent")
    }

    func test_refresh_failure_is_silent_and_keeps_previous_state() async {
        let store = FeedBadgeStore()
        FollowFeedTestURLProtocol.handler = { _ in
            FollowFeedTestURLProtocol.badge(hasNew: true)
        }
        await store.refresh()
        XCTAssertTrue(store.hasNew)

        FollowFeedTestURLProtocol.handler = { _ in
            FollowFeedTestURLProtocol.apiFailure("api.error.server-generic", status: 500)
        }
        await store.refresh()

        XCTAssertTrue(store.hasNew, "a failed badge poll must not touch the dot (US6 silent)")
    }

    func test_clearForLogout_resets_dot() async {
        let store = FeedBadgeStore()
        FollowFeedTestURLProtocol.handler = { _ in
            FollowFeedTestURLProtocol.badge(hasNew: true)
        }
        await store.refresh()
        XCTAssertTrue(store.hasNew)

        store.clearForLogout()

        XCTAssertFalse(store.hasNew, "logout must reset the dot (US8)")
    }

    /// Plan Async lifecycle row 4: a badge response captured before logout and
    /// completing after it must be discarded — `clearForLogout` bumps the
    /// epoch so the previous account's dot cannot flash back.
    func test_stale_badge_discarded_after_logout() async {
        let store = FeedBadgeStore()

        let gate = FFDispatchGate()
        let badgeStarted = FFCounter()
        FollowFeedTestURLProtocol.handler = { [badgeStarted] _ in
            badgeStarted.bump()
            gate.wait()
            return FollowFeedTestURLProtocol.badge(hasNew: true)
        }

        let refreshTask = Task { await store.refresh() }
        await ffWaitUntil { badgeStarted.value == 1 }
        store.clearForLogout()
        gate.release()
        await refreshTask.value

        XCTAssertFalse(
            store.hasNew,
            "a stale badge completion after clearForLogout must not restore the dot"
        )
    }

    /// Spec 072: «гашение сильнее любого in-flight badge-ответа» — a badge
    /// fetch started *before* `markSeenLocally()` (e.g. the bootstrap refresh
    /// in `AppContainer`) and completing after the feed page extinguished the
    /// dot must be discarded, not re-light it. `markSeenLocally` bumps the
    /// epoch the same way `clearForLogout` does.
    func test_inflight_badge_discarded_after_markSeenLocally() async {
        let store = FeedBadgeStore()

        let gate = FFDispatchGate()
        let badgeStarted = FFCounter()
        FollowFeedTestURLProtocol.handler = { [badgeStarted] _ in
            badgeStarted.bump()
            gate.wait()
            return FollowFeedTestURLProtocol.badge(hasNew: true)
        }

        let refreshTask = Task { await store.refresh() }
        await ffWaitUntil { badgeStarted.value == 1 }
        store.markSeenLocally()
        gate.release()
        await refreshTask.value

        XCTAssertFalse(
            store.hasNew,
            "a badge response racing with the feed-read clearing must not re-light the dot"
        )
    }
}

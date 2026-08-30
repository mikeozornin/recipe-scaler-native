//
//  FollowFeedStoresTests.swift
//  RecipeScalerNativeTests
//
//  Spec 072 US8 — combined logout reset across the three spec-072 stores
//  (plan Positive invariants row 6: «Логаут — все три стора сброшены,
//  `clearForLogout()`»). Mirrors the wiring in `AppContainer.stopForLogout()`
//  (feedStore → feedBadgeStore → followStore) without constructing a full
//  container: the same three `clearForLogout` calls in the same order.
//
//  The positive postcondition from the plan's Teardown table: «Новый
//  пользователь видит пустые сторы» — no feed items, no dot, no relationship
//  state, and no server-side side effects (no `/feed/seen` echo after logout).
//

import XCTest
import RecipeScalerCore
@testable import RecipeScalerNative

@MainActor
final class FollowFeedStoresTests: XCTestCase {

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

    /// Populates all three stores with non-empty state, then runs the
    /// `stopForLogout()` clear sequence and asserts every store is empty.
    func test_logout_reset() async {
        // Populate through the real network paths (stubbed transport).
        FollowFeedTestURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path == "/api/v1/feed" {
                return FollowFeedTestURLProtocol.feedPage(
                    items: [FollowFeedTestURLProtocol.feedEntry(id: "r1", isNew: true)],
                    nextCursor: "cursor-1",
                    snapshotAt: "2026-08-28T09:00:00.000Z"
                )
            }
            if path == "/api/v1/feed/seen" {
                return FollowFeedTestURLProtocol.noContent()
            }
            if path == "/api/v1/feed/badge" {
                return FollowFeedTestURLProtocol.badge(hasNew: true)
            }
            if path.hasSuffix("/follow") {
                return FollowFeedTestURLProtocol.okSuccess(status: 201)
            }
            if path.contains("/users/me/following/") {
                return FollowFeedTestURLProtocol.followStatus(following: true, pushOptIn: true)
            }
            return FollowFeedTestURLProtocol.noContent()
        }

        let feedBadgeStore = FeedBadgeStore()
        let feedStore = FeedStore()
        feedStore.bind(badgeStore: feedBadgeStore)
        let followStore = FollowStore()

        await feedBadgeStore.refresh()
        XCTAssertTrue(feedBadgeStore.hasNew, "Sanity: dot is lit after badge refresh")

        await feedStore.loadFirstPage()
        XCTAssertFalse(
            feedBadgeStore.hasNew,
            "Sanity: successful page-1 extinguishes the dot («прочитано = загружено»)"
        )

        await followStore.refresh(username: "author")
        _ = await followStore.follow(username: "author")

        // Re-light the dot so logout reset is observable on the badge store too.
        FollowFeedTestURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path == "/api/v1/feed/badge" {
                return FollowFeedTestURLProtocol.badge(hasNew: true)
            }
            if path.contains("/users/me/following/") {
                return FollowFeedTestURLProtocol.followStatus(following: true, pushOptIn: true)
            }
            return FollowFeedTestURLProtocol.noContent()
        }
        await feedBadgeStore.refresh()

        // Sanity: all three stores hold pre-logout state.
        XCTAssertTrue(feedBadgeStore.hasNew, "Sanity: dot is lit before logout")
        XCTAssertEqual(feedStore.items.count, 1, "Sanity: feed has items before logout")
        XCTAssertEqual(feedStore.nextCursor, "cursor-1")
        XCTAssertEqual(followStore.status, FollowStatusDTO(following: true, pushOptIn: true))

        // AppContainer.stopForLogout() order: feed → badge → follow.
        feedStore.clearForLogout()
        feedBadgeStore.clearForLogout()
        followStore.clearForLogout()

        XCTAssertTrue(feedStore.items.isEmpty, "US8: feed must be emptied on logout")
        XCTAssertNil(feedStore.nextCursor)
        XCTAssertFalse(feedStore.pageError)
        XCTAssertFalse(feedStore.isLoadingFirstPage)
        XCTAssertFalse(feedStore.isAppendingPage)
        XCTAssertFalse(feedBadgeStore.hasNew, "US8: dot must be reset on logout")
        XCTAssertNil(followStore.status, "US8: relationship state must not leak to the next login")
        XCTAssertNil(followStore.lastError)
        XCTAssertFalse(followStore.isFollowingPending)
    }

    /// No request may escape after the logout clear: a fresh empty-feed load
    /// in a clean store (fresh account) starts from a server fetch, not from
    /// resurrected in-memory state — pinning the «чужие данные не мелькают»
    /// postcondition at the store level.
    func test_logout_reset_clears_seen_echo_backlog() async {
        let feedBadgeStore = FeedBadgeStore()
        let feedStore = FeedStore()
        feedStore.bind(badgeStore: feedBadgeStore)
        let followStore = FollowStore()

        FollowFeedTestURLProtocol.handler = { _ in
            FollowFeedTestURLProtocol.badge(hasNew: true)
        }
        await feedBadgeStore.refresh()
        XCTAssertTrue(feedBadgeStore.hasNew)

        // Logout before any feed page was loaded — nothing may echo seen.
        feedStore.clearForLogout()
        feedBadgeStore.clearForLogout()
        followStore.clearForLogout()

        XCTAssertEqual(
            FollowFeedTestURLProtocol.requestCount(matching: "/api/v1/feed/seen"),
            0,
            "logout itself must never touch the server-side seen marker"
        )
        XCTAssertFalse(feedBadgeStore.hasNew)
    }
}

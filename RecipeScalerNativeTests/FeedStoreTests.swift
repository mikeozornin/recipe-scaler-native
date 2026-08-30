//
//  FeedStoreTests.swift
//  RecipeScalerNativeTests
//
//  Spec 072 — `FeedStore` pagination + «прочитано = загружено» semantics
//  (plan: Positive invariants rows 3–5, Async lifecycle row 2; spec US3/US4).
//
//  Covered:
//    - successful first page → `POST /feed/seen { seen_at: snapshotAt }` +
//      local badge extinguish (US4, `FeedStoreTests.test_first_page_marks_seen`)
//    - failed first page → no `seen`, badge untouched, `pageError` set
//      (`test_failed_first_page_does_not_mark_seen`)
//    - keyset pagination without duplicates + single-flight page loads
//      (`test_pagination_no_dupes`)
//    - epoch invalidation: a first page completing after `clearForLogout`
//      is discarded and never sends `seen`
//      (`test_first_page_after_logout_discarded`)
//    - missing `snapshotAt` skips the seen echo (client clocks untrusted)
//

import XCTest
import RecipeScalerCore
@testable import RecipeScalerNative

@MainActor
final class FeedStoreTests: XCTestCase {

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

    // MARK: - Seen echo (plan Positive invariants row 3, US4)

    func test_first_page_marks_seen() async {
        let badge = FeedBadgeStore()
        let store = FeedStore()
        store.bind(badgeStore: badge)

        FollowFeedTestURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path == "/api/v1/feed" {
                return FollowFeedTestURLProtocol.feedPage(
                    items: [FollowFeedTestURLProtocol.feedEntry(id: "r1", isNew: true)],
                    nextCursor: nil,
                    snapshotAt: "2026-08-28T10:00:00.000Z"
                )
            }
            if path == "/api/v1/feed/seen" {
                XCTAssertEqual(request.httpMethod, "POST")
                return FollowFeedTestURLProtocol.noContent()
            }
            return FollowFeedTestURLProtocol.noContent()
        }

        await store.loadFirstPage()

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.isNew, true, "US14: isNew survives decoding")
        XCTAssertNil(store.nextCursor)
        XCTAssertFalse(store.pageError)

        let seenRequests = FollowFeedTestURLProtocol.requests.filter {
            $0.request.url?.path == "/api/v1/feed/seen"
        }
        XCTAssertEqual(
            seenRequests.count,
            1,
            "exactly one seen echo must follow a successful first page"
        )
        let seenBody = seenRequests.first?.body.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        XCTAssertEqual(
            seenBody?["seen_at"] as? String,
            "2026-08-28T10:00:00.000Z",
            "the echo must carry the server snapshot, never a client clock"
        )
        XCTAssertFalse(
            badge.hasNew,
            "the dot is extinguished locally right after page-1 succeeds «прочитано = загружено»"
        )
    }

    func test_first_page_without_snapshot_skips_seen_echo() async {
        let badge = FeedBadgeStore()
        let store = FeedStore()
        store.bind(badgeStore: badge)

        FollowFeedTestURLProtocol.handler = { _ in
            FollowFeedTestURLProtocol.feedPage(items: [], nextCursor: nil, snapshotAt: nil)
        }

        await store.loadFirstPage()

        XCTAssertFalse(badge.hasNew, "the local extinguish still runs on a successful page")
        XCTAssertEqual(
            FollowFeedTestURLProtocol.requestCount(matching: "/api/v1/feed/seen"),
            0,
            "an older server without snapshot_at must not trigger a client-clock echo"
        )
    }

    // MARK: - Failed first page (plan Positive invariants row 4, US4)

    func test_failed_first_page_does_not_mark_seen() async {
        let badge = FeedBadgeStore()
        let store = FeedStore()
        store.bind(badgeStore: badge)
        // Seed the dot through the real badge pipeline: a successful refresh
        // with has_new=true. The failed feed load must leave it untouched.
        FollowFeedTestURLProtocol.handler = { _ in
            FollowFeedTestURLProtocol.badge(hasNew: true)
        }
        await badge.refresh()
        XCTAssertTrue(badge.hasNew, "Sanity: dot is lit before the failed load")

        FollowFeedTestURLProtocol.handler = { _ in
            FollowFeedTestURLProtocol.apiFailure("api.error.server-generic", status: 500)
        }

        await store.loadFirstPage()

        XCTAssertTrue(
            store.pageError,
            "a failed first page must surface pageError for the retry UI"
        )
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(
            badge.hasNew,
            "the dot must not move on a failed load (server marker untouched)"
        )
        XCTAssertEqual(
            FollowFeedTestURLProtocol.requestCount(matching: "/api/v1/feed/seen"),
            0,
            "a failed first page must never send POST /feed/seen"
        )

        // Recovery: retry succeeds → error clears, items land, echo goes out.
        FollowFeedTestURLProtocol.handler = { request in
            if request.url?.path == "/api/v1/feed" {
                return FollowFeedTestURLProtocol.feedPage(
                    items: [FollowFeedTestURLProtocol.feedEntry(id: "r1")],
                    nextCursor: nil,
                    snapshotAt: "2026-08-28T11:00:00.000Z"
                )
            }
            if request.url?.path == "/api/v1/feed/seen" {
                return FollowFeedTestURLProtocol.noContent()
            }
            return FollowFeedTestURLProtocol.badge(hasNew: false)
        }
        await store.refresh()

        XCTAssertFalse(store.pageError)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertFalse(badge.hasNew)
        XCTAssertEqual(FollowFeedTestURLProtocol.requestCount(matching: "/api/v1/feed/seen"), 1)
    }

    // MARK: - Pagination (plan Positive invariants row 5, US3)

    /// Spec 072 wire contract: page 1 carries `has_follows` and `last_seen_at`
    /// — `has_follows=false` must surface for the «нет подписок» empty state,
    /// and the seen marker becomes the client-side cutoff for cursor pages.
    func test_page1_decodes_hasFollows_and_lastSeen_cutoff() async {
        let badge = FeedBadgeStore()
        let store = FeedStore()
        store.bind(badgeStore: badge)

        FollowFeedTestURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path == "/api/v1/feed" {
                let isCursor = request.url?.query?.contains("cursor=") == true
                return FollowFeedTestURLProtocol.feedPage(
                    items: [],
                    nextCursor: isCursor ? nil : "cursor-1",
                    snapshotAt: "2026-08-28T10:00:00.000Z",
                    hasFollows: false,
                    lastSeenAt: "2026-08-27T18:00:00.000Z"
                )
            }
            return FollowFeedTestURLProtocol.noContent()
        }

        await store.loadFirstPage()

        XCTAssertEqual(
            store.hasFollows,
            false,
            "US3: has_follows=false must reach the view for the no-follows empty state"
        )
        XCTAssertEqual(
            store.lastSeenCutoff,
            "2026-08-27T18:00:00.000Z",
            "the server seen marker becomes the client isNew cutoff"
        )
    }

    /// After the page-1 seen echo the server flags the whole backlog
    /// `is_new=false` — cursor-page entries published AFTER the cutoff must
    /// get their «Новое» chip back (web parity via `lastSeenAt`).
    func test_cursor_page_marks_new_against_lastSeen_cutoff() async {
        let store = FeedStore()
        let badge = FeedBadgeStore()
        store.bind(badgeStore: badge)

        let cutoff = "2026-08-27T18:00:00.000Z"
        FollowFeedTestURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path == "/api/v1/feed" {
                let isCursor = request.url?.query?.contains("cursor=") == true
                if isCursor {
                    return FollowFeedTestURLProtocol.feedPage(
                        items: [
                            // Older than the cutoff → stays not-new.
                            FollowFeedTestURLProtocol.feedEntry(
                                id: "old", isNew: false,
                                publishedAt: "2026-08-27T09:00:00.000Z"
                            ),
                            // Newer than the cutoff → recomputed as new.
                            FollowFeedTestURLProtocol.feedEntry(
                                id: "fresh", isNew: false,
                                publishedAt: "2026-08-28T08:00:00.000Z"
                            ),
                        ],
                        nextCursor: nil,
                        snapshotAt: nil
                    )
                }
                return FollowFeedTestURLProtocol.feedPage(
                    items: [],
                    nextCursor: "cursor-1",
                    snapshotAt: "2026-08-28T10:00:00.000Z",
                    hasFollows: true,
                    lastSeenAt: cutoff
                )
            }
            return FollowFeedTestURLProtocol.noContent()
        }

        await store.loadFirstPage()
        await store.loadPage(cursor: "cursor-1")

        XCTAssertEqual(
            store.items.map(\.recipeId),
            ["old", "fresh"],
            "Sanity: both cursor-page entries landed in order"
        )
        XCTAssertEqual(
            store.items.map(\.isNew),
            [false, true],
            "entries newer than the lastSeen cutoff get the «Новое» chip back on cursor pages"
        )
    }

    func test_pagination_no_dupes() async {
        let store = FeedStore()
        let badge = FeedBadgeStore()
        store.bind(badgeStore: badge)

        // Page 1 and page 2 overlap on "shared1"/"shared2" — the store must
        // dedupe by recipeId (cursor re-delivery / server races).
        FollowFeedTestURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path == "/api/v1/feed" {
                let isCursor = request.url?.query?.contains("cursor=") == true
                if isCursor {
                    return FollowFeedTestURLProtocol.feedPage(
                        items: [
                            FollowFeedTestURLProtocol.feedEntry(id: "shared1"),
                            FollowFeedTestURLProtocol.feedEntry(id: "unique2"),
                        ],
                        nextCursor: nil,
                        snapshotAt: nil
                    )
                }
                return FollowFeedTestURLProtocol.feedPage(
                    items: [
                        FollowFeedTestURLProtocol.feedEntry(id: "first1"),
                        FollowFeedTestURLProtocol.feedEntry(id: "shared1"),
                        FollowFeedTestURLProtocol.feedEntry(id: "shared2"),
                    ],
                    nextCursor: "cursor-1",
                    snapshotAt: nil
                )
            }
            return FollowFeedTestURLProtocol.noContent()
        }

        await store.loadFirstPage()
        XCTAssertEqual(store.items.map(\.recipeId), ["first1", "shared1", "shared2"])
        XCTAssertEqual(store.nextCursor, "cursor-1")

        await store.loadPage(cursor: "cursor-1")

        XCTAssertEqual(
            store.items.map(\.recipeId),
            ["first1", "shared1", "shared2", "unique2"],
            "cursor page items must append once; overlapping ids are dropped"
        )
        XCTAssertNil(store.nextCursor, "exhausted feed clears the cursor")
        XCTAssertFalse(store.pageError)
    }

    /// Single-flight: a second `loadPage` while the first is still appending
    /// must not fire a second request for the same cursor. The plan's
    /// `test_cancelled_page_discarded` invariant is exercised on the epoch
    /// path in `test_first_page_after_logout_discarded`.
    func test_pagination_single_flight_drops_parallel_load() async {
        let store = FeedStore()
        let badge = FeedBadgeStore()
        store.bind(badgeStore: badge)

        let gate = FFDispatchGate()
        let cursorLoads = FFCounter()
        FollowFeedTestURLProtocol.handler = { [cursorLoads] request in
            let path = request.url?.path ?? ""
            if path == "/api/v1/feed" {
                if request.url?.query?.contains("cursor=") == true {
                    cursorLoads.bump()
                    gate.wait()
                    return FollowFeedTestURLProtocol.feedPage(
                        items: [FollowFeedTestURLProtocol.feedEntry(id: "p2")],
                        nextCursor: nil,
                        snapshotAt: nil
                    )
                }
                return FollowFeedTestURLProtocol.feedPage(
                    items: [FollowFeedTestURLProtocol.feedEntry(id: "p1")],
                    nextCursor: "cursor-1",
                    snapshotAt: nil
                )
            }
            return FollowFeedTestURLProtocol.noContent()
        }

        await store.loadFirstPage()
        XCTAssertEqual(store.items.count, 1)

        // First loadPage holds the append slot on the gate; the second call
        // must short-circuit without a network request.
        async let first: Void = store.loadPage(cursor: "cursor-1")
        await ffWaitUntil { cursorLoads.value == 1 }
        async let second: Void = store.loadPage(cursor: "cursor-1")
        gate.release()
        await first
        await second

        XCTAssertEqual(
            cursorLoads.value,
            1,
            "single-flight guard must drop the parallel page request"
        )
        XCTAssertEqual(store.items.map(\.recipeId), ["p1", "p2"], "only the gated page lands")
        XCTAssertNil(store.nextCursor)
    }

    // MARK: - Epoch invalidation (plan Async lifecycle row 2)

    func test_first_page_after_logout_discarded() async {
        let badge = FeedBadgeStore()
        let store = FeedStore()
        store.bind(badgeStore: badge)

        let gate = FFDispatchGate()
        let loadStarted = FFCounter()
        FollowFeedTestURLProtocol.handler = { [loadStarted] request in
            if request.url?.path == "/api/v1/feed" {
                loadStarted.bump()
                gate.wait()
                return FollowFeedTestURLProtocol.feedPage(
                    items: [FollowFeedTestURLProtocol.feedEntry(id: "r1", isNew: true)],
                    nextCursor: nil,
                    snapshotAt: "2026-08-28T12:00:00.000Z"
                )
            }
            return FollowFeedTestURLProtocol.noContent()
        }

        let loadTask = Task { await store.loadFirstPage() }
        // Logout happens while the page request is still in flight: wait
        // until the transport has actually dispatched the feed request.
        await ffWaitUntil { loadStarted.value == 1 }
        store.clearForLogout()
        gate.release()
        await loadTask.value

        XCTAssertTrue(
            store.items.isEmpty,
            "a page completing after clearForLogout must be discarded (epoch bump)"
        )
        XCTAssertNil(store.nextCursor)
        XCTAssertFalse(store.pageError)
        XCTAssertEqual(
            FollowFeedTestURLProtocol.requestCount(matching: "/api/v1/feed/seen"),
            0,
            "the discarded page must never echo seen — the server marker stays with the old account"
        )
    }

    /// Cursor page completing after logout is discarded the same way.
    func test_cursor_page_after_logout_discarded() async {
        let store = FeedStore()
        let badge = FeedBadgeStore()
        store.bind(badgeStore: badge)
        FollowFeedTestURLProtocol.handler = { _ in
            FollowFeedTestURLProtocol.feedPage(items: [], nextCursor: "cursor-1", snapshotAt: nil)
        }
        await store.loadFirstPage()
        XCTAssertEqual(store.items.count, 0)
        XCTAssertEqual(store.nextCursor, "cursor-1")

        let gate = FFDispatchGate()
        let pageStarted = FFCounter()
        FollowFeedTestURLProtocol.handler = { [pageStarted] request in
            if request.url?.query?.contains("cursor=") == true {
                pageStarted.bump()
                gate.wait()
                return FollowFeedTestURLProtocol.feedPage(
                    items: [FollowFeedTestURLProtocol.feedEntry(id: "late")],
                    nextCursor: nil,
                    snapshotAt: nil
                )
            }
            return FollowFeedTestURLProtocol.feedPage(items: [], nextCursor: "cursor-1", snapshotAt: nil)
        }

        let pageTask = Task { await store.loadPage(cursor: "cursor-1") }
        await ffWaitUntil { pageStarted.value == 1 }
        store.clearForLogout()
        gate.release()
        await pageTask.value

        XCTAssertTrue(store.items.isEmpty, "the late cursor page must not resurrect the old feed")
        XCTAssertNil(store.nextCursor)
    }
}

/// Synchronous counter the URLProtocol handler can bump from the transport
/// queue; the main-actor test reads it later.
final class FFCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func bump() {
        lock.withLock { count += 1 }
    }

    var value: Int {
        lock.withLock { count }
    }
}

/// DispatchSemaphore-backed gate for the synchronous URLProtocol handler:
/// the handler blocks the transport queue until the test releases it. This is
/// what creates a real mid-flight window for stale-completion and
/// single-flight assertions (the async `AsyncTestGate.Gate` cannot be awaited
/// from the sync handler).
final class FFDispatchGate: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)

    func wait() {
        _ = semaphore.wait(timeout: .now() + 10)
    }

    func release() {
        semaphore.signal()
    }
}


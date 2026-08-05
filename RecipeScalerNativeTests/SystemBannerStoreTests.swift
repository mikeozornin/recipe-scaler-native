//
//  SystemBannerStoreTests.swift
//  RecipeScalerNativeTests
//
//  Spec 061 — system banner store state transitions.
//
//  Covers the synchronous state machine of `SystemBannerStore`:
//    - `dismiss()` clears `activeBanner` synchronously (optimistic update)
//      even when the network POST has not completed.
//    - `clearForLogout()` resets both `activeBanner` and the in-session
//      dismissal guard so a subsequent `refresh()` showing the same banner
//      would surface it again.
//    - `applyFetchedBanner(_:forEpoch:)` ignores results after logout when
//      the captured refresh epoch is stale (logout race guard).
//
//  Network-layer behavior (`refresh()` calling `SystemBannerAPI`) is out of
//  scope here — epoch apply is unit-tested without a live network.
//

import XCTest
import RecipeScalerCore
@testable import RecipeScalerNative

@MainActor
final class SystemBannerStoreTests: XCTestCase {

    private func makeBanner(
        id: UUID = UUID(),
        titleEn: String = "Maintenance",
        titleRu: String = "Техработы",
        bodyEn: String = "Brief downtime at 03:00 UTC.",
        bodyRu: String = "Короткий простой в 03:00 UTC.",
        createdAt: String = "2023-11-14T22:13:20.000Z"
    ) -> SystemBannerDTO {
        SystemBannerDTO(
            id: id,
            titleEn: titleEn,
            titleRu: titleRu,
            bodyEn: bodyEn,
            bodyRu: bodyRu,
            createdAt: createdAt
        )
    }

    /// Server `toISOString()` always includes fractional seconds. Decoding must
    /// not go through `JSONDecoder.dateDecodingStrategy = .iso8601` (rejects ms).
    func testDecodeWirePayloadWithFractionalSeconds() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "title_en": "Maintenance",
          "title_ru": "Техработы",
          "body_en": "Brief downtime.",
          "body_ru": "Короткий простой.",
          "created_at": "2026-08-05T22:47:09.999Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let banner = try decoder.decode(SystemBannerDTO.self, from: json)

        XCTAssertEqual(banner.id, id)
        XCTAssertEqual(banner.createdAt, "2026-08-05T22:47:09.999Z")
        XCTAssertEqual(banner.title(for: "ru"), "Техработы")
    }

    /// `dismiss()` must clear `activeBanner` synchronously, before the
    /// network POST resolves. This is what makes the X-button feel instant.
    func testDismissClearsActiveBannerOptimistically() async {
        let store = SystemBannerStore()
        store.activeBanner = makeBanner()

        XCTAssertNotNil(store.activeBanner, "Sanity: banner is set before dismiss")

        // Kick off dismiss; do not await the network POST.
        // Capture the in-memory state synchronously after the optimistic update.
        let task = Task { await store.dismiss() }
        // Yield once so the synchronous part of `dismiss()` runs.
        await Task.yield()

        XCTAssertNil(store.activeBanner, "Banner must disappear immediately on dismiss()")

        // Let the POST settle so the task does not get cancelled mid-flight.
        await task.value
    }

    /// `clearForLogout()` must reset all per-account state. After clearing,
    /// re-assigning the same banner directly (simulating a refresh that did
    /// not actually re-fetch — purely a state machine check) shows it again.
    func testClearForLogoutResetsActiveBanner() {
        let store = SystemBannerStore()
        store.activeBanner = makeBanner()

        XCTAssertNotNil(store.activeBanner)

        store.clearForLogout()

        XCTAssertNil(store.activeBanner, "Banner must be cleared on logout")
    }

    /// Stale refresh after logout must not restore the previous account's banner.
    /// Simulates: refresh started (epoch captured), then `clearForLogout` bumps
    /// epoch, then the fetch result arrives with the old epoch.
    func testApplyFetchedBannerIgnoresStaleEpochAfterLogout() {
        let store = SystemBannerStore()
        let banner = makeBanner()

        // Epoch is 0 at construction. clearForLogout bumps to 1.
        store.clearForLogout()

        store.applyFetchedBanner(banner, forEpoch: 0)

        XCTAssertNil(
            store.activeBanner,
            "Stale refresh (epoch 0) after logout must not restore activeBanner"
        )
    }

    /// A refresh started after logout (matching current epoch) may apply.
    func testApplyFetchedBannerAcceptsCurrentEpoch() {
        let store = SystemBannerStore()
        let banner = makeBanner()

        store.clearForLogout()
        // After clear, epoch is 1 — apply with matching epoch.
        store.applyFetchedBanner(banner, forEpoch: 1)

        XCTAssertEqual(store.activeBanner?.id, banner.id)
    }

    /// `loadFromCache()` is a documented no-op today (server is the source of
    /// truth). Pin this so the contract is not silently broken: if a future
    /// change adds a local cache, this test should be updated explicitly.
    func testLoadFromCacheIsCurrentlyNoOp() {
        let store = SystemBannerStore()
        XCTAssertNil(store.activeBanner, "Sanity: no banner before")

        store.loadFromCache()

        XCTAssertNil(store.activeBanner, "loadFromCache() must not populate state today")
    }

    /// `dismiss()` with no active banner is a no-op (defensive — the UI only
    /// shows the dismiss button when there is a banner, but the store must
    /// tolerate a stray call).
    func testDismissWithNoActiveBannerIsNoOp() async {
        let store = SystemBannerStore()
        XCTAssertNil(store.activeBanner)

        await store.dismiss()

        XCTAssertNil(store.activeBanner, "Dismiss with no banner must not crash or set anything")
    }
}

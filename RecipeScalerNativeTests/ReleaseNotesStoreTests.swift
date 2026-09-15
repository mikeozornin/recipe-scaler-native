//
//  ReleaseNotesStoreTests.swift
//  RecipeScalerNativeTests
//
//  Spec 077 — lastViewed seed, banner, sheet expand-before-write.
//

import XCTest
@testable import RecipeScalerNative

@MainActor
final class ReleaseNotesStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ReleaseNotesStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_missing_key_seeds_max_no_banner() {
        let store = ReleaseNotesStore(defaults: defaults, catalog: notes(through: 3))

        XCTAssertEqual(store.lastViewed, 3)
        XCTAssertFalse(store.showsBanner)
        XCTAssertEqual(defaults.integer(forKey: ReleaseNotesStore.lastViewedDefaultsKey), 3)
    }

    func test_caught_up_hides_banner() {
        defaults.set(3, forKey: ReleaseNotesStore.lastViewedDefaultsKey)
        let store = ReleaseNotesStore(defaults: defaults, catalog: notes(through: 3))

        XCTAssertFalse(store.showsBanner)
        XCTAssertEqual(store.lastViewed, 3)
    }

    func test_higher_max_shows_banner() {
        defaults.set(3, forKey: ReleaseNotesStore.lastViewedDefaultsKey)
        let store = ReleaseNotesStore(defaults: defaults, catalog: notes(through: 4))

        XCTAssertTrue(store.showsBanner)
        XCTAssertEqual(store.latestNote?.version, 4)
        XCTAssertEqual(store.latestNote?.title(for: "en"), "Title 4")
        XCTAssertEqual(store.latestNote?.title(for: "ru"), "Заголовок 4")
    }

    func test_dismiss_writes_max() {
        defaults.set(3, forKey: ReleaseNotesStore.lastViewedDefaultsKey)
        let store = ReleaseNotesStore(defaults: defaults, catalog: notes(through: 4))

        store.dismissBanner()

        XCTAssertEqual(store.lastViewed, 4)
        XCTAssertFalse(store.showsBanner)
        XCTAssertEqual(defaults.integer(forKey: ReleaseNotesStore.lastViewedDefaultsKey), 4)
    }

    func test_open_sheet_writes_max() {
        defaults.set(3, forKey: ReleaseNotesStore.lastViewedDefaultsKey)
        let store = ReleaseNotesStore(defaults: defaults, catalog: notes(through: 4))

        store.presentSheet()

        XCTAssertEqual(store.lastViewed, 4)
        XCTAssertTrue(store.isSheetPresented)
        XCTAssertFalse(store.showsBanner)
    }

    func test_unread_expanded_before_mark() {
        defaults.set(2, forKey: ReleaseNotesStore.lastViewedDefaultsKey)
        let store = ReleaseNotesStore(defaults: defaults, catalog: notes(through: 4))

        store.presentSheet()

        XCTAssertEqual(store.expandedVersions, [3, 4])
        XCTAssertEqual(store.lastViewed, 4)
        XCTAssertTrue(store.isExpanded(3))
        XCTAssertTrue(store.isExpanded(4))
        XCTAssertFalse(store.isExpanded(1))
        XCTAssertFalse(store.isExpanded(2))
    }

    func test_empty_catalog_hides_surfaces() {
        let store = ReleaseNotesStore(defaults: defaults, catalog: [])

        XCTAssertFalse(store.showsBanner)
        XCTAssertFalse(store.hasArchiveRow)
        XCTAssertEqual(store.lastViewed, 0)
        XCTAssertEqual(defaults.integer(forKey: ReleaseNotesStore.lastViewedDefaultsKey), 0)
    }

    func test_empty_catalog_gesture_does_not_invent_notes() {
        let store = ReleaseNotesStore(defaults: defaults, catalog: [])
        store.presentSheet()
        store.dismissBanner()

        XCTAssertFalse(store.isSheetPresented)
        XCTAssertEqual(store.lastViewed, 0)
        XCTAssertTrue(store.expandedVersions.isEmpty)
    }

    func test_logout_does_not_reset_last_viewed() {
        defaults.set(4, forKey: ReleaseNotesStore.lastViewedDefaultsKey)
        let before = ReleaseNotesStore(defaults: defaults, catalog: notes(through: 4))
        XCTAssertEqual(before.lastViewed, 4)

        // Logout must not touch this key. A new store on the same defaults
        // (cold start after account switch) still reads 4.
        let after = ReleaseNotesStore(defaults: defaults, catalog: notes(through: 4))
        XCTAssertEqual(after.lastViewed, 4)
        XCTAssertEqual(defaults.integer(forKey: ReleaseNotesStore.lastViewedDefaultsKey), 4)
    }

    func test_corrupt_key_seeds_like_missing() {
        defaults.set("nope", forKey: ReleaseNotesStore.lastViewedDefaultsKey)
        let store = ReleaseNotesStore(defaults: defaults, catalog: notes(through: 3))

        XCTAssertEqual(store.lastViewed, 3)
        XCTAssertFalse(store.showsBanner)
    }

    func test_reinit_does_not_lower_existing_last_viewed() {
        defaults.set(5, forKey: ReleaseNotesStore.lastViewedDefaultsKey)
        let store = ReleaseNotesStore(defaults: defaults, catalog: notes(through: 3))

        XCTAssertEqual(store.lastViewed, 5)
        XCTAssertFalse(store.showsBanner)
    }

    private func notes(through max: Int) -> [IOSReleaseNote] {
        (1...max).map { version in
            IOSReleaseNote(
                version: version,
                date: Date(timeIntervalSince1970: 1_700_000_000 + Double(version)),
                titleEn: "Title \(version)",
                titleRu: "Заголовок \(version)",
                bodyEn: "Body \(version)",
                bodyRu: "Текст \(version)"
            )
        }
    }
}

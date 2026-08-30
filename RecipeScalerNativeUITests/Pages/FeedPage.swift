//
//  FeedPage.swift
//  RecipeScalerNativeUITests
//
//  Spec 072 page object for the Discover «Моя лента» segment and the follow
//  controls on a public profile. Locators mirror the app-side catalog
//  (`AccessibilityIdentifiers`, spec 072 kebab-case a11y ids).
//
//  Spec coverage (scenarios themselves are implemented in future specs once
//  REST fixtures for follow/feed exist on the E2E backend):
//    - US1 — Подписка: openProfile → followButton() → tapFollow()
//    - US2 — Колокольчик: followMenu() → tapMenuSubscribeNotifications()
//    - US3 — Лента: openFollowingSegment() → feedCards(), autoLoadFooter(),
//      retryPageButton() (inline «Повторить»)
//    - US4 — Точка нового: after a successful first page the segment dot /
//      badge extinguish (server-driven; asserted indirectly via feed readiness)
//    - US14 — Подсветка новых: newBadges() on `isNew` feed cards
//
//  Usage: launch as a logged-in user, `Navigation.openTab(.discover, …)`,
//  then `FeedPage(app:).awaitReady()`.
//

import XCTest

/// Discover feed segment («Моя лента») + follow controls page object.
struct FeedPage: Page {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Segment header («Подборки | Моя лента»)

    /// The segmented picker. SwiftUI exposes segmented pickers as buttons per
    /// segment; the container id is matched via `.any` (picker/button/other).
    var segment: XCUIElement {
        app.descendants(matching: .any)[UIA.discoverFeedSegment].firstMatch
    }

    /// «Моя лента» segment button (second segment of the picker). Falls back
    /// to the localized segment title (EN) when the id lands on an inner view.
    var followingSegmentButton: XCUIElement {
        let byId = app.descendants(matching: .any)[UIA.discoverFeedSegment]
            .buttons.element(boundBy: 1)
        if byId.exists { return byId }
        return app.buttons["My Feed"].firstMatch
    }

    // MARK: - Feed list

    /// Feed container (ScrollView / empty-state / loading / error — all carry
    /// the same list id so readiness is state-agnostic).
    var feedList: XCUIElement {
        app.descendants(matching: .any)[UIA.discoverFeedList].firstMatch
    }

    var feedCards: XCUIElementQuery {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@", UIA.discoverFeedCard)
        )
    }

    var firstCard: XCUIElement { feedCards.firstMatch }

    func card(atIndex index: Int) -> XCUIElement {
        feedCards.element(boundBy: index)
    }

    /// Red «Новое» chip (US14) — one per `isNew` card, matched above the
    /// preview image of the card.
    var newBadges: XCUIElementQuery {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@", UIA.discoverFeedCardNewBadge)
        )
    }

    var firstNewBadge: XCUIElement { newBadges.firstMatch }

    /// Inline retry footer / auto-load sentinel at the list tail. When the
    /// page failed, the retry button lives inside this container.
    var autoLoadFooter: XCUIElement {
        app.descendants(matching: .any)[UIA.discoverFeedAutoLoad].firstMatch
    }

    /// «Повторить» button for a failed cursor page (US3: no auto-retry).
    var retryPageButton: XCUIElement {
        app.buttons["Retry"].firstMatch
    }

    /// «Повторить» button for a failed first page (error empty state).
    var retryFirstPageButton: XCUIElement {
        app.buttons["Retry"].firstMatch
    }

    // MARK: - Follow controls (public profile)

    var followButton: XCUIElement {
        app.buttons[UIA.followButton].firstMatch
    }

    /// Subscription dropdown (visible only while `following == true`).
    var followMenu: XCUIElement {
        app.descendants(matching: .any)[UIA.followMenu].firstMatch
    }

    func menuButton(_ identifier: String) -> XCUIElement {
        app.buttons[identifier].firstMatch
    }

    var menuUnsubscribe: XCUIElement { menuButton(UIA.followMenuUnsubscribe) }
    var menuSubscribeOnly: XCUIElement { menuButton(UIA.followMenuSubscribeOnly) }
    var menuSubscribeNotifications: XCUIElement { menuButton(UIA.followMenuSubscribeNotifications) }

    // MARK: - Actions

    @discardableResult
    func awaitReady(timeout: TimeInterval = Wait.element) -> Self {
        awaitRoot(segment, timeout: timeout, "Feed segment picker")
        return self
    }

    /// Opens the «Моя лента» segment and waits for the feed container.
    @discardableResult
    func openFollowingSegment(timeout: TimeInterval = Wait.element) -> Self {
        followingSegmentButton.tap()
        awaitRoot(feedList, timeout: timeout, "Feed list")
        return self
    }

    @discardableResult
    func tapFollow(timeout: TimeInterval = Wait.element) -> Self {
        Wait.hittable(followButton, timeout: timeout).tap()
        // Successful follow swaps the button for the dropdown menu.
        _ = followMenu.waitForExistence(timeout: timeout)
        return self
    }

    /// Opens the subscription dropdown (US2 entry point).
    @discardableResult
    func openFollowMenu(timeout: TimeInterval = Wait.element) -> Self {
        Wait.hittable(followMenu, timeout: timeout).tap()
        return self
    }

    /// Pull-to-refresh on the feed list.
    func pullToRefresh() {
        let start = feedList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let end = feedList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        start.press(forDuration: 0.05, thenDragTo: end)
    }
}

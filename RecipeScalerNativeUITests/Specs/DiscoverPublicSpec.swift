import XCTest

/// Spec coverage: specs/011-discover/spec.md
///
/// Web parity: tests/e2e/specs/011-discover-public.spec.ts
///
///   - US1 — Discover root renders with cards
///   - US2 — Search field present (soft-skip when feed has no search UI)
///   - US3 — Public collection/profile cards visible (depends on server content)
///
/// Spec coverage: specs/082-discover-author-cards/spec.md
///
///   - 082 US1 — author «Обложка» card is one button «{name}, {N recipes}»
///   - 082 US2 — a tap on a collage photo or on the name opens the author page (SC-004)
final class DiscoverPublicSpec: BaseTestCase {
    func test_US1_discoverRootRenders() {
        Navigation.openTab(.discover, in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)[UIA.discoverRoot].waitForExistence(timeout: Wait.firstPaint),
            "Discover root did not render"
        )
    }

    func test_US2_searchFieldPresent() throws {
        Navigation.openTab(.discover, in: app)
        _ = discoverPage.awaitReady()
        // Search field is rendered only when content exists. For a fresh
        // empty user the discover feed may legitimately have no search UI —
        // this is genuinely env-dependent (server content), so keep the
        // soft-skip here. NOT a regression. See review finding Critical #5
        // (env-conditional skips are legitimate; UI-a11y-id-missing skips
        // are not — DiscoverPublicSpec is the former).
        let collectionSearch = discoverPage.collectionSearchField.waitForExistence(timeout: Wait.element)
        let profileSearch = discoverPage.profileSearchField.exists
        try XCTSkipIf(
            !(collectionSearch || profileSearch),
            "No discover search field — feed has no public content for fresh user (env-conditional)"
        )
    }

    // MARK: - Spec 082 — author cards

    func test_082_US1_authorCardVisible() throws {
        Navigation.openTab(.discover, in: app)
        _ = discoverPage.awaitReady()
        let card = discoverPage.firstProfileCard
        try XCTSkipIf(
            !card.waitForExistence(timeout: Wait.element),
            "No public authors in Discover (env-conditional)"
        )
        XCTAssertEqual(card.elementType, .button, "The author card must be one button")
        XCTAssertTrue(
            card.label.contains(", "),
            "The card must read «{name}, {N recipes}», got «\(card.label)»"
        )
    }

    /// SC-004: the collage is part of the card's single tap target, not a link to a recipe.
    func test_082_US2_tapAuthorPhotoOpensProfile() throws {
        Navigation.openTab(.discover, in: app)
        _ = discoverPage.awaitReady()
        try XCTSkipIf(
            !discoverPage.firstProfileCard.waitForExistence(timeout: Wait.element),
            "No public authors in Discover (env-conditional)"
        )
        let photo = discoverPage.firstAuthorCardPhoto
        try XCTSkipIf(
            !discoverPage.scrollToReveal(photo),
            "No author with recipe photos in Discover (env-conditional)"
        )
        let username = Self.username(fromPhotoIdentifier: photo.identifier)
        photo.tap()
        assertAuthorPageOpened(username: username)
    }

    func test_082_US2_tapAuthorNameOpensProfile() throws {
        Navigation.openTab(.discover, in: app)
        _ = discoverPage.awaitReady()
        let card = discoverPage.firstProfileCard
        try XCTSkipIf(
            !card.waitForExistence(timeout: Wait.element),
            "No public authors in Discover (env-conditional)"
        )
        let username = String(card.identifier.dropFirst(UIA.discoverAuthorCardPrefix.count))
        // The first text of the card is the name: the collage and the avatar are images.
        let name = card.staticTexts.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: Wait.element), "The author card has no name")
        discoverPage.scrollToReveal(name)
        name.tap()
        assertAuthorPageOpened(username: username)
    }

    /// `discover.author-card.{username}.photo.{index}` → `username`.
    private static func username(fromPhotoIdentifier identifier: String) -> String {
        let withoutPrefix = identifier.dropFirst(UIA.discoverAuthorCardPrefix.count)
        guard let marker = withoutPrefix.range(of: UIA.discoverAuthorCardPhotoMarker, options: .backwards) else {
            return String(withoutPrefix)
        }
        return String(withoutPrefix[..<marker.lowerBound])
    }

    private func assertAuthorPageOpened(
        username: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            discoverPage.profileHeader.waitForExistence(timeout: Wait.firstPaint),
            "The author page did not open",
            file: file,
            line: line
        )
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label == %@", "@\(username)")).firstMatch
                .waitForExistence(timeout: Wait.element),
            "The opened page is not @\(username)'s",
            file: file,
            line: line
        )
    }
}

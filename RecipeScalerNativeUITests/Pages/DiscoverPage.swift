import XCTest

/// Discover screen (`-OpenTab=discover`).
///
/// Web parity: `discover` namespace in `helpers/selectors.ts`.
struct DiscoverPage: Page {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    var root: XCUIElement { app.descendants(matching: .any)[UIA.discoverRoot] }
    var collectionSearchField: XCUIElement {
        let direct = app.searchFields[UIA.discoverCollectionSearchField]
        if direct.exists { return direct }
        // Fallback: SwiftUI may type it as a generic textField.
        return app.textFields[UIA.discoverCollectionSearchField]
    }
    var profileSearchField: XCUIElement {
        let direct = app.searchFields[UIA.discoverProfileSearchField]
        if direct.exists { return direct }
        return app.textFields[UIA.discoverProfileSearchField]
    }

    var firstCollectionCard: XCUIElement {
        app.descendants(matching: .any)[UIA.discoverCollectionCard].firstMatch
    }
    /// Author cards (spec 082): `discover.author-card.{username}`, without their photo tiles.
    var authorCards: XCUIElementQuery {
        app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND NOT (identifier CONTAINS %@)",
                UIA.discoverAuthorCardPrefix,
                UIA.discoverAuthorCardPhotoMarker
            )
        )
    }
    var firstProfileCard: XCUIElement { authorCards.firstMatch }
    func authorCard(username: String) -> XCUIElement {
        app.descendants(matching: .any)[UIA.discoverAuthorCard(username: username)]
    }
    /// First collage tile (`.photo.0`) of the first author card on screen that has photos.
    var firstAuthorCardPhoto: XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@",
                UIA.discoverAuthorCardPrefix,
                "\(UIA.discoverAuthorCardPhotoMarker)0"
            )
        ).firstMatch
    }
    /// The page an author card opens (`DiscoverPublicProfileView`).
    var profileHeader: XCUIElement {
        app.descendants(matching: .any)[UIA.discoverProfileHeader]
    }
    var firstRecipeCard: XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", UIA.discoverRecipeCardPrefix))
            .firstMatch
    }
    func recipeCard(id: String) -> XCUIElement {
        app.descendants(matching: .any)[UIA.discoverRecipeCard(id: id)]
    }
    var firstRecipeCloneButton: XCUIElement {
        app.buttons[UIA.discoverRecipeCloneButton].firstMatch
    }

    @discardableResult
    func awaitReady(timeout: TimeInterval = Wait.element) -> Self {
        awaitRoot(root, timeout: timeout, "Discover")
        return self
    }

    /// Scrolls «Подборки» until `element` is on screen with its center clear of the navigation
    /// bar and the floating tab bar. Cards live in lazy grids: one below the fold is not in the
    /// tree until scrolled to. `false` when it never shows up.
    @discardableResult
    func scrollToReveal(_ element: XCUIElement, maxDrags: Int = 8) -> Bool {
        for _ in 0 ... maxDrags {
            if element.exists {
                let midY = element.frame.midY
                let screen = app.frame
                if midY > screen.minY + screen.height * 0.2, midY < screen.minY + screen.height * 0.7 {
                    return true
                }
            }
            let start = root.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let end = root.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        return element.exists
    }
}

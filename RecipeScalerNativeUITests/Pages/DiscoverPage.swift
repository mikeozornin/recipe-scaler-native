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
    var firstProfileCard: XCUIElement {
        app.descendants(matching: .any)[UIA.discoverProfileCard].firstMatch
    }
    var firstRecipeCard: XCUIElement {
        app.descendants(matching: .any)[UIA.discoverRecipeCard].firstMatch
    }
    var firstRecipeCloneButton: XCUIElement {
        app.buttons[UIA.discoverRecipeCloneButton].firstMatch
    }

    @discardableResult
    func awaitReady(timeout: TimeInterval = Wait.element) -> Self {
        awaitRoot(root, timeout: timeout, "Discover")
        return self
    }
}

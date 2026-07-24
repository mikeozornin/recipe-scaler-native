import XCTest

/// Collections (folders) root screen.
///
/// Web parity: `collections` namespace in `helpers/selectors.ts`.
struct CollectionsPage: Page {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    var root: XCUIElement { app.descendants(matching: .any)[UIA.collectionsRoot] }
    var newRow: XCUIElement { app.buttons[UIA.collectionsNewRow] }
    var viewModeToggle: XCUIElement { app.buttons[UIA.collectionsViewModeToggle] }

    func row(id: String) -> XCUIElement { app.buttons[UIA.collectionsRootRow(folderId: id)] }
    func gridTile(id: String) -> XCUIElement { app.buttons[UIA.collectionsRootGridTile(folderId: id)] }

    var firstRow: XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", UIA.collectionsRootRowPrefix)
        ).firstMatch
    }

    @discardableResult
    func awaitReady(timeout: TimeInterval = Wait.element) -> Self {
        awaitRoot(root, timeout: timeout, "Collections")
        return self
    }
}

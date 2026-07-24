import XCTest

/// Tab navigation helpers.
///
/// Web parity: `tests/e2e/helpers/nav.ts` (`gotoHash`) and
/// `helpers/selectors.ts` tab namespaces. Native uses tab bar buttons with
/// `tab_<name>` accessibility identifiers. On some iOS 26 builds the id
/// collapses onto an inner container — fall back to the localized label.
enum Navigation {
    enum Tab: String {
        case recipes
        case shopping
        case discover
        case profile
        case importTab = "import"

        var accessibilityId: String {
            switch self {
            case .recipes: return UIA.tabRecipes
            case .shopping: return UIA.tabShopping
            case .discover: return UIA.tabDiscover
            case .profile: return UIA.tabProfile
            case .importTab: return UIA.tabImport
            }
        }

        /// Visible tab-bar label (EN). Used when a11y id is not on the Button.
        var labelFallback: String {
            switch self {
            case .recipes: return "Recipes"
            case .shopping: return "Shopping"
            case .discover: return "Discover"
            case .profile: return "Profile"
            case .importTab: return "Import"
            }
        }
    }

    /// Tap a tab bar button. Retries when not hittable; falls back to label.
    ///
    /// Does NOT wait `firstPaint` per call (would block 45s × N specs on a
    /// broken build). The first call after launch relies on `BaseTestCase`
    /// having already triggered launch + an implicit wait through page
    /// accessors. See review finding Performance Critical #4.
    static func openTab(_ tab: Tab, in app: XCUIApplication) {
        // Short warm-up: any tab bar button exists at all (10s, not 45s).
        let anyTab = app.buttons[UIA.tabRecipes]
        if !anyTab.waitForExistence(timeout: Wait.element) {
            _ = app.buttons[tab.labelFallback].waitForExistence(timeout: Wait.element)
        }

        var button = app.buttons[tab.accessibilityId]
        if !button.waitForExistence(timeout: Wait.element) {
            button = app.buttons[tab.labelFallback]
        }
        guard button.waitForExistence(timeout: Wait.element) else {
            XCTFail("Tab button not found: \(tab.rawValue)")
            return
        }
        for attempt in 0..<3 {
            if button.isHittable {
                button.tap()
                return
            }
            _ = button.waitForExistence(timeout: 0.5)
            if attempt == 2 {
                let coord = button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                coord.tap()
            }
        }
    }

    /// Pop one level back via the navigation bar back button.
    static func goBack(in app: XCUIApplication) {
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.waitForExistence(timeout: 3) {
            backButton.tap()
        }
    }
}

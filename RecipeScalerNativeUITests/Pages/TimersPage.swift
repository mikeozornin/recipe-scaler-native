import XCTest

/// Timer panel (mobile bottom sheet + watch).
///
/// Web parity: `timers` namespace in `helpers/selectors.ts`.
struct TimersPage: Page {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    var panel: XCUIElement { app.descendants(matching: .any)[UIA.mobileTimerPanel] }
    var panelHeader: XCUIElement { app.descendants(matching: .any)[UIA.mobileTimerPanelHeader] }

    func chip(timerId: String) -> XCUIElement {
        app.otherElements[UIA.mobileTimerChip(timerId: timerId)]
    }

    func toggle(timerId: String) -> XCUIElement {
        app.buttons[UIA.mobileTimerToggle(timerId: timerId)]
    }

    func delete(timerId: String) -> XCUIElement {
        app.buttons[UIA.mobileTimerDelete(timerId: timerId)]
    }

    /// Locate a timer chip by visible name (since IDs are UUIDs from server).
    func chipByName(_ name: String) -> XCUIElement {
        app.otherElements.containing(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
    }

    @discardableResult
    func awaitPanel(timeout: TimeInterval = Wait.element) -> Self {
        awaitRoot(panel, timeout: timeout, "Timer panel")
        return self
    }
}

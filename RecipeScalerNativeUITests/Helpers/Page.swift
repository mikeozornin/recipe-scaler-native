import XCTest

/// Base page-object protocol. Mirrors web's `tests/e2e/helpers/selectors.ts`
/// pattern — each page knows how to find its own elements via accessibility
/// identifiers, exposing typed accessors to specs.
protocol Page {
    var app: XCUIApplication { get }
    init(app: XCUIApplication)
}

extension Page {
    /// Convenience: wait for a known root-level element that proves the page
    /// is on screen before any further interaction.
    func awaitRoot(_ element: XCUIElement, timeout: TimeInterval = Wait.firstPaint, _ name: String) {
        guard element.waitForExistence(timeout: timeout) else {
            XCTFail("\(name) did not appear within \(Int(timeout))s")
            return
        }
    }
}

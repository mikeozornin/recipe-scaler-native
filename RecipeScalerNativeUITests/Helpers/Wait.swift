import XCTest

/// Deterministic wait helpers for UI tests.
///
/// Web parity: `tests/e2e/helpers/yjs-sync.ts` (`waitForSync`) and
/// `helpers/overlays.ts` (`dismissOverlays`). On native we don't have a
/// `window.__yjsSynced` bridge, so waits are `waitForExistence` with
/// realistic timeouts calibrated against the sync handshake (3–8 s typical,
/// up to 30 s on a cold debug build with logs).
enum Wait {
    /// Standard timeout for an element to appear after a tap/navigation.
    static let element: TimeInterval = 10

    /// Extended timeout for first-paint after launch (collection hydrate +
    /// socket auth ack). Use only for the very first list-load assertion.
    /// Calibrated from 45s → 25s: with `-SkipSplash=1` and DEBUG-only E2E
    /// overrides, cold-launch first paint on CI rarely exceeds 20s. Slower
    /// flows can still override via `timeout:` argument. See review finding
    /// Performance Medium.
    static let firstPaint: TimeInterval = 25

    /// Sync round-trip timeout (after REST seed → app should reflect it).
    /// Calibrated from 30s → 20s. Slower flows (Discover, PushNotifications)
    /// override via `timeout:` argument. See review finding Performance Medium.
    static let syncRoundTrip: TimeInterval = 20

    /// Wait for `element` to exist, failing the test with `message` if not.
    static func exists(
        _ element: XCUIElement,
        timeout: TimeInterval = element,
        _ message: @autoclosure () -> String = ""
    ) {
        guard element.waitForExistence(timeout: timeout) else {
            XCTFail(message().isEmpty ? "Element not found: \(element.label)" : message())
            return
        }
    }

    /// Wait for `element` to become hittable, then return it for chaining.
    @discardableResult
    static func hittable(
        _ element: XCUIElement,
        timeout: TimeInterval = element
    ) -> XCUIElement {
        let predicate = NSPredicate(format: "isHittable == YES")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        if result != .completed {
            XCTFail("Element not hittable within \(timeout)s: \(element.label)")
        }
        return element
    }
}

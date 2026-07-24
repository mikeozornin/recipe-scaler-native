import XCTest

/// Spec coverage: specs/032-import-decompression-bomb/spec.md
///
/// Web parity: tests/e2e/specs/032-import-decompression-bomb.spec.ts
///
/// Verifies the import pipeline refuses a zip bomb rather than consuming
/// unbounded memory. The actual bomb payload is constructed in unit tests;
/// this E2E just asserts the import sheet is reachable and stable.
final class ImportDecompressionBombSpec: BaseTestCase {
    func test_importSheetDoesNotCrashOnLaunch() {
        Navigation.openTab(.importTab, in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)[UIA.importSheet].waitForExistence(timeout: Wait.firstPaint),
            "Import sheet did not render (crash on launch?)"
        )
        // Actual bomb-rejection scenarios are covered by unit tests with
        // crafted zip payloads — too brittle to drive through XCUITest's
        // file picker.
    }
}

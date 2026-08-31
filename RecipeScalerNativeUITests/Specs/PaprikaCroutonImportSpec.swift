import XCTest

/// Spec coverage: specs/027-paprika-crouton-import/spec.md
///
/// Web parity: tests/e2e/specs/027-paprika-crouton-import.spec.ts
///
/// Migration hint for Paprika/Crouton exports and own-format round-trip.
/// Full file-format round-trip is covered by unit tests; this E2E only
/// verifies the import-sheet migration banner.
///
/// Spec 074: Import left the tab bar; presented via `-OpenTab=import`.
final class PaprikaCroutonImportSpec: BaseTestCase {
    override func extraLaunchArguments() -> [String] {
        super.extraLaunchArguments() + ["-OpenTab", "import"]
    }

    func test_importSheetRenders() {
        Navigation.awaitImportSheet(in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)[UIA.importSheet].waitForExistence(timeout: Wait.firstPaint),
            "Import sheet did not render"
        )
    }
}

import XCTest

/// Spec coverage: specs/020-account-telegram-export/spec.md
///
/// Web parity: tests/e2e/specs/020-account-telegram-export.spec.ts
///
/// Connect-code block on the account screen. Either the "Connect" CTA
/// (not yet connected) or the connect code (already connected) should
/// be visible.
final class AccountTelegramExportSpec: BaseTestCase {
    func test_US1_telegramBlockRenders() {
        Navigation.openTab(.profile, in: app)
        let page = accountPage.awaitReady()
        let hasConnect = page.telegramConnect.exists
        let hasCode = page.telegramCode.exists
        XCTAssertTrue(
            hasConnect || hasCode,
            "Telegram export block missing — neither Connect button nor Code visible"
        )
    }
}

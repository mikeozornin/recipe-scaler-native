//
//  VkusvillAccountTests.swift
//
//  Spec 083: вход в аккаунт Вкусвилла — разбор callback, коды ошибок сервера,
//  DTO и жизненный цикл `VkusvillAccountViewModel` (сеть подменена providers).
//

import AuthenticationServices
import XCTest
import RecipeScalerCore
@testable import RecipeScalerNative

@MainActor
final class VkusvillAccountTests: XCTestCase {

    private static let callbackURL = URL(string: "recipe-scaler://vkusvill-oauth?code=abc&state=sealed")!
    private static let authorizeURL = URL(string: "https://id.vkusvill.ru/oauth/authorize?client_id=x")!

    private func makeConnection(
        connected: Bool = true,
        status: VkusvillConnectionDTO.Status? = .active,
        personalized: Bool? = nil
    ) -> VkusvillConnectionDTO {
        VkusvillConnectionDTO(
            available: true,
            connected: connected,
            status: connected ? status : nil,
            scopes: connected ? ["catalog.search", "purchase_history.read"] : [],
            connectedAt: connected ? "2026-10-17T09:30:00.123Z" : nil,
            personalized: personalized
        )
    }

    private func makeModel() -> VkusvillAccountViewModel {
        let model = VkusvillAccountViewModel()
        model.hasAuthenticatedUser = { true }
        model.startSignInProvider = { Self.authorizeURL }
        return model
    }

    // MARK: - Callback

    func test_callback_codeAndState_parsed() {
        XCTAssertEqual(VkusvillOAuthCallback.parse(Self.callbackURL), .code(code: "abc", state: "sealed"))
    }

    func test_callback_accessDenied_isSilentDenial() {
        let url = URL(string: "recipe-scaler-dev://vkusvill-oauth?error=access_denied")!
        XCTAssertEqual(VkusvillOAuthCallback.parse(url), .denied)
    }

    func test_callback_otherErrorOrMissingParts_fails() {
        let urls = [
            "recipe-scaler://vkusvill-oauth?error=server_error",
            "recipe-scaler://vkusvill-oauth?code=abc",
            "recipe-scaler://vkusvill-oauth?code=&state=sealed",
            "recipe-scaler://recipe?code=abc&state=sealed",
        ]
        for raw in urls {
            XCTAssertEqual(VkusvillOAuthCallback.parse(URL(string: raw)!), .failed, raw)
        }
    }

    // MARK: - Server error codes

    func test_errorCodes_mapToAccountErrors() {
        XCTAssertEqual(VkusvillAccountAPI.error(code: "invalid_state", statusCode: 400) as? VkusvillAccountError, .signInExpired)
        XCTAssertEqual(VkusvillAccountAPI.error(code: "invalid_grant", statusCode: 400) as? VkusvillAccountError, .signInExpired)
        XCTAssertEqual(VkusvillAccountAPI.error(code: "vkusvill_unavailable", statusCode: 502) as? VkusvillAccountError, .vkusvillUnavailable)
        XCTAssertEqual(VkusvillAccountAPI.error(code: "vkusvill_not_configured", statusCode: 503) as? VkusvillAccountError, .notConfigured)
        XCTAssertEqual(VkusvillAccountAPI.error(code: nil, statusCode: 500) as? VkusvillAccountError, .server(statusCode: 500))
        guard case .unauthorized = VkusvillAccountAPI.error(code: nil, statusCode: 401) as? APIError else {
            return XCTFail("401 without code must stay APIError.unauthorized")
        }
    }

    // MARK: - DTO

    func test_connectionDTO_decodesServerShape() throws {
        let json = """
        {"available":true,"connected":true,"status":"reconnect_required","scopes":["catalog.search"],
         "connected_at":"2026-10-17T09:30:00.123Z","personalized":false}
        """
        let dto = try JSONDecoder().decode(VkusvillConnectionDTO.self, from: Data(json.utf8))
        XCTAssertEqual(dto.status, .reconnectRequired)
        XCTAssertEqual(dto.personalized, false)
        XCTAssertNotNil(dto.connectedDate, "connected_at carries milliseconds")
    }

    func test_signedInDateText_omitsCurrentYear() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let locale = Locale(identifier: "ru_RU")
        let date = try XCTUnwrap(DiscoverDateParser.parse("2026-10-17T09:30:00Z"))
        let sameYear = try XCTUnwrap(DiscoverDateParser.parse("2026-12-01T00:00:00Z"))
        let nextYear = try XCTUnwrap(DiscoverDateParser.parse("2027-02-01T00:00:00Z"))

        XCTAssertEqual(
            VkusvillSettingsSection.signedInDateText(date, now: sameYear, locale: locale, calendar: calendar),
            "17 октября"
        )
        XCTAssertTrue(
            VkusvillSettingsSection.signedInDateText(date, now: nextYear, locale: locale, calendar: calendar)
                .contains("2026")
        )
    }

    // MARK: - Sign-in

    func test_signIn_success_completesWithCallbackCodeAndState() async {
        let model = makeModel()
        var completed: (String, String)?
        model.completeSignInProvider = { code, state in
            completed = (code, state)
            return self.makeConnection()
        }
        var openedURL: URL?

        await model.signIn(isOnline: true) { url in
            openedURL = url
            return Self.callbackURL
        }

        XCTAssertEqual(openedURL, Self.authorizeURL)
        XCTAssertEqual(completed?.0, "abc")
        XCTAssertEqual(completed?.1, "sealed")
        XCTAssertTrue(model.isConnected)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isWorking)
    }

    func test_signIn_deniedOrCancelled_isSilent() async {
        let model = makeModel()
        var completeCalls = 0
        model.completeSignInProvider = { _, _ in
            completeCalls += 1
            return self.makeConnection()
        }

        await model.signIn(isOnline: true) { _ in
            URL(string: "recipe-scaler://vkusvill-oauth?error=access_denied")!
        }
        await model.signIn(isOnline: true) { _ in
            throw ASWebAuthenticationSessionError(.canceledLogin)
        }

        XCTAssertEqual(completeCalls, 0)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isConnected)
    }

    func test_signIn_failedCallback_showsSignInError() async {
        let model = makeModel()

        await model.signIn(isOnline: true) { _ in
            URL(string: "recipe-scaler://vkusvill-oauth?error=server_error")!
        }

        XCTAssertEqual(model.errorMessage, Bundle.currentLocalizedString("vkusvill.account.error.sign-in-failed"))
    }

    func test_signIn_serverErrors_mapToMessages() async {
        let cases: [(Error, String)] = [
            (VkusvillAccountError.vkusvillUnavailable, "vkusvill.account.error.unavailable"),
            (VkusvillAccountError.signInExpired, "vkusvill.account.error.sign-in-expired"),
            (VkusvillAccountError.notConfigured, "vkusvill.account.error.not-configured"),
            (VkusvillAccountError.server(statusCode: 500), "vkusvill.account.error.sign-in-failed"),
            (URLError(.notConnectedToInternet), "account.error.unreachable"),
        ]
        for (error, key) in cases {
            let model = makeModel()
            model.completeSignInProvider = { _, _ in throw error }

            await model.signIn(isOnline: true) { _ in Self.callbackURL }

            XCTAssertEqual(model.errorMessage, Bundle.currentLocalizedString(key), key)
            XCTAssertFalse(model.isConnected)
        }
    }

    func test_signIn_offline_doesNothing() async {
        let model = makeModel()
        var startCalls = 0
        model.startSignInProvider = {
            startCalls += 1
            return Self.authorizeURL
        }

        await model.signIn(isOnline: false) { _ in Self.callbackURL }

        XCTAssertEqual(startCalls, 0)
    }

    func test_refreshStartedBeforeSignIn_doesNotOverwriteSignedInState() async throws {
        let model = makeModel()
        model.fetchConnectionProvider = {
            try? await Task.sleep(nanoseconds: 150_000_000)
            return self.makeConnection(connected: false)
        }
        model.completeSignInProvider = { _, _ in self.makeConnection() }

        let staleRefresh = Task { await model.refresh(isOnline: true) }
        try await Task.sleep(nanoseconds: 30_000_000)
        await model.signIn(isOnline: true) { _ in Self.callbackURL }
        await staleRefresh.value

        XCTAssertTrue(model.isConnected, "GET issued before sign-in must not apply after it")
        XCTAssertFalse(model.isLoading)
    }

    // MARK: - Sign-out and toggle

    func test_signOut_success_clearsConnection() async {
        let model = makeModel()
        model.fetchConnectionProvider = { self.makeConnection() }
        model.signOutProvider = { self.makeConnection(connected: false) }
        await model.refresh(isOnline: true)
        XCTAssertTrue(model.isConnected)

        await model.signOut(isOnline: true)

        XCTAssertFalse(model.isConnected)
        XCTAssertNil(model.errorMessage)
    }

    func test_signOut_failure_keepsConnectionAndShowsError() async {
        let model = makeModel()
        model.fetchConnectionProvider = { self.makeConnection() }
        model.signOutProvider = { throw VkusvillAccountError.server(statusCode: 500) }
        await model.refresh(isOnline: true)

        await model.signOut(isOnline: true)

        XCTAssertTrue(model.isConnected)
        XCTAssertEqual(model.errorMessage, Bundle.currentLocalizedString("vkusvill.account.error.sign-out-failed"))
    }

    func test_toggleOff_dropsConnectionAndError() async {
        let model = makeModel()
        model.fetchConnectionProvider = { self.makeConnection() }
        model.signOutProvider = { throw VkusvillAccountError.server(statusCode: 500) }
        await model.refresh(isOnline: true)
        await model.signOut(isOnline: true)

        model.handleToggleChange(enabled: false)

        XCTAssertFalse(model.isConnected)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.isAvailable)
    }

    // MARK: - Derived state

    func test_derivedState_reconnectAndNoAddress() async {
        let model = makeModel()

        model.fetchConnectionProvider = { self.makeConnection(status: .reconnectRequired, personalized: false) }
        await model.refresh(isOnline: true)
        XCTAssertTrue(model.needsReconnect)
        XCTAssertFalse(model.hasNoDeliveryAddress, "reconnect wins over the no-address hint")

        model.fetchConnectionProvider = { self.makeConnection(personalized: false) }
        await model.refresh(isOnline: true)
        XCTAssertFalse(model.needsReconnect)
        XCTAssertTrue(model.hasNoDeliveryAddress)

        model.fetchConnectionProvider = { self.makeConnection(personalized: nil) }
        await model.refresh(isOnline: true)
        XCTAssertFalse(model.hasNoDeliveryAddress, "no search yet — no hint")
    }

    func test_unconfiguredServer_hidesAccountRows() async {
        let model = makeModel()
        model.fetchConnectionProvider = {
            VkusvillConnectionDTO(available: false, connected: false, status: nil, scopes: [], connectedAt: nil, personalized: nil)
        }
        XCTAssertTrue(model.isAvailable, "rows stay visible until the status is known")

        await model.refresh(isOnline: true)

        XCTAssertFalse(model.isAvailable)
    }
}

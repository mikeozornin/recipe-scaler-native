//
//  AliceConnectionTests.swift
//
//  Web spec 066: код подключения навыка «Книга рецептов» — DTO, маппинг
//  серверных ошибок и жизненный цикл `AliceConnectionViewModel`
//  (сеть подменена providers).
//

import XCTest
import RecipeScalerCore
@testable import RecipeScalerNative

@MainActor
final class AliceConnectionTests: XCTestCase {

    private struct StubError: Error {}

    private func makeModel() -> AliceConnectionViewModel {
        let model = AliceConnectionViewModel()
        model.hasAuthenticatedUser = { true }
        model.pollInterval = .milliseconds(20)
        model.fetchStatusProvider = { Self.status(connected: false) }
        model.connectProvider = { AliceConnectionCodeDTO(code: "12345678", expiresInMinutes: 10) }
        model.disconnectProvider = {}
        return model
    }

    private static func status(connected: Bool) -> AliceConnectionStatusDTO {
        AliceConnectionStatusDTO(
            connected: connected,
            connectedAt: connected ? "2026-10-20T09:30:00.000Z" : nil,
            lastActiveAt: nil
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - DTO and errors

    func test_codeDTO_decodesServerShape() throws {
        let json = #"{"code":"04718263","expiresInMinutes":10,"instructions":"Enter this code"}"#
        let dto = try JSONDecoder().decode(AliceConnectionCodeDTO.self, from: Data(json.utf8))
        XCTAssertEqual(dto, AliceConnectionCodeDTO(code: "04718263", expiresInMinutes: 10))
    }

    func test_statusDTO_decodesConnectedAndBareShapes() throws {
        let connected = #"{"connected":true,"connectedAt":"2026-10-20T09:30:00.000Z","lastActiveAt":null}"#
        let bare = #"{"connected":false}"#
        XCTAssertEqual(
            try JSONDecoder().decode(AliceConnectionStatusDTO.self, from: Data(connected.utf8)),
            Self.status(connected: true)
        )
        XCTAssertEqual(
            try JSONDecoder().decode(AliceConnectionStatusDTO.self, from: Data(bare.utf8)),
            Self.status(connected: false)
        )
    }

    func test_englishServerErrors_collapseToAliceKeys() {
        let cases: [(String?, ServerErrorCode, ServerErrorCode)] = [
            ("Failed to generate connection code", .aliceFailedToGetCode, .aliceFailedToGetCode),
            ("Failed to get status", .aliceFailedToGetStatus, .aliceFailedToGetStatus),
            ("Failed to disconnect", .aliceFailedToDisconnect, .aliceFailedToDisconnect),
            (nil, .aliceFailedToGetCode, .aliceFailedToGetCode),
            ("alice.failed-to-disconnect", .aliceFailedToGetStatus, .aliceFailedToDisconnect),
        ]
        for (serverValue, fallback, expected) in cases {
            XCTAssertEqual(ServerErrorCode.from(serverValue: serverValue, fallback: fallback), expected)
        }
    }

    func test_withFallback_mapsUpstreamAnd5xxButKeepsAuthAndTransport() async {
        func thrown(_ error: Error) async -> Error? {
            do {
                _ = try await AliceAPI.withFallback(.aliceFailedToGetCode) { () async throws -> Int in throw error }
                return nil
            } catch {
                return error
            }
        }

        let upstream = await thrown(APIError.upstreamMessage("Failed to generate connection code"))
        XCTAssertEqual(
            UserFacingAPIError.message(for: upstream!),
            Bundle.currentLocalizedString("alice.failed-to-get-code")
        )
        let http500 = await thrown(APIError.httpError(statusCode: 500))
        XCTAssertEqual(
            UserFacingAPIError.message(for: http500!),
            Bundle.currentLocalizedString("alice.failed-to-get-code")
        )
        let unauthorized = await thrown(APIError.unauthorized)
        if case .unauthorized? = unauthorized as? APIError {} else {
            XCTFail("unauthorized must pass through")
        }
        let transport = await thrown(URLError(.notConnectedToInternet))
        XCTAssertTrue(transport is URLError)
    }

    // MARK: - Status

    func test_refresh_appliesConnectedStatus() async {
        let model = makeModel()
        model.fetchStatusProvider = { Self.status(connected: true) }

        await model.refreshStatus(isOnline: true)

        XCTAssertTrue(model.isConnected)
        XCTAssertNil(model.connectionCode)
    }

    func test_refresh_offlineOrSignedOut_doesNotCallServer() async {
        let model = makeModel()
        var calls = 0
        model.fetchStatusProvider = {
            calls += 1
            return Self.status(connected: true)
        }

        await model.refreshStatus(isOnline: false)
        model.hasAuthenticatedUser = { false }
        await model.refreshStatus(isOnline: true)

        XCTAssertEqual(calls, 0)
        XCTAssertFalse(model.isConnected)
    }

    func test_refreshError_isSilent() async {
        let model = makeModel()
        model.fetchStatusProvider = { throw StubError() }

        await model.refreshStatus(isOnline: true)

        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isConnected)
    }

    // MARK: - Connect

    func test_connect_showsCodeThenPollingFlipsToConnected() async throws {
        let model = makeModel()
        var linked = false
        model.fetchStatusProvider = { Self.status(connected: linked) }

        await model.connect(isOnline: true)
        XCTAssertEqual(model.connectionCode, "12345678")
        XCTAssertFalse(model.isLoading)

        linked = true
        try await waitUntil { model.isConnected }

        XCTAssertTrue(model.isConnected)
        XCTAssertNil(model.connectionCode)
        model.stopPolling()
    }

    func test_connect_offline_doesNothing() async {
        let model = makeModel()
        var calls = 0
        model.connectProvider = {
            calls += 1
            return AliceConnectionCodeDTO(code: "12345678", expiresInMinutes: 10)
        }

        await model.connect(isOnline: false)

        XCTAssertEqual(calls, 0)
        XCTAssertNil(model.connectionCode)
    }

    func test_refreshCodeFailure_keepsShownCodeAndShowsError() async {
        let model = makeModel()
        await model.connect(isOnline: true)
        model.connectProvider = { throw APIError.serverError(code: .aliceFailedToGetCode) }

        await model.connect(isOnline: true)

        XCTAssertEqual(model.connectionCode, "12345678")
        XCTAssertEqual(model.errorMessage, Bundle.currentLocalizedString("alice.failed-to-get-code"))
        model.stopPolling()
    }

    func test_refreshCode_replacesCode() async {
        let model = makeModel()
        await model.connect(isOnline: true)
        model.connectProvider = { AliceConnectionCodeDTO(code: "87654321", expiresInMinutes: 10) }

        await model.connect(isOnline: true)

        XCTAssertEqual(model.connectionCode, "87654321")
        XCTAssertNil(model.errorMessage)
        model.stopPolling()
    }

    func test_stopPolling_stopsStatusCalls() async throws {
        let model = makeModel()
        var calls = 0
        model.fetchStatusProvider = {
            calls += 1
            return Self.status(connected: false)
        }
        await model.connect(isOnline: true)
        try await waitUntil { calls >= 1 }

        model.stopPolling()
        let callsAfterStop = calls
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertGreaterThanOrEqual(callsAfterStop, 1)
        XCTAssertEqual(calls, callsAfterStop)
        XCTAssertEqual(model.connectionCode, "12345678")
    }

    // MARK: - Disconnect

    func test_disconnect_success_clearsConnection() async {
        let model = makeModel()
        model.fetchStatusProvider = { Self.status(connected: true) }
        await model.refreshStatus(isOnline: true)

        await model.disconnect(isOnline: true)

        XCTAssertFalse(model.isConnected)
        XCTAssertNil(model.errorMessage)
    }

    func test_disconnect_failure_keepsConnectionAndShowsError() async {
        let model = makeModel()
        model.fetchStatusProvider = { Self.status(connected: true) }
        model.disconnectProvider = { throw APIError.serverError(code: .aliceFailedToDisconnect) }
        await model.refreshStatus(isOnline: true)

        await model.disconnect(isOnline: true)

        XCTAssertTrue(model.isConnected)
        XCTAssertEqual(model.errorMessage, Bundle.currentLocalizedString("alice.failed-to-disconnect"))
    }

    func test_statusStartedBeforeDisconnect_doesNotOverwriteIt() async throws {
        let model = makeModel()
        model.fetchStatusProvider = { Self.status(connected: true) }
        await model.refreshStatus(isOnline: true)
        model.fetchStatusProvider = {
            try? await Task.sleep(for: .milliseconds(150))
            return Self.status(connected: true)
        }

        let staleRefresh = Task { await model.refreshStatus(isOnline: true) }
        try await Task.sleep(for: .milliseconds(30))
        await model.disconnect(isOnline: true)
        await staleRefresh.value

        XCTAssertFalse(model.isConnected, "GET issued before disconnect must not apply after it")
    }
}

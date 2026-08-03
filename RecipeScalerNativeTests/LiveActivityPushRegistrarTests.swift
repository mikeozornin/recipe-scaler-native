//
//  LiveActivityPushRegistrarTests.swift
//
//  Spec 058 — unit tests for the ActivityKit push-token registrar.
//
//  Covers the three positive invariants the plan promised:
//    1. POST register succeeds → token cached → identical follow-up is a no-op.
//    2. Token rotation → differing token hits the network again (UPSERT).
//    3. DELETE unregister clears the cache and tolerates 4xx/5xx.
//
//  Plus `clearAllCachedTokens()` (logout-wipe path used by
//  `AppContainer.stopForLogout()`).
//
//  Network is indirected via `LiveActivityPushRegistrarTestURLProtocol`
//  registered on `URLSession.shared`'s default `URLProtocol` set — same
//  pattern as `PublicImageCacheTestURLProtocol` in
//  `RecipeScalerNativeTests.swift`.
//

import XCTest
import RecipeScalerCore
@testable import RecipeScalerNative

@MainActor
final class LiveActivityPushRegistrarTests: XCTestCase {
    private let timerId = "timer_00000000-0000-0000-0000-000000000001"
    private let deviceIdKey = "deviceId"
    private var savedDeviceId: String?

    override func setUp() {
        super.setUp()
        // Isolate `TimerSyncService.storedDeviceId()` so the registrar's body
        // is deterministic and does not leak across tests.
        savedDeviceId = UserDefaults.standard.string(forKey: deviceIdKey)
        UserDefaults.standard.set("device-test-fixture", forKey: deviceIdKey)

        // Isolate token-cache keys so a stale `liveActivityPushToken.*` entry
        // from a previous test (or a previous user session) cannot satisfy the
        // dedup short-circuit and hide a regression.
        wipeTokenCacheKeys()

        LiveActivityPushRegistrarTestURLProtocol.reset()
        URLProtocol.registerClass(LiveActivityPushRegistrarTestURLProtocol.self)
    }

    override func tearDown() {
        LiveActivityPushRegistrarTestURLProtocol.reset()
        URLProtocol.unregisterClass(LiveActivityPushRegistrarTestURLProtocol.self)
        wipeTokenCacheKeys()
        if let savedDeviceId {
            UserDefaults.standard.set(savedDeviceId, forKey: deviceIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: deviceIdKey)
        }
        super.tearDown()
    }

    private func wipeTokenCacheKeys() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
            where key.hasPrefix("liveActivityPushToken.") {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - register

    func testRegister_PostsTokenAndCachesLocally() async {
        let registrar = LiveActivityPushRegistrar()
        var capturedBody: [String: Any]?
        LiveActivityPushRegistrarTestURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.hasSuffix("/api/push/apns-register-liveactivity") == true)
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capturedBody = json
            } else if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var data = Data()
                let bufferSize = 1024
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                defer { buffer.deallocate() }
                while stream.hasBytesAvailable {
                    let read = stream.read(buffer, maxLength: bufferSize)
                    if read > 0 { data.append(buffer, count: read) }
                    else { break }
                }
                capturedBody = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            }
            return Self.okResponse()
        }

        let ok = await registrar.register(timerId: timerId, tokenHex: "deadbeef")
        XCTAssertTrue(ok, "register should return true on 2xx")
        XCTAssertEqual(LiveActivityPushRegistrarTestURLProtocol.callCount, 1)
        XCTAssertTrue(registrar.hasCachedToken(timerId: timerId))

        XCTAssertEqual(capturedBody?["timer_id"] as? String, timerId)
        XCTAssertEqual(capturedBody?["token"] as? String, "deadbeef")
        XCTAssertEqual(capturedBody?["device_id"] as? String, "device-test-fixture")
    }

    func testRegister_DedupSkipsNetworkOnIdenticalToken() async {
        let registrar = LiveActivityPushRegistrar()
        LiveActivityPushRegistrarTestURLProtocol.handler = { _ in Self.okResponse() }

        _ = await registrar.register(timerId: timerId, tokenHex: "deadbeef")
        let firstCount = LiveActivityPushRegistrarTestURLProtocol.callCount
        XCTAssertEqual(firstCount, 1)

        // Identical second call — must not hit the network.
        let ok = await registrar.register(timerId: timerId, tokenHex: "deadbeef")
        XCTAssertTrue(ok)
        XCTAssertEqual(
            LiveActivityPushRegistrarTestURLProtocol.callCount,
            firstCount,
            "identical token must short-circuit on the UserDefaults cache"
        )
    }

    func testRegister_RotationPostsNewTokenAndOverwritesCache() async {
        let registrar = LiveActivityPushRegistrar()
        LiveActivityPushRegistrarTestURLProtocol.handler = { _ in Self.okResponse() }

        _ = await registrar.register(timerId: timerId, tokenHex: "deadbeef")
        _ = await registrar.register(timerId: timerId, tokenHex: "cafef00d")

        XCTAssertEqual(
            LiveActivityPushRegistrarTestURLProtocol.callCount,
            2,
            "rotated (differing) token must trigger a new POST (server UPSERT, R4)"
        )
        // Cache now holds the new token, so a third identical call dedups.
        _ = await registrar.register(timerId: timerId, tokenHex: "cafef00d")
        XCTAssertEqual(LiveActivityPushRegistrarTestURLProtocol.callCount, 2)
    }

    func testRegister_ReturnsFalseOnServerErrorAndDoesNotCache() async {
        let registrar = LiveActivityPushRegistrar()
        LiveActivityPushRegistrarTestURLProtocol.handler = { _ in
            Self.response(status: 503, json: ["success": false, "error": "boom"])
        }

        let ok = await registrar.register(timerId: timerId, tokenHex: "deadbeef")
        XCTAssertFalse(ok, "5xx should surface as failure so the caller can resubscribe")
        XCTAssertFalse(
            registrar.hasCachedToken(timerId: timerId),
            "failed register must not poison the cache"
        )
    }

    func testRegister_GuardsAgainstEmptyInputs() async {
        let registrar = LiveActivityPushRegistrar()
        LiveActivityPushRegistrarTestURLProtocol.handler = { _ in Self.okResponse() }

        let byEmptyTimer = await registrar.register(timerId: "", tokenHex: "deadbeef")
        let byEmptyToken = await registrar.register(timerId: timerId, tokenHex: "")
        XCTAssertFalse(byEmptyTimer)
        XCTAssertFalse(byEmptyToken)
        XCTAssertEqual(LiveActivityPushRegistrarTestURLProtocol.callCount, 0)
    }

    // MARK: - unregister

    func testUnregister_ClearsCacheAndHitsDeleteEndpoint() async {
        let registrar = LiveActivityPushRegistrar()
        LiveActivityPushRegistrarTestURLProtocol.handler = { _ in Self.okResponse() }
        _ = await registrar.register(timerId: timerId, tokenHex: "deadbeef")
        XCTAssertTrue(registrar.hasCachedToken(timerId: timerId))

        var capturedMethod: String?
        var capturedURL: String?
        LiveActivityPushRegistrarTestURLProtocol.callCount = 0
        LiveActivityPushRegistrarTestURLProtocol.handler = { request in
            capturedMethod = request.httpMethod
            capturedURL = request.url?.absoluteString
            return Self.okResponse()
        }

        await registrar.unregister(timerId: timerId)

        XCTAssertEqual(capturedMethod, "DELETE")
        XCTAssertNotNil(capturedURL)
        XCTAssertTrue(
            capturedURL?.contains("timer_id=\(timerId)") == true,
            "DELETE query must carry timer_id"
        )
        XCTAssertTrue(
            capturedURL?.contains("device_id=device-test-fixture") == true,
            "DELETE query must carry device_id"
        )
        XCTAssertFalse(registrar.hasCachedToken(timerId: timerId))
        XCTAssertEqual(LiveActivityPushRegistrarTestURLProtocol.callCount, 1)
    }

    func testUnregister_ToleratesServerErrorAndStillClearsCache() async {
        let registrar = LiveActivityPushRegistrar()
        LiveActivityPushRegistrarTestURLProtocol.handler = { _ in Self.okResponse() }
        _ = await registrar.register(timerId: timerId, tokenHex: "deadbeef")

        // Endpoint may not exist yet while server 058 is in flight — registrar
        // must swallow and still drop the local cache (spec: idempotent best-effort).
        LiveActivityPushRegistrarTestURLProtocol.handler = { _ in
            Self.response(status: 404, json: ["success": false, "error": "not found"])
        }

        await registrar.unregister(timerId: timerId)

        XCTAssertFalse(
            registrar.hasCachedToken(timerId: timerId),
            "unregister must clear the cache regardless of server response"
        )
    }

    // MARK: - clearAllCachedTokens

    func testClearAllCachedTokens_WipesAllPrefixedEntries() async {
        let registrar = LiveActivityPushRegistrar()
        LiveActivityPushRegistrarTestURLProtocol.handler = { _ in Self.okResponse() }

        _ = await registrar.register(timerId: "timer_aaa", tokenHex: "aa")
        _ = await registrar.register(timerId: "timer_bbb", tokenHex: "bb")
        XCTAssertTrue(registrar.hasCachedToken(timerId: "timer_aaa"))
        XCTAssertTrue(registrar.hasCachedToken(timerId: "timer_bbb"))

        registrar.clearAllCachedTokens()

        XCTAssertFalse(registrar.hasCachedToken(timerId: "timer_aaa"))
        XCTAssertFalse(registrar.hasCachedToken(timerId: "timer_bbb"))
        // Belt-and-suspenders: confirm no key with our prefix survives.
        let survivor = UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("liveActivityPushToken.") }
        XCTAssertTrue(survivor.isEmpty, "unexpected cached keys: \(survivor)")
    }

    // MARK: - helpers

    private static func okResponse() -> (HTTPURLResponse, Data) {
        response(status: 200, json: ["success": true])
    }

    private static func response(status: Int, json: [String: Any]) -> (HTTPURLResponse, Data) {
        let url = URL(string: "https://recipe-scaler.ru/api/push/apns-register-liveactivity")!
        let data = try! JSONSerialization.data(withJSONObject: json)
        let http = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (http, data)
    }
}

private final class LiveActivityPushRegistrarTestURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var callCount = 0

    static func reset() {
        handler = nil
        callCount = 0
    }

    override class func canInit(with request: URLRequest) -> Bool {
        // Match only the liveactivity endpoint host — leaves the rest of
        // `URLSession.shared` (image fetches, etc.) untouched.
        request.url?.path == "/api/push/apns-register-liveactivity"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.callCount += 1
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

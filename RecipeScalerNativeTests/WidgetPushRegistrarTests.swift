//
//  WidgetPushRegistrarTests.swift
//
//  Spec 030 Phase B2 — unit tests for widget push token registration.
//

import XCTest
import RecipeScalerCore
@testable import RecipeScalerNative

@MainActor
final class WidgetPushRegistrarTests: XCTestCase {
    private let deviceIdKey = SharedDeviceId.standardKey
    private var savedDeviceId: String?
    private var savedAppGroupDeviceId: String?
    private var savedPendingWidgetToken: String?
    private var savedRegisteredWidgetToken: String?

    override func setUp() {
        super.setUp()
        // A widget token POST started by an earlier suite can still be in
        // flight when this suite registers the protocol: URLSession keeps the
        // request running after that suite's tearDown reset the shared static
        // counters. Drain before taking ownership of the stub so every count
        // below measures only this test's requests.
        drainWidgetPushTransport()
        savedDeviceId = UserDefaults.standard.string(forKey: deviceIdKey)
        savedAppGroupDeviceId = AppGroup.userDefaults?.string(forKey: SharedDeviceId.appGroupKey)
        savedPendingWidgetToken = WidgetPushTokenClient.pendingTokenHex
        savedRegisteredWidgetToken = WidgetPushTokenClient.registeredTokenHex
        UserDefaults.standard.set("device-widget-fixture", forKey: deviceIdKey)
        AppGroup.userDefaults?.set("device-widget-fixture", forKey: SharedDeviceId.appGroupKey)
        WidgetPushTokenClient.clearCachedToken()

        // Isolate from AppContainer's 401 handler and stale bearer tokens left
        // by earlier suites (otherwise widget POST can hit prod and session_wipe).
        APIClient.shared.configure(authToken: nil)
        APIClient.shared.configure(userId: nil)
        APIClient.shared.unauthorizedHandler = nil

        WidgetPushRegistrarTestURLProtocol.reset()
        URLProtocol.registerClass(WidgetPushRegistrarTestURLProtocol.self)
    }

    override func tearDown() {
        // Drain before unregistering: once the protocol is gone the request
        // falls through to a real transport, and the next suite inherits the
        // response side effects (401 handler, cache writes) off the stub.
        drainWidgetPushTransport()
        WidgetPushRegistrarTestURLProtocol.reset()
        URLProtocol.unregisterClass(WidgetPushRegistrarTestURLProtocol.self)
        WidgetPushTokenClient.clearCachedToken()
        if let savedDeviceId {
            UserDefaults.standard.set(savedDeviceId, forKey: deviceIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: deviceIdKey)
        }
        if let savedAppGroupDeviceId {
            AppGroup.userDefaults?.set(savedAppGroupDeviceId, forKey: SharedDeviceId.appGroupKey)
        } else {
            AppGroup.userDefaults?.removeObject(forKey: SharedDeviceId.appGroupKey)
        }
        WidgetPushTokenClient.pendingTokenHex = savedPendingWidgetToken
        WidgetPushTokenClient.registeredTokenHex = savedRegisteredWidgetToken
        super.tearDown()
    }

    func testRegister_PostsHexTokenAndDeviceId() async {
        let registrar = WidgetPushRegistrar()
        var capturedBody: [String: Any]?
        WidgetPushRegistrarTestURLProtocol.handler = { request in
            guard request.httpMethod == "POST" else { return Self.okResponse() }
            XCTAssertTrue(
                request.url?.absoluteString.contains("/api/push/apns-register-widget") == true
            )
            capturedBody = Self.bodyJSON(from: request)
            return Self.okResponse()
        }
        let baseline = WidgetPushRegistrarTestURLProtocol.postCallCount(forToken: "aabbccdd")

        let ok = await registrar.register(tokenHex: "aabbccdd")
        XCTAssertTrue(ok)
        XCTAssertEqual(
            WidgetPushRegistrarTestURLProtocol.postCallCount(forToken: "aabbccdd") - baseline,
            1
        )
        XCTAssertEqual(capturedBody?["token"] as? String, "aabbccdd")
        XCTAssertEqual(capturedBody?["device_id"] as? String, "device-widget-fixture")
        XCTAssertTrue(registrar.hasCachedToken)
    }

    func testRegister_DedupSkipsIdenticalToken() async {
        let registrar = WidgetPushRegistrar()
        WidgetPushRegistrarTestURLProtocol.handler = { request in
            guard request.httpMethod == "POST" else { return Self.okResponse() }
            return Self.okResponse()
        }

        _ = await registrar.register(tokenHex: "aabbccdd")
        let first = WidgetPushRegistrarTestURLProtocol.postCallCount(forToken: "aabbccdd")
        _ = await registrar.register(tokenHex: "aabbccdd")
        XCTAssertEqual(
            WidgetPushRegistrarTestURLProtocol.postCallCount(forToken: "aabbccdd"),
            first,
            "identical token must not re-POST"
        )
    }

    func testRegister_RotationRePosts() async {
        let registrar = WidgetPushRegistrar()
        WidgetPushRegistrarTestURLProtocol.handler = { request in
            guard request.httpMethod == "POST" else { return Self.okResponse() }
            return Self.okResponse()
        }
        let firstToken = "aabbccdd"
        let secondToken = "11223344"
        let firstBaseline = WidgetPushRegistrarTestURLProtocol.postCallCount(forToken: firstToken)
        let secondBaseline = WidgetPushRegistrarTestURLProtocol.postCallCount(forToken: secondToken)

        _ = await registrar.register(tokenHex: firstToken)
        _ = await registrar.register(tokenHex: secondToken)
        XCTAssertEqual(
            WidgetPushRegistrarTestURLProtocol.postCallCount(forToken: firstToken) - firstBaseline,
            1
        )
        XCTAssertEqual(
            WidgetPushRegistrarTestURLProtocol.postCallCount(forToken: secondToken) - secondBaseline,
            1
        )
        XCTAssertEqual(WidgetPushTokenClient.registeredTokenHex, secondToken)
    }

    func testUnregister_DeletesAndClearsCache() async {
        let registrar = WidgetPushRegistrar()
        WidgetPushRegistrarTestURLProtocol.handler = { _ in Self.okResponse() }
        _ = await registrar.register(tokenHex: "aabbccdd")

        var method: String?
        var url: String?
        WidgetPushRegistrarTestURLProtocol.callCount = 0
        WidgetPushRegistrarTestURLProtocol.deleteCallCount = 0
        WidgetPushRegistrarTestURLProtocol.handler = { request in
            method = request.httpMethod
            url = request.url?.absoluteString
            return Self.okResponse()
        }

        await registrar.unregister()
        XCTAssertEqual(method, "DELETE")
        XCTAssertTrue(url?.contains("device_id=device-widget-fixture") == true)
        XCTAssertFalse(registrar.hasCachedToken)
        XCTAssertEqual(
            WidgetPushRegistrarTestURLProtocol.deleteCallCount(forDevice: "device-widget-fixture"),
            1
        )
    }

    func testUnregister_ToleratesServerError() async {
        let registrar = WidgetPushRegistrar()
        WidgetPushRegistrarTestURLProtocol.handler = { _ in Self.okResponse() }
        _ = await registrar.register(tokenHex: "aabbccdd")

        WidgetPushRegistrarTestURLProtocol.handler = { _ in
            Self.response(status: 500, json: ["success": false])
        }
        await registrar.unregister()
        XCTAssertFalse(registrar.hasCachedToken)
    }

    func testUnregister_ReturnsUnauthorizedOn401() async {
        // Security review critical #1: a 401 here means the DELETE went out
        // without a valid bearer (logout ordering regression). The outcome
        // must be observable by the caller so the leak is not silent.
        let registrar = WidgetPushRegistrar()
        WidgetPushRegistrarTestURLProtocol.handler = { _ in Self.okResponse() }
        _ = await registrar.register(tokenHex: "aabbccdd")

        WidgetPushRegistrarTestURLProtocol.handler = { _ in
            Self.response(status: 401, json: ["success": false])
        }
        let outcome = await WidgetPushTokenClient.unregister(deviceId: "device-widget-fixture")
        XCTAssertEqual(outcome, .unauthorized)
    }

    // MARK: - helpers

    /// Give URLProtocol-mediated widget POST/DELETE traffic a few runloop
    /// turns to finish. The handlers respond synchronously, so any request
    /// that has already reached the transport completes here; requests that
    /// never start cannot produce a count later.
    private func drainWidgetPushTransport() {
        for _ in 0..<20 {
            RunLoop.current.run(
                mode: .default,
                before: Date().addingTimeInterval(0.005)
            )
        }
    }

    private static func bodyJSON(from request: URLRequest) -> [String: Any]? {
        if let body = request.httpBody,
           let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            return json
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: 1024)
            if read > 0 { data.append(buffer, count: read) } else { break }
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func okResponse() -> (HTTPURLResponse, Data) {
        response(status: 200, json: ["success": true])
    }

    private static func response(status: Int, json: [String: Any]) -> (HTTPURLResponse, Data) {
        let url = URL(string: "https://recipe-scaler.ru/api/push/apns-register-widget")!
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

private final class WidgetPushRegistrarTestURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var postCallCount = 0
    nonisolated(unsafe) static var deleteCallCount = 0
    nonisolated(unsafe) static var postCountsByToken: [String: Int] = [:]
    nonisolated(unsafe) static var deleteCountsByDevice: [String: Int] = [:]

    /// Legacy alias used by tests that only care about POST volume.
    nonisolated(unsafe) static var callCount: Int {
        get { postCallCount }
        set { postCallCount = newValue }
    }

    static func reset() {
        handler = nil
        postCallCount = 0
        deleteCallCount = 0
        postCountsByToken.removeAll()
        deleteCountsByDevice.removeAll()
    }

    /// Suite teardown in other classes can still be posting widget tokens when
    /// this suite runs; only requests carrying this test's token may affect
    /// its assertions.
    static func postCallCount(forToken token: String) -> Int {
        postCountsByToken[token] ?? 0
    }

    static func deleteCallCount(forDevice deviceId: String) -> Int {
        deleteCountsByDevice[deviceId] ?? 0
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard handler != nil else { return false }
        return request.url?.path == "/api/push/apns-register-widget"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if request.httpMethod == "POST" {
            Self.postCallCount += 1
            if let token = Self.token(in: request) {
                Self.postCountsByToken[token, default: 0] += 1
            }
        } else if request.httpMethod == "DELETE" {
            Self.deleteCallCount += 1
            if let deviceId = Self.deviceId(in: request) {
                Self.deleteCountsByDevice[deviceId, default: 0] += 1
            }
        }
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

    private static func token(in request: URLRequest) -> String? {
        guard let data = bodyData(of: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["token"] as? String
    }

    private static func deviceId(in request: URLRequest) -> String? {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        return components.queryItems?.first { $0.name == "device_id" }?.value
    }

    private static func bodyData(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: 1024)
            if read > 0 { data.append(buffer, count: read) } else { break }
        }
        return data
    }
}

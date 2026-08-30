import Foundation
import XCTest

/// Shared `URLProtocol` stub for spec 072 store tests
/// (`FollowStoreTests`, `FeedStoreTests`, `FeedBadgeStoreTests`,
/// `FollowFeedStoresTests`).
///
/// Pattern: `LiveActivityPushRegistrarTestURLProtocol` — registered globally on
/// `URLSession.shared` for the duration of one test class and matched narrowly
/// by request path so the rest of the host app's traffic is untouched.
/// `APIClient` has no injectable session (private init, `URLSession.shared`
/// hard-wired), so a protocol stub is the project's seam for REST store tests.
///
/// Responses come from a per-test `handler`; every intercepted request is
/// recorded together with its body (drained while the transport stream is
/// still readable) so tests can assert the `POST /feed/seen` echo.
final class FollowFeedTestURLProtocol: URLProtocol {

    struct RecordedRequest {
        let request: URLRequest
        /// Request body bytes captured inside `startLoading`.
        let body: Data?
    }

    private static let stateLock = NSLock()
    nonisolated(unsafe) private static var _handler: ((URLRequest) -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) private static var _requests: [RecordedRequest] = []

    static var handler: ((URLRequest) -> (HTTPURLResponse, Data))? {
        get { stateLock.withLock { _handler } }
        set { stateLock.withLock { _handler = newValue } }
    }

    static var requests: [RecordedRequest] {
        stateLock.withLock { _requests }
    }

    static var requestCount: Int {
        stateLock.withLock { _requests.count }
    }

    static func reset() {
        stateLock.withLock {
            _handler = nil
            _requests = []
        }
    }

    static func requestCount(matching path: String) -> Int {
        requests.filter { $0.request.url?.path == path }.count
    }

    override class func canInit(with request: URLRequest) -> Bool {
        // Only stub while a test handler is installed; otherwise leave
        // `URLSession.shared` to the next protocol (avoids failing unrelated
        // suites when async work outlives tearDown).
        guard stateLock.withLock({ _handler != nil }) else { return false }
        let path = request.url?.path ?? ""
        if path == "/api/v1/feed" || path == "/api/v1/feed/badge" || path == "/api/v1/feed/seen" {
            return true
        }
        if path.hasPrefix("/api/v1/users/") {
            return path.hasSuffix("/follow") || path.contains("/users/me/following/")
        }
        return false
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let body = Self.readBody(request)
        Self.stateLock.withLock {
            Self._requests.append(RecordedRequest(request: request, body: body))
        }
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URLSession hands the body over as a stream inside `URLProtocol` — drain
    /// it while it is still readable (same as `LiveActivityPushRegistrarTests`).
    private static func readBody(_ request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read > 0 {
                data.append(buffer, count: read)
            } else {
                break
            }
        }
        return data.isEmpty ? nil : data
    }
}

// MARK: - Response builders (shared by all spec 072 store tests)

extension FollowFeedTestURLProtocol {

    static func json(_ payload: String, status: Int = 200) -> (HTTPURLResponse, Data) {
        let http = HTTPURLResponse(
            url: URL(string: "https://unit-test.recipe-scaler.invalid/api/v1/x")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (http, Data(payload.utf8))
    }

    /// `{"success": true, "data": …}` envelope for `APIClient.requestJSON`.
    static func okData(_ dataJSON: String) -> (HTTPURLResponse, Data) {
        json("{\"success\":true,\"data\":\(dataJSON)}")
    }

    static func okEmpty() -> (HTTPURLResponse, Data) {
        okData("null")
    }

    /// Bare `204 No Content` — the real wire format of `DELETE /follow` and
    /// `POST /feed/seen` (web spec 072 § Wire-контракт). Unlike `okEmpty()`
    /// (a 200 JSON envelope) this exercises the empty-body path of
    /// `requestJSON`.
    static func noContent() -> (HTTPURLResponse, Data) {
        let http = HTTPURLResponse(
            url: URL(string: "https://unit-test.recipe-scaler.invalid/api/v1/x")!,
            statusCode: 204,
            httpVersion: nil,
            headerFields: nil
        )!
        return (http, Data())
    }

    /// `{"success": true}` — bare success envelope of `POST /follow`
    /// (server returns 201 create / 200 repeat, both with a body).
    static func okSuccess(status: Int = 200) -> (HTTPURLResponse, Data) {
        json("{\"success\":true}", status: status)
    }

    /// Non-2xx failure carrying a server dot-key (`mapHTTPFailure` resolves
    /// it into `APIError.serverError`).
    static func apiFailure(_ dotKey: String, status: Int = 500) -> (HTTPURLResponse, Data) {
        json("{\"success\":false,\"error\":\"\(dotKey)\"}", status: status)
    }

    static func badge(hasNew: Bool) -> (HTTPURLResponse, Data) {
        okData("{\"has_new\":\(hasNew)}")
    }

    static func followStatus(following: Bool, pushOptIn: Bool) -> (HTTPURLResponse, Data) {
        okData("{\"following\":\(following),\"push_opt_in\":\(pushOptIn)}")
    }

    static func feedPage(
        items: [String],
        nextCursor: String?,
        snapshotAt: String?,
        hasFollows: Bool? = nil,
        lastSeenAt: String? = nil
    ) -> (HTTPURLResponse, Data) {
        let cursorJSON = nextCursor.map { "\"\($0)\"" } ?? "null"
        let snapshotJSON = snapshotAt.map { "\"\($0)\"" } ?? "null"
        let hasFollowsJSON = hasFollows.map { "\($0)" } ?? "null"
        let lastSeenJSON = lastSeenAt.map { "\"\($0)\"" } ?? "null"
        let payload =
            "{\"items\":[\(items.joined(separator: ","))],"
            + "\"next_cursor\":\(cursorJSON),\"snapshot_at\":\(snapshotJSON),"
            + "\"has_follows\":\(hasFollowsJSON),\"last_seen_at\":\(lastSeenJSON)}"
        return okData(payload)
    }

    static func feedEntry(
        id: String,
        isNew: Bool = false,
        publishedAt: String = "2026-08-28T09:00:00.000Z"
    ) -> String {
        "{\"recipe_id\":\"\(id)\",\"username\":\"author\",\"display_name\":\"Author\","
            + "\"avatar_ref\":null,\"image_ref\":null,\"name\":\"Recipe \(id)\","
            + "\"published_at\":\"\(publishedAt)\",\"is_new\":\(isNew)}"
    }
}

// MARK: - Test plumbing helpers

extension XCTestCase {
    /// Polls a synchronous condition from an async test until it holds or the
    /// timeout elapses. Used to hand off deterministically with the transport
    /// queue before asserting on interleaving (stale completions, single-flight).
    func ffWaitUntil(timeout: TimeInterval = 5, _ condition: @escaping () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}


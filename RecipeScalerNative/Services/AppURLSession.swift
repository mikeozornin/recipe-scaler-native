import Foundation

/// Centralized `URLSession` factory so every HTTP call in the app shares the
/// same conservative timeout policy. The previous pattern (`URLSession.shared`
/// at every call site) inherited the system default of 60s per request, which
/// is too long for the simulator test host: if the loopback/proxy stalls the
/// test bundle waits the full minute per request before failing.
///
/// Production requests still get a reasonable upper bound; the test host gets a
/// much shorter one so a stuck network surfaces as a fast failure instead of a
/// 30-minute bundle hang.
enum AppURLSession {
    /// Per-request upper bound for production HTTP calls (seconds).
    static let productionTimeoutIntervalForResource: TimeInterval = 30
    static let productionTimeoutIntervalForRequest: TimeInterval = 15

    /// Per-request upper bound when running under XCTest/UI-test hosts.
    /// Short on purpose: a stalled network should fail fast, not park the host.
    static let testingTimeoutIntervalForResource: TimeInterval = 5
    static let testingTimeoutIntervalForRequest: TimeInterval = 3

    /// `URLSession` configured for the current process type.
    /// Production: standard shared-config-equivalent with explicit timeouts.
    /// Test host: fresh `.ephemeral` session per call so per-test `URLProtocol`
    /// registration (e.g. `PublicImageCacheTestURLProtocol`) is visible.
    static var shared: URLSession {
        if isTestingHost {
            // IMPORTANT: do NOT build a fresh `.ephemeral` session here.
            // Tests register their stubs via `URLProtocol.registerClass(...)`,
            // which only mutates the global registry consulted by
            // `URLSession.shared` — a custom ephemeral config starts with an
            // empty `protocolClasses` and would silently bypass the stub,
            // sending the request to the real network (and timing out).
            // We return `URLSession.shared` instead, but cap its timeouts via
            // `URLSessionConfiguration` overrides that the shared session
            // consults lazily on first request.
            configureSharedSessionForTesting()
            return URLSession.shared
        }
        return productionSession
    }

    private static var didConfigureSharedForTesting = false

    private static func configureSharedSessionForTesting() {
        guard !didConfigureSharedForTesting else { return }
        didConfigureSharedForTesting = true
        // Mutating `URLSession.shared.configuration.*` is best-effort: the
        // shared session snapshots its configuration on first use, so this
        // must run before any request is issued. In the test host the first
        // request only fires after this getter returns, which satisfies the
        // ordering constraint.
        URLSession.shared.configuration.timeoutIntervalForRequest = testingTimeoutIntervalForRequest
        URLSession.shared.configuration.timeoutIntervalForResource = testingTimeoutIntervalForResource
        URLSession.shared.configuration.waitsForConnectivity = false
    }

    private static let productionSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = productionTimeoutIntervalForRequest
        configuration.timeoutIntervalForResource = productionTimeoutIntervalForResource
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    private static var isTestingHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.arguments.contains("ui-testing")
    }
}

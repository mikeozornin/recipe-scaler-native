import Foundation
import XCTest

/// `URLProtocol` that fails any unexpected network request made from a
/// unit/integration test bundle.
///
/// Why this exists: `llm/reviews/` repeatedly caught tests that (a) hit the
/// production server by accident, or (b) succeeded without exercising the code
/// path under test because the real network answered. Per
/// `docs/agents/ASYNC-LIFECYCLE.md` §5 unit/integration suites deny external
/// network by default; only suites explicitly labelled as integration may opt
/// in, and even there each request must be expected and stubbed.
///
/// Usage in tests:
///
/// ```swift
/// let config = URLSessionConfiguration.ephemeral
/// config.protocolClasses = [NoExternalNetworkURLProtocol.self]
/// let session = URLSession(configuration: config)
/// ```
///
/// Or register globally for the test run:
///
/// ```swift
/// URLProtocol.registerClass(NoExternalNetworkURLProtocol.self)
/// ```
final class NoExternalNetworkURLProtocol: URLProtocol {

    /// Hosts that may be used by pure-local test plumbing (e.g. loopback
    /// fixtures). Add only with an explicit test reason; never add production
    /// hosts here.
    static var allowedLoopbackHosts: Set<String> = ["127.0.0.1", "localhost"]

    static var failureHandler: ((URL) -> NSError)?

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    private static let blockedLock = NSLock()
    nonisolated(unsafe) private static var blocked: [String] = []

    /// URLs blocked since the last call (reported per test by `TestBundleSetup`).
    static func drainBlocked() -> [String] {
        blockedLock.lock()
        defer { blockedLock.unlock() }
        let drained = blocked
        blocked.removeAll()
        return drained
    }

    override func startLoading() {
        let url = request.url
        let host = url?.host?.lowercased()
        Self.blockedLock.lock()
        Self.blocked.append("\(request.httpMethod ?? "GET") \(url?.path ?? "<nil>")")
        Self.blockedLock.unlock()
        if let host, Self.allowedLoopbackHosts.contains(host) {
            // Loopback requests are left to a real or stubbed transport; we do
            // not synthesise a response here. The test owns the next hop.
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
        } else {
            let error: NSError = Self.failureHandler.flatMap { $0(url ?? URL(string: "about:blank")!) }
                ?? NSError(
                    domain: "NoExternalNetworkURLProtocol",
                    code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Unexpected external network request in test: \(url?.absoluteString ?? "<nil>")",
                    ]
                )
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        // No-op; we never start a real connection.
    }
}

/// Principal class of the test bundle (`NSPrincipalClass` in Info.plist): XCTest
/// instantiates it before the first test. The test host is the real app sharing
/// the simulator keychain, so without this `AppContainer`-based tests schedule real
/// pushes / Live Activity registrations for the signed-in user. Stubs registered
/// later in `setUp` still win: URLProtocol classes are consulted newest-first.
final class TestBundleSetup: NSObject, XCTestObservation {
    override init() {
        super.init()
        URLProtocol.registerClass(NoExternalNetworkURLProtocol.self)
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        let blocked = NoExternalNetworkURLProtocol.drainBlocked()
        guard !blocked.isEmpty else { return }
        print("BLOCKED NETWORK \(testCase.name): \(blocked.joined(separator: ", "))")
    }
}

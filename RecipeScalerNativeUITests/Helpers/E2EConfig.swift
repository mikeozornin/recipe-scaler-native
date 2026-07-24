import Foundation

/// Constants for E2E UI tests.
///
/// Strategy: **per-test fresh anonymous user** (web parity with
/// `tests/e2e/fixtures/auth.ts` — `register-auto` per test, then inject
/// credentials before launch). No need to wipe state between tests
/// because each test gets its own fresh user with an empty collection.
enum E2EConfig {
    /// Prefer local backend when available (web Playwright parity: localhost:3001).
    /// Override with `E2E_API_BASE` env on the test host, or force prod with
    /// `E2E_API_BASE=https://recipe-scaler.ru`.
    ///
    /// Scheme is validated: only `https://` (any host) and `http://` against
    /// explicit loopback hosts (`127.0.0.1` / `localhost`) are allowed. Any
    /// other scheme/host combination triggers `fatalError` so a misconfigured
    /// CI cannot silently leak bearer tokens in cleartext to an arbitrary
    /// host. See review finding High #6.
    static var apiBaseURL: URL {
        if let raw = ProcessInfo.processInfo.environment["E2E_API_BASE"],
           let url = URL(string: raw), !raw.isEmpty {
            validateScheme(url, raw: raw)
            return url
        }
        // Default for local E2E: same host the simulator can reach.
        return URL(string: "http://127.0.0.1:3001")!
    }

    /// True when the active backend is loopback (`127.0.0.1` / `localhost`).
    /// Used by `BaseTestCase.seedOrSkip` to decide whether a seed failure is
    /// a hard `XCTFail` (loopback: backend must be healthy) or a soft
    /// `XCTSkip` (prod: seeding is best-effort).
    static var isLoopbackBackend: Bool {
        let host = (apiBaseURL.host ?? "").lowercased()
        return host == "127.0.0.1" || host == "localhost" || host.isEmpty
    }

    /// Crash loudly if the configured base URL would send credentials in
    /// cleartext off-loopback. Localhost is the only place cleartext is
    /// acceptable for fixture seeding.
    private static func validateScheme(_ url: URL, raw: String) {
        let scheme = url.scheme?.lowercased()
        let host = (url.host ?? "").lowercased()
        let isLoopback = host == "127.0.0.1" || host == "localhost" || host.isEmpty
        if scheme == "https" {
            return
        }
        if scheme == "http" && isLoopback {
            return
        }
        fatalError(
            """
            E2E_API_BASE must be https:// (any host) or http:// against loopback.
            Got: \(raw)
            Refusing to send bearer tokens over this transport.
            """
        )
    }

    /// Default request timeout for REST fixture calls (seconds).
    static let requestTimeout: TimeInterval = 30

    /// Launch-env keys injected into the app under test.
    static let launchEnvUserId = "E2E_OVERRIDE_USER_ID"
    static let launchEnvDeviceToken = "E2E_OVERRIDE_DEVICE_TOKEN"
    static let launchEnvSeedPhrase = "E2E_OVERRIDE_SEED_PHRASE"
    static let launchEnvDeviceId = "E2E_OVERRIDE_DEVICE_ID"
    static let launchEnvApiBase = "E2E_OVERRIDE_API_BASE"
    static let launchEnvWsBase = "E2E_OVERRIDE_WS_BASE"
}

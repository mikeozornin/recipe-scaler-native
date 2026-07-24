import Foundation

/// Registers a fresh anonymous user per test (web parity: `register-auto`
/// fixture). After `registerFresh()` completes, `user` is non-nil and
/// `authHeaders()` returns a valid Bearer header for that user.
///
/// Not a singleton — `BaseTestCase` creates a fresh `DebugUser()` in `setUp`
/// and passes it to `SeedClient.init(user:)`. This makes fixtures unit-
/// testable (mock the auth path) and eliminates cross-test state leaks when
/// `registerFresh()` fails mid-way. See review finding Critical #2.
final class DebugUser {
    private(set) var user: TestUser?

    /// Ephemeral session so registered-user responses (which contain the
    /// device token + seed phrase) never hit the system URL cache. See
    /// review finding High #6/#8.
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = E2EConfig.requestTimeout
        return URLSession(configuration: config)
    }()

    /// Register a fresh anonymous user via `POST /api/auth/register-auto`.
    /// Each test calls this in setUp; the resulting `user` is bound to this
    /// instance for the lifetime of the test.
    func registerFresh() async throws -> TestUser {
        let deviceId = UUID().uuidString
        let url = E2EConfig.apiBaseURL.appendingPathComponent("/api/auth/register-auto")
        let body = try JSONSerialization.data(withJSONObject: [
            "device_id": deviceId,
            "platform": "web",
            "user_agent": "playwright-xcuitest",
            "language": "en",
        ])

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw E2EError.nonHTTPResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw E2EError.unexpectedStatus(
                "POST /api/auth/register-auto → \(http.statusCode): \(body.prefix(300))",
                http.statusCode
            )
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let success = json["success"] as? Bool, success,
            let dataDict = json["data"] as? [String: Any],
            let userDict = dataDict["user"] as? [String: Any],
            let userId = userDict["id"] as? String,
            let deviceToken = dataDict["device_token"] as? String,
            let seedPhrase = dataDict["seed_phrase"] as? String
        else {
            throw E2EError.unexpectedStatus(
                "register-auto malformed body: \(String(data: data, encoding: .utf8) ?? "")",
                http.statusCode
            )
        }

        let u = TestUser(
            userId: userId,
            deviceToken: deviceToken,
            seedPhrase: seedPhrase,
            deviceId: deviceId
        )
        self.user = u
        return u
    }

    /// Standard `Authorization: Bearer <device_token>` + JSON headers.
    /// Throws if `registerFresh()` hasn't run yet.
    func authHeaders() throws -> [String: String] {
        guard let user = user else {
            throw E2EError.unexpectedStatus(
                "DebugUser.authHeaders called before registerFresh",
                0
            )
        }
        return [
            "Content-Type": "application/json",
            "Authorization": "Bearer \(user.deviceToken)",
        ]
    }
}

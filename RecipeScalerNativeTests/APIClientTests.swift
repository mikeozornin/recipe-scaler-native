import XCTest
import RecipeScalerCore

final class APIClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // APIClient.shared — синглтон; предыдущие тесты или debug auto-login
        // могли выставить authToken/userId. Сбрасываем для изоляции контракта
        // bearer-first / x-user-id-fallback (spec 041).
        APIClient.shared.configure(authToken: nil)
        APIClient.shared.configure(userId: nil)
    }

    /// Same-host URL for auth-header assertions — `Config.baseURL` host
    /// (with DEBUG env overrides honored), not a fixed literal, because the
    /// allowlist check derives from `Config.universalLinkHosts` (review 2026.09.04 №9).
    private var apiHostImageURL: URL {
        let host = URL(string: Config.baseURL)!.host!
        return URL(string: "https://\(host)/api/recipes/r1/image")!
    }

    @MainActor
    func testRecipeImageDownloadRequestPrefersBearerTokenOverUserId() {
        APIClient.shared.configure(authToken: "verify-bearer")
        APIClient.shared.configure(userId: "verify-user-id")
        let request = APIClient.shared.recipeImageDownloadRequest(
            remoteURL: apiHostImageURL,
            etag: "etag-1",
            lastModified: nil
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer verify-bearer")
        XCTAssertNil(request.value(forHTTPHeaderField: "x-user-id"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "etag-1")
    }

    @MainActor
    func testRecipeImageDownloadRequestFallsBackToUserIdHeader() {
        APIClient.shared.configure(authToken: nil)
        APIClient.shared.configure(userId: "verify-user-id")
        let request = APIClient.shared.recipeImageDownloadRequest(
            remoteURL: apiHostImageURL,
            etag: nil,
            lastModified: "lm-1"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-user-id"), "verify-user-id")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "If-Modified-Since"), "lm-1")
    }

    // MARK: - Review 2026.09.04 №9 — auth headers only for the API host

    /// A foreign absolute `avatarUrl`/`imageUrl` must never receive the
    /// Bearer token (or the legacy x-user-id): the URL is a location hint
    /// from the server, not an auth target.
    @MainActor
    func testRecipeImageDownloadRequest_foreignHostGetsNoAuthHeaders() {
        APIClient.shared.configure(authToken: "secret-bearer")
        APIClient.shared.configure(userId: "verify-user-id")
        let foreignURL = URL(string: "https://evil.example.com/avatar.png")!

        let request = APIClient.shared.recipeImageDownloadRequest(
            remoteURL: foreignURL,
            etag: nil,
            lastModified: nil
        )

        XCTAssertNil(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer must not leak to a host outside Config.baseURL (№9)"
        )
        XCTAssertNil(
            request.value(forHTTPHeaderField: "x-user-id"),
            "Legacy x-user-id must not leak to a foreign host either (№9)"
        )
    }

    /// The `www.` variant of the API host stays inside the allowlist.
    @MainActor
    func testRecipeImageDownloadRequest_wwwVariantKeepsAuthHeaders() {
        APIClient.shared.configure(authToken: "secret-bearer")
        guard let baseHost = URL(string: Config.baseURL)?.host else {
            return XCTFail("Config.baseURL must parse")
        }
        let wwwHost = baseHost.hasPrefix("www.")
            ? baseHost
            : "www.\(baseHost)"
        let wwwURL = URL(string: "https://\(wwwHost)/api/recipes/r1/image")!

        let request = APIClient.shared.recipeImageDownloadRequest(
            remoteURL: wwwURL,
            etag: nil,
            lastModified: nil
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-bearer")
    }
}

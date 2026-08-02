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

    @MainActor
    func testRecipeImageDownloadRequestPrefersBearerTokenOverUserId() {
        APIClient.shared.configure(authToken: "verify-bearer")
        APIClient.shared.configure(userId: "verify-user-id")
        let remoteURL = URL(string: "https://example.test/api/recipes/r1/image")!
        let request = APIClient.shared.recipeImageDownloadRequest(
            remoteURL: remoteURL,
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
        let remoteURL = URL(string: "https://example.test/api/recipes/r1/image")!
        let request = APIClient.shared.recipeImageDownloadRequest(
            remoteURL: remoteURL,
            etag: nil,
            lastModified: "lm-1"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-user-id"), "verify-user-id")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "If-Modified-Since"), "lm-1")
    }
}

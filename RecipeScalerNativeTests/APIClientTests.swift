import XCTest
import RecipeScalerCore

final class APIClientTests: XCTestCase {
    @MainActor
    func testAPIClientImageDownloadRequestIncludesUserId() {
        APIClient.shared.configure(userId: "verify-user-id")
        let remoteURL = URL(string: "https://example.test/api/recipes/r1/image")!
        let request = APIClient.shared.recipeImageDownloadRequest(
            remoteURL: remoteURL,
            etag: "etag-1",
            lastModified: nil
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-user-id"), "verify-user-id")
        XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "etag-1")
        APIClient.shared.configure(userId: nil)
    }
}

import XCTest
@testable import RecipeScalerNative

@MainActor
final class DiscoverPublicProfileModelTests: XCTestCase {
    func testLoadIfNeededLoadsOnceForSameUsername() async {
        let expected = makeResponse(username: "alice", title: "First")
        let probe = ProfileFetchProbe(results: [.success(expected)])
        let model = DiscoverPublicProfileModel(api: .shared) { username in
            XCTAssertEqual(username, "alice")
            return try await probe.next()
        }

        await model.loadIfNeeded(username: "alice")
        await model.loadIfNeeded(username: "alice")

        let callCount = await probe.callCount
        XCTAssertEqual(callCount, 1)
        guard case .loaded(let response) = model.state else {
            return XCTFail("Expected loaded profile")
        }
        XCTAssertEqual(response.profile.name, "First")
    }

    func testRefreshFailureKeepsLoadedProfile() async {
        let initial = makeResponse(username: "alice", title: "Initial")
        let probe = ProfileFetchProbe(results: [
            .success(initial),
            .failure(TestError.failed)
        ])
        let model = DiscoverPublicProfileModel(api: .shared) { _ in
            try await probe.next()
        }

        await model.loadIfNeeded(username: "alice")
        await model.refresh(username: "alice")

        guard case .loaded(let response) = model.state else {
            return XCTFail("Refresh failure must preserve loaded profile")
        }
        XCTAssertEqual(response.profile.name, "Initial")
    }

    private func makeResponse(username: String, title: String) -> PublicProfileResponseDTO {
        PublicProfileResponseDTO(
            profile: PublicProfileDTO(
                username: username,
                name: title,
                avatarUrl: nil,
                recipeCount: 0,
                description: nil,
                allowRecipeDownloads: true,
                shareMode: .all
            ),
            recipes: []
        )
    }
}

private actor ProfileFetchProbe {
    private var results: [Result<PublicProfileResponseDTO, TestError>]
    private(set) var callCount = 0

    init(results: [Result<PublicProfileResponseDTO, TestError>]) {
        self.results = results
    }

    func next() throws -> PublicProfileResponseDTO {
        callCount += 1
        return try results.removeFirst().get()
    }
}

private enum TestError: Error {
    case failed
}

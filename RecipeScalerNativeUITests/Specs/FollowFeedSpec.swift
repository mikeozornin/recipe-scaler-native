import XCTest

/// Spec coverage: specs/072-follow-feed/spec.md
///
/// Live against prod (`E2E_API_BASE=https://recipe-scaler.ru`) once backend 072
/// is deployed. Uses Discover content + REST follow where UI seeding is heavy.
///
///   - US1 — Follow button on a public profile → subscription menu
///   - US3 — «Моя лента» segment renders the feed container
///   - REST — follow + badge endpoints respond after deploy
final class FollowFeedSpec: BaseTestCase {

    func test_US3_followingSegment_rendersFeedList() {
        Navigation.openTab(.discover, in: app)
        feedPage.awaitReady().openFollowingSegment()
        XCTAssertTrue(
            feedPage.feedList.waitForExistence(timeout: Wait.element),
            "Feed list container must render on «Моя лента»"
        )
    }

    func test_US1_followButton_onPublicProfile() throws {
        Navigation.openTab(.discover, in: app)
        _ = discoverPage.awaitReady()

        let profileCard = discoverPage.firstProfileCard
        try XCTSkipIf(
            !profileCard.waitForExistence(timeout: Wait.element),
            "No public profile cards in Discover (env-conditional)"
        )
        profileCard.tap()

        let follow = feedPage.followButton
        try XCTSkipIf(
            !follow.waitForExistence(timeout: Wait.element),
            "Profile has no follow button (own profile or discoverability off)"
        )
        follow.tap()
        XCTAssertTrue(
            feedPage.followMenu.waitForExistence(timeout: Wait.element),
            "Follow must swap to the subscription dropdown menu"
        )
    }

    func test_rest_followAndBadgeEndpoints() async throws {
        let usernames = try await seedClient.discoveryProfileUsernames()
        try XCTSkipIf(
            usernames.isEmpty,
            "Discover returned no public profiles (env-conditional)"
        )
        try await seedClient.follow(username: usernames[0])
        _ = try await seedClient.fetchFeedBadgeHasNew()
    }
}

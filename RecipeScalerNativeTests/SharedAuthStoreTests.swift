import XCTest
import RecipeScalerCore

final class SharedAuthStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        SharedAuthStore.clear()
    }

    override func tearDown() {
        SharedAuthStore.clear()
        super.tearDown()
    }

    func testUserIdRoundTrip() {
        XCTAssertNil(SharedAuthStore.userId, "expected no userId before write")

        SharedAuthStore.userId = "user-abc-123"

        XCTAssertEqual(SharedAuthStore.userId, "user-abc-123")
    }

    func testClearIdempotentOnEmptyStore() {
        // Clearing a never-written store must not crash or throw.
        SharedAuthStore.clear()
        SharedAuthStore.clear()

        XCTAssertNil(SharedAuthStore.userId)
    }

    func testOverwriteExistingUserId() {
        SharedAuthStore.userId = "first"
        XCTAssertEqual(SharedAuthStore.userId, "first")

        SharedAuthStore.userId = "second"
        XCTAssertEqual(SharedAuthStore.userId, "second")
    }

    func testSettingNilRemovesUserId() {
        SharedAuthStore.userId = "doomed"
        XCTAssertEqual(SharedAuthStore.userId, "doomed")

        SharedAuthStore.userId = nil

        XCTAssertNil(SharedAuthStore.userId)
    }

    func testClearRemovesUserId() {
        SharedAuthStore.userId = "user-xyz"
        XCTAssertEqual(SharedAuthStore.userId, "user-xyz")

        SharedAuthStore.clear()

        XCTAssertNil(SharedAuthStore.userId)
    }

    func testUserIdSurvivesEmptyStringValue() {
        // An empty-string userId is unusual but should round-trip without
        // ambiguity: setting "" is not the same as clearing.
        SharedAuthStore.userId = ""

        XCTAssertEqual(SharedAuthStore.userId, "")
    }

    func testTokenRoundTrip() {
        XCTAssertNil(SharedAuthStore.token)
        SharedAuthStore.token = "device-token-abc"
        XCTAssertEqual(SharedAuthStore.token, "device-token-abc")
    }

    func testClearRemovesToken() {
        SharedAuthStore.userId = "user-1"
        SharedAuthStore.token = "tok"
        SharedAuthStore.clear()
        XCTAssertNil(SharedAuthStore.userId)
        XCTAssertNil(SharedAuthStore.token)
    }

    func testSettingNilTokenRemovesTokenOnly() {
        SharedAuthStore.userId = "user-keep"
        SharedAuthStore.token = "tok"
        SharedAuthStore.token = nil
        XCTAssertEqual(SharedAuthStore.userId, "user-keep")
        XCTAssertNil(SharedAuthStore.token)
    }
}

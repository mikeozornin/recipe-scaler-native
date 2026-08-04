import XCTest
import Security
import RecipeScalerCore

final class SharedAuthStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        SharedAuthStore.clear()
        deleteUngroupedItem(account: SharedAuthStore.userIdAccount)
        deleteUngroupedItem(account: SharedAuthStore.tokenAccount)
    }

    override func tearDown() {
        SharedAuthStore.clear()
        deleteUngroupedItem(account: SharedAuthStore.userIdAccount)
        deleteUngroupedItem(account: SharedAuthStore.tokenAccount)
        super.tearDown()
    }

    /// Access group constant must be the expanded Team ID form, never the Xcode macro.
    func testKeychainAccessGroupIsTeamPrefixed() {
        XCTAssertEqual(
            SharedAuthStore.sharedKeychainAccessGroup,
            "ZBPX4JYT24.ru.recipescaler.RecipeScaler"
        )
        XCTAssertEqual(
            SharedAuthStore.keychainAccessGroup,
            SharedAuthStore.sharedKeychainAccessGroup
        )
        XCTAssertFalse(
            SharedAuthStore.sharedKeychainAccessGroup.contains("$("),
            "runtime must not use unsubstituted $(AppIdentifierPrefix)"
        )
    }

    /// Legacy per-app (ungrouped) items remain readable as a fallback.
    func testReadsUngroupedLegacyItem() {
        let legacyUserId = "legacy-user-from-ungrouped"
        XCTAssertTrue(
            writeUngroupedItem(account: SharedAuthStore.userIdAccount, value: legacyUserId),
            "seed ungrouped keychain item"
        )

        XCTAssertEqual(SharedAuthStore.userId, legacyUserId)
    }

    func testReadsUngroupedLegacyToken() {
        let legacyToken = "legacy-device-token"
        XCTAssertTrue(
            writeUngroupedItem(account: SharedAuthStore.tokenAccount, value: legacyToken),
            "seed ungrouped token"
        )

        XCTAssertEqual(SharedAuthStore.token, legacyToken)
    }

    // MARK: - Ungrouped SecItem helpers (legacy seed / cleanup)

    private func ungroupedQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: SharedAuthStore.keychainService,
            kSecAttrAccount as String: account,
        ]
    }

    @discardableResult
    private func writeUngroupedItem(account: String, value: String) -> Bool {
        deleteUngroupedItem(account: account)
        var query = ungroupedQuery(account: account)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecAttrSynchronizable as String] = kCFBooleanFalse
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private func deleteUngroupedItem(account: String) {
        SecItemDelete(ungroupedQuery(account: account) as CFDictionary)
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

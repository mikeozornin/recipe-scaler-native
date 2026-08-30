//
//  AuthServiceOwnUsernameTests.swift
//
//  Spec 072 — own-profile follow-button ownership gate (web parity).
//

import XCTest
import RecipeScalerCore
@testable import RecipeScalerNative

@MainActor
final class AuthServiceOwnUsernameTests: XCTestCase {

    override func tearDown() {
        SharingSettingsCache.save(
            publicProfileEnabled: false,
            shareMode: .one_by_one,
            username: ""
        )
        super.tearDown()
    }

    private func makeAuthenticatedService() -> AuthService {
        let service = AuthService()
        service.userId = "user-1"
        service.isAuthenticated = true
        return service
    }

    func test_shouldShowFollowControls_guest_returnsTrue() {
        let service = AuthService()
        XCTAssertFalse(service.isAuthenticated)
        XCTAssertTrue(service.shouldShowFollowControls(for: "chef"))
    }

    func test_shouldShowFollowControls_authedUnresolved_returnsFalse() {
        let service = makeAuthenticatedService()
        XCTAssertFalse(service.isOwnUsernameResolved)
        XCTAssertFalse(service.shouldShowFollowControls(for: "chef"))
    }

    func test_shouldShowFollowControls_ownProfile_returnsFalse() async {
        let service = makeAuthenticatedService()
        service.fetchSharingSettingsProvider = {
            SharingSettingsDTO(
                username: "Chef",
                publicProfileEnabled: true,
                shareMode: "all",
                allowRecipeDownloads: true
            )
        }
        await service.refreshOwnUsername()
        XCTAssertFalse(service.shouldShowFollowControls(for: "chef"))
    }

    func test_shouldShowFollowControls_otherProfile_returnsTrue() async {
        let service = makeAuthenticatedService()
        service.fetchSharingSettingsProvider = {
            SharingSettingsDTO(
                username: "alice",
                publicProfileEnabled: true,
                shareMode: "all",
                allowRecipeDownloads: true
            )
        }
        await service.refreshOwnUsername()
        XCTAssertTrue(service.shouldShowFollowControls(for: "bob"))
    }

    func test_refreshOwnUsername_setsUsernameAndResolvedFlag() async {
        let service = makeAuthenticatedService()
        service.fetchSharingSettingsProvider = {
            SharingSettingsDTO(
                username: "patissier",
                publicProfileEnabled: true,
                shareMode: "all",
                allowRecipeDownloads: true
            )
        }

        await service.refreshOwnUsername()

        XCTAssertEqual(service.ownUsername, "patissier")
        XCTAssertTrue(service.isOwnUsernameResolved)
        XCTAssertEqual(SharingSettingsCache.username, "patissier")
    }

    func test_refreshOwnUsername_networkFailure_marksResolved() async {
        let service = makeAuthenticatedService()
        service.fetchSharingSettingsProvider = {
            throw URLError(.notConnectedToInternet)
        }

        await service.refreshOwnUsername()

        XCTAssertTrue(service.isOwnUsernameResolved)
    }

    #if DEBUG
    func test_applySession_seedsOwnUsernameFromSharingCache() {
        SharingSettingsCache.save(
            publicProfileEnabled: true,
            shareMode: .one_by_one,
            username: "cache-seed"
        )
        let service = AuthService()
        service.applyDebugSimulatorSession(
            userId: "debug-user",
            deviceToken: "debug-token",
            seedPhrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        )

        XCTAssertEqual(service.ownUsername, "cache-seed")
        XCTAssertTrue(service.isOwnUsernameResolved)
    }
    #endif

    func test_logout_clearsOwnUsernameResolution() async throws {
        let service = makeAuthenticatedService()
        service.fetchSharingSettingsProvider = {
            SharingSettingsDTO(
                username: "alice",
                publicProfileEnabled: true,
                shareMode: "all",
                allowRecipeDownloads: true
            )
        }
        await service.refreshOwnUsername()
        SharedAuthStore.userId = "user-1"
        SharedAuthStore.token = "token"

        try service.logout()

        XCTAssertNil(service.ownUsername)
        XCTAssertFalse(service.isOwnUsernameResolved)
    }
}

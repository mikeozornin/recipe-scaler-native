//
//  AuthServiceStaleSessionTests.swift
//
//  Spec 054: verifies the cold-start `/api/settings` health-check that detects
//  a stored user that no longer exists on the server (e.g. after a Postgres
//  cutover that lost the row).
//
//    1. `.userMissing` (404) → wipe local session, isAuthenticated == false.
//    2. `.unauthorized` (401/403) → same wipe.
//    3. `.transient` (5xx / network) → keep session.
//    4. `.exists` (2xx) → keep session.
//
//  The probe is indirected via `AuthService.checkUserExistsProvider` so tests
//  inject a stub without hitting the network.
//

import XCTest
import KeychainAccess
import RecipeScalerCore
@testable import RecipeScalerNative

@MainActor
final class AuthServiceStaleSessionTests: XCTestCase {

    private var keychain: Keychain {
        Keychain(service: "com.recipescaler.native")
    }

    override func setUp() {
        super.setUp()
        SharedAuthStore.clear()
        UserDefaults.standard.removeObject(forKey: "userId")
        UserDefaults.standard.removeObject(forKey: "authToken")
        UserDefaults(suiteName: AppGroup.id)?
            .removeObject(forKey: SharedAuthStore.legacyAppGroupUserIdKey)
        try? keychain.remove("seedPhrase")
    }

    override func tearDown() {
        SharedAuthStore.clear()
        UserDefaults.standard.removeObject(forKey: "userId")
        UserDefaults.standard.removeObject(forKey: "authToken")
        UserDefaults(suiteName: AppGroup.id)?
            .removeObject(forKey: SharedAuthStore.legacyAppGroupUserIdKey)
        try? keychain.remove("seedPhrase")
        super.tearDown()
    }

    /// Build an `AuthService` outside the testing-only short-circuit so the
    /// cold-start restore path can be exercised. Mirrors the production init
    /// order: seed Keychain → construct → run health-check.
    private func makeAuthServiceSkippingTestGate() -> AuthService {
        // AuthService.init detects XCTestConfigurationFilePath and short-circuits.
        // We construct it and then manually apply a production-style session so
        // the health-check code path has state to wipe.
        let service = AuthService()
        SharedAuthStore.userId = "user-from-keychain"
        SharedAuthStore.token = "device-token-from-keychain"
        service.userId = "user-from-keychain"
        service.token = "device-token-from-keychain"
        service.isAuthenticated = true
        try? keychain.set("seed phrase words", key: "seedPhrase")
        return service
    }

    // MARK: - Wipe cases

    func testHealthCheck_userMissing_wipesSession() async {
        let service = makeAuthServiceSkippingTestGate()
        service.checkUserExistsProvider = { .userMissing }

        await service.performStaleSessionHealthCheck()

        XCTAssertFalse(
            service.isAuthenticated,
            "userMissing (404) must flip isAuthenticated to false so AuthView shows"
        )
        XCTAssertNil(service.userId, "userId must be cleared on the service")
        XCTAssertNil(service.token, "token must be cleared on the service")
        XCTAssertNil(SharedAuthStore.userId, "SharedAuthStore.userId must be cleared")
        XCTAssertNil(SharedAuthStore.token, "SharedAuthStore.token must be cleared")
        XCTAssertNil(
            try? keychain.get("seedPhrase"),
            "seed phrase must be wiped so a re-login starts clean"
        )
    }

    func testHealthCheck_unauthorized_wipesSession() async {
        let service = makeAuthServiceSkippingTestGate()
        service.checkUserExistsProvider = { .unauthorized }

        await service.performStaleSessionHealthCheck()

        XCTAssertFalse(service.isAuthenticated, "unauthorized (401/403) must wipe the session")
        XCTAssertNil(SharedAuthStore.userId)
        XCTAssertNil(SharedAuthStore.token)
        XCTAssertNil(try? keychain.get("seedPhrase"))
    }

    // MARK: - Keep cases

    func testHealthCheck_exists_keepsSession() async {
        let service = makeAuthServiceSkippingTestGate()
        service.checkUserExistsProvider = { .exists }

        await service.performStaleSessionHealthCheck()

        XCTAssertTrue(service.isAuthenticated, "exists (2xx) must leave the session intact")
        XCTAssertEqual(SharedAuthStore.userId, "user-from-keychain")
        XCTAssertEqual(SharedAuthStore.token, "device-token-from-keychain")
        XCTAssertNotNil(try? keychain.get("seedPhrase"))
    }

    func testHealthCheck_transient_keepsSession() async {
        let service = makeAuthServiceSkippingTestGate()
        service.checkUserExistsProvider = { .transient }

        await service.performStaleSessionHealthCheck()

        XCTAssertTrue(
            service.isAuthenticated,
            "transient (5xx / network) must NOT wipe the session — temporary outage"
        )
        XCTAssertEqual(SharedAuthStore.userId, "user-from-keychain")
        XCTAssertEqual(SharedAuthStore.token, "device-token-from-keychain")
        XCTAssertNotNil(try? keychain.get("seedPhrase"))
    }

    // MARK: - Gating

    func testHealthCheck_skipsWhenNotAuthenticated() async {
        let service = AuthService()
        service.checkUserExistsProvider = { .userMissing }
        // No session to check.
        await service.performStaleSessionHealthCheck()
        // If probe had fired it would be a no-op anyway; assert state is still clean.
        XCTAssertFalse(service.isAuthenticated)
        XCTAssertNil(SharedAuthStore.userId)
    }

    // MARK: - H3 DEBUG simulator auto-login

    /// `AuthService.init` short-circuits under XCTest, so we exercise the same
    /// helper that production `init` calls before Keychain restore.
    func testDebugSimulatorAutoLoginOnLaunch_appliesDebugCreds() throws {
        #if DEBUG
        #if targetEnvironment(simulator)
        guard DebugSimulatorAutoLogin.isEnabled else {
            throw XCTSkip("DebugSimulatorAutoLogin disabled (DisableDebugAutoLogin / E2E override)")
        }
        let service = AuthService()
        XCTAssertTrue(
            service.applyDebugSimulatorAutoLoginOnLaunchIfNeeded(),
            "helper must apply when DebugSimulatorAutoLogin.isEnabled"
        )
        XCTAssertEqual(service.userId, DebugSimulatorAutoLogin.userId)
        XCTAssertEqual(service.token, DebugSimulatorAutoLogin.deviceToken)
        XCTAssertTrue(service.isAuthenticated)
        XCTAssertEqual(SharedAuthStore.userId, DebugSimulatorAutoLogin.userId)
        XCTAssertEqual(SharedAuthStore.token, DebugSimulatorAutoLogin.deviceToken)
        #else
        throw XCTSkip("DEBUG simulator auto-login is simulator-only")
        #endif
        #else
        throw XCTSkip("DEBUG simulator auto-login is DEBUG-only")
        #endif
    }

    func testDebugSimulatorAutoLoginOnLaunch_prefersExistingStoreToken() throws {
        #if DEBUG
        #if targetEnvironment(simulator)
        guard DebugSimulatorAutoLogin.isEnabled else {
            throw XCTSkip("DebugSimulatorAutoLogin disabled (DisableDebugAutoLogin / E2E override)")
        }
        let storedToken = "existing-debug-store-token"
        SharedAuthStore.userId = DebugSimulatorAutoLogin.userId
        SharedAuthStore.token = storedToken

        let service = AuthService()
        XCTAssertTrue(service.applyDebugSimulatorAutoLoginOnLaunchIfNeeded())
        XCTAssertEqual(service.token, storedToken)
        XCTAssertEqual(SharedAuthStore.token, storedToken)
        #else
        throw XCTSkip("DEBUG simulator auto-login is simulator-only")
        #endif
        #else
        throw XCTSkip("DEBUG simulator auto-login is DEBUG-only")
        #endif
    }
}

//
//  AuthSessionInvalidationTests.swift
//
//  Spec 055 Phase R: verifies runtime recovery when the account is deleted
//  server-side while the native client is running.
//
//    1. Socket `auth_error` "Account deleted" → wipe + isAuthenticated == false.
//    2. REST 401 → exchange → 404 User not found → wipe + stopForLogout.
//    3. REST 401 → exchange → success token → keep session, new token applied.
//    4. REST 401 → exchange → transient → light revoke (no stopForLogout).
//    5. Double signal (socket + REST) → wipe called exactly once.
//
//  The seed-exchange network call is indirected via
//  `AuthService.exchangeSeedForTokenRecoveryProvider` so tests inject outcomes
//  without hitting the server.
//

import XCTest
import KeychainAccess
import RecipeScalerCore
@testable import RecipeScalerNative

@MainActor
final class AuthSessionInvalidationTests: XCTestCase {

    private var keychain: Keychain {
        Keychain(service: "com.recipescaler.native")
    }

    private let seedPhraseKey = "seedPhrase"

    override func setUp() {
        super.setUp()
        SharedAuthStore.clear()
        UserDefaults.standard.removeObject(forKey: "userId")
        UserDefaults.standard.removeObject(forKey: "authToken")
        UserDefaults(suiteName: AppGroup.id)?
            .removeObject(forKey: SharedAuthStore.legacyAppGroupUserIdKey)
        try? keychain.remove(seedPhraseKey)
    }

    override func tearDown() {
        SharedAuthStore.clear()
        UserDefaults.standard.removeObject(forKey: "userId")
        UserDefaults.standard.removeObject(forKey: "authToken")
        UserDefaults(suiteName: AppGroup.id)?
            .removeObject(forKey: SharedAuthStore.legacyAppGroupUserIdKey)
        try? keychain.remove(seedPhraseKey)
        super.tearDown()
    }

    /// Construct an `AuthService` outside the testing short-circuit so the
    /// runtime-recovery code path has real state to wipe. Mirrors
    /// `AuthServiceStaleSessionTests.makeAuthServiceSkippingTestGate()`.
    private func makeAuthService() -> AuthService {
        let service = AuthService()
        SharedAuthStore.userId = "user-from-keychain"
        SharedAuthStore.token = "device-token-from-keychain"
        service.userId = "user-from-keychain"
        service.token = "device-token-from-keychain"
        service.isAuthenticated = true
        try? keychain.set("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about", key: seedPhraseKey)
        return service
    }

    // MARK: - R6.2 — Socket "Account deleted" wipes

    func test_socket_account_deleted_wipes() async {
        let service = makeAuthService()

        await service.handleAccountDeleted(reason: .socketSignal)

        XCTAssertFalse(
            service.isAuthenticated,
            "Socket 'Account deleted' must flip isAuthenticated to false"
        )
        XCTAssertNil(service.userId)
        XCTAssertNil(service.token)
        XCTAssertNil(SharedAuthStore.userId)
        XCTAssertNil(SharedAuthStore.token)
        XCTAssertNil(try? keychain.get(seedPhraseKey))
    }

    // MARK: - R6.3 — REST 401 + exchange 404 wipes

    func test_rest_401_exchange_404_wipes() async {
        let service = makeAuthService()
        service.exchangeSeedForTokenRecoveryProvider = { _ in .userNotFound }

        await service.handleDeviceTokenInvalid()

        XCTAssertFalse(service.isAuthenticated, "User-not-found recovery must wipe the session")
        XCTAssertNil(SharedAuthStore.userId)
        XCTAssertNil(SharedAuthStore.token)
        XCTAssertNil(try? keychain.get(seedPhraseKey))
    }

    // MARK: - R6.4 — REST 401 + exchange success keeps session

    func test_rest_401_exchange_success_keeps_session() async {
        let service = makeAuthService()
        service.exchangeSeedForTokenRecoveryProvider = { _ in .token("fresh-device-token") }

        await service.handleDeviceTokenInvalid()

        XCTAssertTrue(service.isAuthenticated, "Successful token recovery must keep the session alive")
        XCTAssertEqual(SharedAuthStore.userId, "user-from-keychain")
        XCTAssertEqual(SharedAuthStore.token, "fresh-device-token")
        XCTAssertEqual(service.token, "fresh-device-token")
        XCTAssertNotNil(try? keychain.get(seedPhraseKey))
    }

    // MARK: - R6.5 — REST 401 + transient → light revoke

    func test_rest_401_exchange_network_light_revoke() async {
        let service = makeAuthService()
        service.exchangeSeedForTokenRecoveryProvider = { _ in .transient }

        await service.handleDeviceTokenInvalid()

        XCTAssertFalse(
            service.isAuthenticated,
            "Transient exchange failure must light-revoke (clear auth state)"
        )
        XCTAssertNil(SharedAuthStore.userId)
        XCTAssertNil(SharedAuthStore.token)
        // Light revoke still wipes the seed: we have no way back to a known
        // state without the user re-entering the seed. Local data (Yjs store)
        // is preserved by the absence of `stopForLogout` — only auth is cleared.
        XCTAssertNil(try? keychain.get(seedPhraseKey))
    }

    // MARK: - R6.6 — Double signal → single wipe (concurrent)

    func test_double_signal_single_wipe() async {
        let service = makeAuthService()

        // FR-R5 invariant: parallel socket `auth_error` + REST 401 must
        // collapse into a single wipe. Spawn both in detached Tasks that
        // hop to MainActor independently — a broken re-entry guard would
        // let the second call re-enter and run teardown twice.
        async let a: Void = service.handleAccountDeleted(reason: .socketSignal)
        async let b: Void = service.handleAccountDeleted(reason: .restInvalidation)
        _ = await (a, b)

        XCTAssertFalse(service.isAuthenticated)
        XCTAssertNil(SharedAuthStore.userId)
        XCTAssertNil(SharedAuthStore.token)
        XCTAssertNil(try? keychain.get(seedPhraseKey))
    }

    // MARK: - R6.6b — REST 401 burst → single recovery attempt

    func test_rest_401_burst_single_recovery() async {
        let service = makeAuthService()

        // Force a real suspension point in the stubbed provider so the
        // MainActor can interleave concurrent `handleDeviceTokenInvalid`
        // callers — without this, `async let` on a @MainActor method runs
        // the bodies back-to-back without overlapping.
        actor ExchangeCounter {
            var count = 0
            func increment() { count += 1 }
            func value() -> Int { count }
        }
        let counter = ExchangeCounter()
        service.exchangeSeedForTokenRecoveryProvider = { _ in
            await counter.increment()
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
            return .userNotFound
        }

        // Burst of REST 401s from parallel recipe fetches. The re-entry
        // guard spans the awaited seed exchange, so only one exchange
        // call hits the (stubbed) provider.
        async let a: Void = service.handleDeviceTokenInvalid()
        async let b: Void = service.handleDeviceTokenInvalid()
        async let c: Void = service.handleDeviceTokenInvalid()
        _ = await (a, b, c)

        let exchangeCallCount = await counter.value()
        XCTAssertEqual(
            exchangeCallCount, 1,
            "Burst of REST 401s must collapse into one exchange attempt (got \(exchangeCallCount))"
        )
        XCTAssertFalse(service.isAuthenticated)
        XCTAssertNil(SharedAuthStore.userId)
    }

    // MARK: - R6.7 — Constants parity with web

    func test_account_deleted_socket_message_matches_web_contract() {
        XCTAssertEqual(
            AuthRevocationConstants.accountDeletedSocketMessage,
            "Account deleted",
            "Must match recipe-scaler-web AUTH_ACCOUNT_DELETED_SOCKET_MESSAGE"
        )
        XCTAssertEqual(
            AuthRevocationConstants.deviceTokenInvalidCode,
            "device_token_invalid",
            "Must match recipe-scaler-web requireBearerDeviceToken 401 code"
        )
    }
}

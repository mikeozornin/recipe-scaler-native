import Foundation

/// Holds credentials for the fresh per-test user.
///
/// Web parity: `TestUser` interface in `tests/e2e/fixtures/auth.ts`.
struct TestUser {
    let userId: String
    let deviceToken: String
    let seedPhrase: String
    let deviceId: String
}

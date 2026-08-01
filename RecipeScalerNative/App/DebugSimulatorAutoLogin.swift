import Foundation

#if DEBUG
/// Simulator-only DEBUG auto-login against the shared prod debug user.
///
/// After legacy `x-user-id` cutoff (spec 041), auto-login must inject a
/// `device_token` alongside `userId` — same pattern as E2E launch env
/// (`E2E_OVERRIDE_USER_ID` / `E2E_OVERRIDE_DEVICE_TOKEN`).
///
/// Token resolution order:
/// 1. `DEBUG_DEVICE_TOKEN` or `E2E_OVERRIDE_DEVICE_TOKEN` launch env
/// 2. Bundled fallback token (rotated via `/exchange-seed-for-token` when stale)
///
/// Seed phrase is documented in `docs/PROJECT.md` and kept here so bootstrap
/// can re-exchange if the bundled token is revoked.
enum DebugSimulatorAutoLogin {
    static let userId = "cfcd839f-56f2-4411-9632-7795b75f96d1"

    /// Same phrase as `docs/PROJECT.md` — DEBUG simulator recovery only.
    static let seedPhrase =
        "mass layer gossip slight bachelor broken spend story rabbit biology tower blast"

    /// Last known valid Bearer for `device_id=debug-simulator-autologin`.
    /// Prefer launch-env override; re-exchange via seed if this is revoked.
    private static let bundledDeviceToken =
        "BnSx2ROVt4p_ADYNS1ctvvcS3AtuBAwknV-I0_0FGfM"

    static var isEnabled: Bool {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-DisableDebugAutoLogin=1") {
            return false
        }
        if let env = ProcessInfo.processInfo.environment["E2E_OVERRIDE_USER_ID"],
           !env.isEmpty {
            return false
        }
        return true
        #else
        return false
        #endif
    }

    /// Launch-env token, else bundled DEBUG fallback.
    static var deviceToken: String {
        let env = ProcessInfo.processInfo.environment
        for key in ["DEBUG_DEVICE_TOKEN", "E2E_OVERRIDE_DEVICE_TOKEN"] {
            if let value = env[key], !value.isEmpty {
                return value
            }
        }
        return bundledDeviceToken
    }
}
#endif

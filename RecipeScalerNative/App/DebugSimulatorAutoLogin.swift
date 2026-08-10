import Foundation

#if DEBUG
/// DEBUG auto-login against the shared prod debug user.
///
/// iOS enables this for Simulator builds. Native macOS enables it only when
/// launched with `-DebugMacAutoLogin=1`, so a normal Mac launch still exposes
/// the explicit auth screen.
///
/// After legacy `x-user-id` cutoff (spec 041), auto-login must inject a
/// `device_token` alongside `userId` — same pattern as E2E launch env
/// (`E2E_OVERRIDE_USER_ID` / `E2E_OVERRIDE_DEVICE_TOKEN`).
///
/// Token resolution order:
/// 1. `DEBUG_DEVICE_TOKEN` or `E2E_OVERRIDE_DEVICE_TOKEN` launch env
/// 2. Bundled fallback token (rotated via `/exchange-seed-for-token` when stale)
///
/// Seed phrase is documented in `docs/PROJECT.md` and kept here so AuthService
/// / post-wipe bootstrap can re-exchange if the bundled token is revoked.
enum DebugSimulatorAutoLogin {
    static let userId = "f088233a-cfed-4fa5-8284-daa2d1ab827c"

    /// Same phrase as `docs/PROJECT.md` — DEBUG simulator recovery only.
    static let seedPhrase =
        "breeze roast wink solar guess tongue nothing subway theme palace mask wrist"

    /// Last known valid Bearer for `device_id=debug-simulator-autologin`.
    /// Prefer launch-env override; re-exchange via seed if this is revoked.
    private static let bundledDeviceToken =
        "Q5Xhsf1lxkGDE4F5ssFMgv2M6zlzoRHMBPDU7IJkNJE"

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
        #elseif os(macOS)
        return ProcessInfo.processInfo.arguments.contains("-DebugMacAutoLogin=1")
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

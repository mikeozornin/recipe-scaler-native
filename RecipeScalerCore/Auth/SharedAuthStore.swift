//
//  SharedAuthStore.swift
//  RecipeScalerCore
//
//  Encrypted credential storage for the main app and extensions.
//
//  Stores the authenticated `userId` and per-device `device_token` in the iOS Keychain
//  (`kSecClassGenericPassword`) so that forensic extraction of on-disk
//  plists (UserDefaults) cannot reveal them. Sharing across the main app
//  and Share/Action/Home/Timer extensions is achieved via a shared
//  keychain access group declared in every target's entitlements:
//
//      <key>keychain-access-groups</key>
//      <array>
//          <string>$(AppIdentifierPrefix)ru.recipescaler.RecipeScaler</string>
//      </array>
//
//  `$(AppIdentifierPrefix)` expands at codesign time to `ZBPX4JYT24.`.
//  Swift must use the expanded team-prefixed string — the Xcode macro is
//  not substituted in source.
//
//  Writes mirror into both the shared access group (for extensions on device)
//  and the process-scoped keychain (fallback when the entitlement is missing,
//  e.g. some XCTest hosts). Reads prefer the shared group, then ungrouped.
//

import Foundation
import Security

public enum SharedAuthStore {
    /// Keychain service under which credential items live.
    public static let keychainService = "com.recipescaler.shared"

    /// Keychain account name for the authenticated user identifier.
    public static let userIdAccount = "userId"

    /// Keychain account name for the device bearer token (spec 041).
    public static let tokenAccount = "token"

    /// Legacy App Group UserDefaults key retained only to purge leftover
    /// plaintext copies from older app versions during migration. The
    /// `userId` itself is never written here anymore. Purge reads/writes use
    /// `AppGroup.id` for the shared `UserDefaults` suite.
    public static let legacyAppGroupUserIdKey = "shared.userId"

    /// Team ID from `DEVELOPMENT_TEAM` (`ZBPX4JYT24`) + keychain sharing suffix.
    /// Matches entitlements after `$(AppIdentifierPrefix)` expansion.
    public static let sharedKeychainAccessGroup = "ZBPX4JYT24.ru.recipescaler.RecipeScaler"

    /// Documented access group for SecItem queries. Always the team-prefixed
    /// group — never the literal `$(AppIdentifierPrefix)…` macro.
    public static var keychainAccessGroup: String? {
        sharedKeychainAccessGroup
    }

    /// Currently authenticated user identifier, or `nil` when signed out.
    public static var userId: String? {
        get { readString(account: userIdAccount) }
        set {
            if let newValue {
                writeString(newValue, account: userIdAccount)
            } else {
                clear()
            }
        }
    }

    /// Per-device bearer token issued by the API (spec 041). `nil` when signed out.
    public static var token: String? {
        get { readString(account: tokenAccount) }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                writeString(trimmed, account: tokenAccount)
            } else {
                deleteItem(account: tokenAccount)
            }
        }
    }

    /// Remove stored credentials. Idempotent — calling on an empty store is a no-op.
    /// Clears both shared-group and process-scoped items.
    public static func clear() {
        deleteItem(account: userIdAccount)
        deleteItem(account: tokenAccount)
    }

    // MARK: - Keychain primitives

    private static func baseQuery(account: String, accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    /// Prefer shared access group (extensions on device); fall back to process-scoped.
    private static func readString(account: String) -> String? {
        if let shared = copyMatching(account: account, accessGroup: sharedKeychainAccessGroup) {
            return shared
        }
        return copyMatching(account: account, accessGroup: nil)
    }

    private static func copyMatching(account: String, accessGroup: String?) -> String? {
        var query = baseQuery(account: account, accessGroup: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Mirror into shared group (best-effort) and process-scoped keychain.
    /// Extensions on a paid/signed build read the shared copy; XCTest hosts
    /// that cannot use the access group still round-trip via the ungrouped copy.
    private static func writeString(_ value: String, account: String) {
        let data = Data(value.utf8)
        _ = upsert(data: data, account: account, accessGroup: sharedKeychainAccessGroup)
        _ = upsert(data: data, account: account, accessGroup: nil)
    }

    @discardableResult
    private static func upsert(data: Data, account: String, accessGroup: String?) -> OSStatus {
        deleteItem(account: account, accessGroup: accessGroup)
        var query = baseQuery(account: account, accessGroup: accessGroup)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecAttrSynchronizable as String] = kCFBooleanFalse
        return SecItemAdd(query as CFDictionary, nil)
    }

    private static func deleteItem(account: String) {
        deleteItem(account: account, accessGroup: sharedKeychainAccessGroup)
        deleteItem(account: account, accessGroup: nil)
    }

    private static func deleteItem(account: String, accessGroup: String?) {
        SecItemDelete(baseQuery(account: account, accessGroup: accessGroup) as CFDictionary)
    }
}

public enum AuthClientMetadata {
    public static let nativePlatform: String = {
        #if os(macOS)
        return "macos-native"
        #elseif os(watchOS)
        return watchPlatform
        #else
        return "ios-native"
        #endif
    }()
    public static let watchPlatform = "ios-watch"

    public static func appVersion() -> String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }
}

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
//  keychain access group declared in every target's entitlements.
//
//  On simulator / unsigned dev builds without a paid provisioning profile
//  the access-group attribute is omitted: the keychain still works, just
//  scoped to the single process. Production builds MUST add:
//
//      <key>keychain-access-groups</key>
//      <array>
//          <string>$(AppIdentifierPrefix)ru.recipescaler.RecipeScalerNative</string>
//      </array>
//
//  to every consuming target's entitlements.
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

    /// Shared keychain access group. Resolves to `nil` on simulator / dev
    /// builds (no provisioning profile) so the keychain query stays valid
    /// without an access-group attribute. On signed builds the value is
    /// `$(AppIdentifierPrefix)ru.recipescaler.RecipeScalerNative`.
    public static var keychainAccessGroup: String? {
        if hasKeychainAccessGroupEntitlement {
            return "$(AppIdentifierPrefix)ru.recipescaler.RecipeScalerNative"
        }
        return nil
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
    public static func clear() {
        deleteItem(account: userIdAccount)
        deleteItem(account: tokenAccount)
    }

    // MARK: - Keychain primitives

    private static func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        if let group = keychainAccessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        return query
    }

    private static func readString(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func writeString(_ value: String, account: String) {
        let data = Data(value.utf8)
        var query = baseQuery(account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecAttrSynchronizable as String] = kCFBooleanFalse

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            var updateQuery = baseQuery(account: account)
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                kSecAttrSynchronizable as String: kCFBooleanFalse,
            ]
            SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
        }
    }

    private static func deleteItem(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    // MARK: - Entitlement probe

    private static var hasKeychainAccessGroupEntitlement: Bool {
        Bundle.main.object(forInfoDictionaryKey: "keychain-access-groups") != nil
    }
}

public enum AuthClientMetadata {
    public static let nativePlatform = "ios-native"
    public static let watchPlatform = "ios-watch"

    public static func appVersion() -> String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }
}
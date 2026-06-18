//
//  SharedAuthStore.swift
//  RecipeScalerCore
//
//  Encrypted credential storage for the main app and extensions.
//
//  Stores the currently authenticated `userId` in the iOS Keychain
//  (`kSecClassGenericPassword`) so that forensic extraction of on-disk
//  plists (UserDefaults) cannot reveal it. Sharing across the main app
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

    /// Legacy App Group UserDefaults key retained only to purge leftover
    /// plaintext copies from older app versions during migration. The
    /// `userId` itself is never written here anymore.
    public static let legacyAppGroupUserIdKey = "shared.userId"

    /// App Group identifier used historically to mirror `userId` as plaintext
    /// in a shared `UserDefaults` suite. Retained for the one-shot legacy
    /// purge on app launch — new code MUST NOT write here.
    public static let appGroupID = AppGroup.id

    /// Shared keychain access group. Resolves to `nil` on simulator / dev
    /// builds (no provisioning profile) so the keychain query stays valid
    /// without an access-group attribute. On signed builds the value is
    /// `$(AppIdentifierPrefix)ru.recipescaler.RecipeScalerNative`.
    public static var keychainAccessGroup: String? {
        // Explicitly opt-in: only set when the host target declares the
        // entitlement via the Info.plist marker. This avoids errSecMissingEntitlement
        // on simulator runs (which are unsigned and have no Team prefix).
        if hasKeychainAccessGroupEntitlement {
            return "$(AppIdentifierPrefix)ru.recipescaler.RecipeScalerNative"
        }
        return nil
    }

    /// Currently authenticated user identifier, or `nil` when signed out.
    ///
    /// Reads/writes go directly to the Keychain via the Security framework.
    /// Writes are atomic from the API consumer's perspective: setting `nil`
    /// removes the item, overwriting an existing value replaces it in place.
    public static var userId: String? {
        get { readUserId() }
        set {
            if let newValue {
                writeUserId(newValue)
            } else {
                clear()
            }
        }
    }

    /// Remove the stored user identifier. Idempotent — calling on an empty
    /// store is a no-op and never throws.
    public static func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    // MARK: - Keychain primitives

    private static func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: userIdAccount,
        ]
        if let group = keychainAccessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        return query
    }

    private static func readUserId() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func writeUserId(_ userId: String) {
        let data = Data(userId.utf8)
        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        // Try to add first. If the item already exists, update its value in place.
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            var updateQuery = baseQuery()
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
        }
    }

    // MARK: - Entitlement probe

    /// Detects whether the host target declares a shared keychain access group.
    ///
    /// The entitlement key (`keychain-access-groups`) is only embedded into the
    /// binary by Xcode when the corresponding `.entitlements` file lists one. On
    /// unsigned simulator builds it is absent, so we must omit the access-group
    /// attribute from the query to avoid `errSecMissingEntitlement` (-34018).
    private static var hasKeychainAccessGroupEntitlement: Bool {
        Bundle.main.object(forInfoDictionaryKey: "keychain-access-groups") != nil
    }
}

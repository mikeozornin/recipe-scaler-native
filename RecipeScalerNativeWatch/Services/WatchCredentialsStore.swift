//
//  WatchCredentialsStore.swift
//  RecipeScalerNativeWatch Watch App
//
//  Spec 039 — watch-local Keychain storage for `userId`.
//
//  On iOS the userId lives in a shared Keychain access group. The watch uses
//  a private, watch-local Keychain entry — no access group, no sharing with
//  iPhone keychain. Access class is `AfterFirstUnlockThisDeviceOnly` so the
//  value survives reboots but not device restore / backup.
//

import Foundation
import Security

enum WatchCredentialsStore {
    private static let service = "com.recipescaler.watch"
    private static let account = "userId"

    /// Read the stored userId, or `nil` if not set / purge received.
    static var userId: String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    /// Persist userId for subsequent launches. Empty / nil clears it.
    static func set(_ userId: String?) {
        let previousUserId = Self.userId
        if let userId, !userId.isEmpty {
            save(userId)
            WatchFeatureAdoptionReporter.reportFirstOpenIfNeeded()
        } else {
            if let previousUserId {
                WatchFeatureAdoptionReporter.clearLocalReport(for: previousUserId)
            }
            clear()
        }
    }

    /// Remove stored userId (logout / purge from iPhone).
    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func save(_ userId: String) {
        let data = Data(userId.utf8)
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        // Try update first (cheaper), fall back to add.
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecItemNotFound {
            SecItemAdd(attrs as CFDictionary, nil)
        }
    }
}

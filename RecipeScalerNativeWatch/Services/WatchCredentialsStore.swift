//
//  WatchCredentialsStore.swift
//  RecipeScalerNativeWatch Watch App
//
//  Spec 039 — watch-local Keychain storage for `userId`.
//  Spec 041 — `token` for Bearer API auth from iPhone WC bridge.
//

import Foundation
import Security

enum WatchCredentialsStore {
    private static let service = "com.recipescaler.watch"
    private static let userIdAccount = "userId"
    private static let tokenAccount = "token"

    static var userId: String? {
        readString(account: userIdAccount)
    }

    static var token: String? {
        readString(account: tokenAccount)
    }

    /// Persist userId for subsequent launches. Empty / nil clears credentials.
    static func set(_ userId: String?, token: String? = nil) {
        let previousUserId = Self.userId
        if let userId, !userId.isEmpty {
            save(userId, account: userIdAccount)
            if let token, !token.isEmpty {
                save(token, account: tokenAccount)
            } else {
                deleteItem(account: tokenAccount)
            }
            WatchFeatureAdoptionReporter.reportFirstOpenIfNeeded()
        } else {
            if let previousUserId {
                WatchFeatureAdoptionReporter.clearLocalReport(for: previousUserId)
            }
            clear()
        }
    }

    static func clear() {
        deleteItem(account: userIdAccount)
        deleteItem(account: tokenAccount)
    }

    private static func readString(account: String) -> String? {
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

    private static func save(_ value: String, account: String) {
        let data = Data(value.utf8)
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: kCFBooleanFalse,
        ]
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: kCFBooleanFalse,
        ]
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecItemNotFound {
            SecItemAdd(attrs as CFDictionary, nil)
        }
    }

    private static func deleteItem(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
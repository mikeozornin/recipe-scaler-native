//
//  AssistantSessionStore.swift
//  RecipeScalerNative
//
//  OS facade for the assistant chat session persistence (review 2026.09.04 №19).
//  Views must not touch `UserDefaults.standard` directly — the same key pair
//  was written from four places in `AssistantSheet`, which is exactly the kind
//  of scattered access that gets missed when keys move to an App Group
//  (spec 066 side-by-side flavor).
//

import Foundation

enum AssistantSessionStore {
    private static let threadIdKey = "assistant.session.threadId"
    private static let lastOpenedAtKey = "assistant.session.lastOpenedAt"

    /// Persisted thread id of the last open assistant chat, if any.
    static var threadId: String? {
        UserDefaults.standard.string(forKey: threadIdKey)
    }

    /// Wall-clock timestamp of the last session stamp (used for the
    /// "continue recent chat" timeout in `AssistantSheet`).
    static var lastOpenedAt: TimeInterval {
        UserDefaults.standard.double(forKey: lastOpenedAtKey)
    }

    /// Stamp the session: bump `lastOpenedAt` and store / clear the thread id.
    static func persist(threadId: String?, now: TimeInterval = Date().timeIntervalSince1970) {
        UserDefaults.standard.set(now, forKey: lastOpenedAtKey)
        if let threadId {
            UserDefaults.standard.set(threadId, forKey: threadIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: threadIdKey)
        }
    }

    /// Drop the persisted thread (new chat / session reset).
    static func clearThreadId() {
        UserDefaults.standard.removeObject(forKey: threadIdKey)
    }
}

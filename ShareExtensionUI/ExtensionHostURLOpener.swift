//
//  ExtensionHostURLOpener.swift
//  ShareExtensionUI
//
//  Share extensions cannot rely on NSExtensionContext.open (returns false).
//  On iOS 18+, walk the responder chain to UIApplication.open(_:options:).
//  When neither path succeeds, the App Group `routing.pendingRecipeId` slot
//  written by `ShareView.openRecipeInHostApp()` carries the id to the host
//  on its next launch via `DeepLinkRouter.consumePendingRecipeId()`.
//
//  Note: a runtime `UIApplication.sharedApplication` fallback via
//  `NSSelectorFromString` / `perform(_:)` was considered and removed — it
//  shows up in App Review's static binary analysis as private API usage and
//  risks rejection under guideline 2.5.1.
//

import UIKit

enum ExtensionHostURLOpener {
    /// Attempts to open `url` in the containing app.
    /// 1) `NSExtensionContext.open` (Today / some Action hosts)
    /// 2) `UIApplication.open` via responder chain
    /// 3) Fall back to App Group IPC (host consumes on next launch)
    static func open(
        _ url: URL,
        extensionContext: NSExtensionContext?,
        from responder: UIResponder?,
        completion: @escaping (Bool) -> Void
    ) {
        if let extensionContext {
            extensionContext.open(url) { success in
                if success {
                    completion(true)
                    return
                }
                openViaApplication(url, from: responder, completion: completion)
            }
            return
        }
        openViaApplication(url, from: responder, completion: completion)
    }

    private static func openViaApplication(
        _ url: URL,
        from responder: UIResponder?,
        completion: @escaping (Bool) -> Void
    ) {
        var current: UIResponder? = responder
        while let candidate = current {
            if let application = candidate as? UIApplication {
                application.open(url, options: [:], completionHandler: completion)
                return
            }
            current = candidate.next
        }

        // No UIApplication in the responder chain. The App Group slot
        // written by `ShareView.openRecipeInHostApp()` carries the recipe id
        // to the host on its next launch — caller treats `false` as
        // "complete the share request; id survives via App Group".
        completion(false)
    }
}

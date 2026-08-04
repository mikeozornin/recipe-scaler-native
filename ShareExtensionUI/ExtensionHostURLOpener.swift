//
//  ExtensionHostURLOpener.swift
//  ShareExtensionUI
//
//  Share extensions cannot rely on NSExtensionContext.open (returns false).
//  On iOS 18+, walk the responder chain to UIApplication.open(_:options:),
//  then fall back to runtime UIApplication.sharedApplication.
//

import UIKit

enum ExtensionHostURLOpener {
    /// Attempts to open `url` in the containing app.
    /// 1) `NSExtensionContext.open` (Today / some Action hosts)
    /// 2) `UIApplication.open` via responder chain
    /// 3) Runtime `sharedApplication` (Share on iOS 18+)
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

        // UIApplication.shared is unavailable at compile time in extensions;
        // resolve at runtime (common Share Extension pattern).
        let sel = NSSelectorFromString("sharedApplication")
        if let appType = NSClassFromString("UIApplication") as? NSObject.Type,
           appType.responds(to: sel),
           let unmanaged = appType.perform(sel),
           let application = unmanaged.takeUnretainedValue() as? UIApplication {
            application.open(url, options: [:], completionHandler: completion)
            return
        }

        completion(false)
    }
}

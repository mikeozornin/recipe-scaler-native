import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// NDJSON debug trace (`/debug` workflow). Filter device logs by `[sync]` or `topic":"sync"`.
/// Compatibility wrapper — delegates to `AppLog`.
enum AgentSyncDebugLog {
    /// Socket.IO connection lifecycle (send these lines when reporting sync bugs).
    static func sync(
        location: String,
        message: String,
        data: [String: String] = [:]
    ) {
        var enriched = data
        enriched["topic"] = "sync"
        write(hypothesisId: "sync", location: location, message: message, data: enriched)
    }

    static func write(
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: String]
    ) {
        #if DEBUG
        guard AgentDebugLogging.isEnabled else { return }
        AppLog.agent(hypothesisId: hypothesisId, location: location, message: message, data: data)
        #endif
    }

    /// On-device NDJSON session log, for export/sharing from the account screen.
    static func sessionLogFileURL() -> URL? {
        AppLog.currentLogFileURL()
    }

    #if DEBUG
    // #region agent log
    /// Assistant dismiss / nav-bar layout probe (session 25add8).
    static func assistantLayout(
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: String] = [:]
    ) {
        write(hypothesisId: hypothesisId, location: location, message: message, data: data)
    }

    static func logNavigationBarState(hypothesisId: String, location: String, tag: String) {
        #if canImport(UIKit)
        DispatchQueue.main.async {
            var data: [String: String] = ["tag": tag]
            guard let root = keyWindowRootViewController() else {
                data["nav"] = "no_root"
                write(hypothesisId: hypothesisId, location: location, message: "nav_bar_snapshot", data: data)
                return
            }
            data["hasPresented"] = root.presentedViewController != nil ? "true" : "false"
            if let presented = root.presentedViewController {
                data["presented"] = String(describing: type(of: presented))
            }
            if let nav = findNavigationController(from: root) {
                data["navBarHidden"] = nav.isNavigationBarHidden ? "true" : "false"
                data["navBarTranslucent"] = nav.navigationBar.isTranslucent ? "true" : "false"
            } else {
                data["navBarHidden"] = "no_nav"
            }
            write(hypothesisId: hypothesisId, location: location, message: "nav_bar_snapshot", data: data)
        }
        #endif
    }

    #if canImport(UIKit)
    private static func keyWindowRootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }

    private static func findNavigationController(from root: UIViewController?) -> UINavigationController? {
        guard let root else { return nil }
        if let nav = root as? UINavigationController { return nav }
        for child in root.children {
            if let nav = findNavigationController(from: child) { return nav }
        }
        if let presented = root.presentedViewController {
            if let nav = findNavigationController(from: presented) { return nav }
        }
        return nil
    }
    #endif
    // #endregion
    #endif
}

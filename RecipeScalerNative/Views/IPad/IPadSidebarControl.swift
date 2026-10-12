import SwiftUI
import UIKit

/// The only UIKit code of the iPad shell (spec 081, plan.md Р2, spike S1/S2).
///
/// SwiftUI can read the tab bar placement (`\.tabBarPlacement`) but cannot show or hide
/// the `.sidebarAdaptable` sidebar, so this goes through `UITabBarController.sidebar`.
/// Used only in `.padRegular` on iPadOS 26.2+. If the controller is not found it logs
/// and does nothing: the sidebar stays as the system left it.
@available(iOS 26.2, *)
@MainActor
enum IPadSidebarControl {
    /// True while the sidebar is shown on top of dimmed content (portrait), rather than
    /// beside it: the selected page then keeps a leading safe-area inset of about 0.
    static var sidebarOverlaysContent: Bool {
        guard let tabBarController = tabBarController(), !tabBarController.sidebar.isHidden else {
            return false
        }
        let leadingInset = tabBarController.selectedViewController?.view.safeAreaInsets.left ?? 0
        return leadingInset < IPadLayoutMetrics.sidebarOverlayMaxLeadingInset
    }

    /// The sidebar is on screen, beside the content or over it.
    static var isSidebarShown: Bool {
        tabBarController().map { !$0.sidebar.isHidden } ?? false
    }

    static func setSidebarHidden(_ hidden: Bool) {
        guard let tabBarController = tabBarController() else {
            AppLog.notice(.ui, "ipad_sidebar_controller_missing", data: ["hidden": hidden ? "true" : "false"])
            return
        }
        tabBarController.sidebar.isHidden = hidden
    }

    /// A programmatic selection (the profile footer) does not close a floating sidebar,
    /// unlike a tap on a sidebar row (spike S1, workaround 3).
    static func hideSidebarIfOverlaying() {
        guard sidebarOverlaysContent else { return }
        setSidebarHidden(true)
    }

    private static func tabBarController() -> UITabBarController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        return TabBarDiscovery.find(in: window?.rootViewController)
    }
}

extension View {
    /// Reports whether the sidebar is on screen, from a page of the `TabView`
    /// (Scrapp `RootView.swift:311-327`). The placement follows the sidebar opened and
    /// closed in portrait; the sidebar's own geometry does not (UIKit slides it in).
    func reportsIPadSidebarShown(_ shown: Binding<Bool>) -> some View {
        modifier(IPadSidebarReporter(shown: shown))
    }
}

private struct IPadSidebarReporter: ViewModifier {
    @Binding var shown: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.modifier(IPadSidebarPlacementReader(shown: $shown))
        } else {
            content
        }
    }
}

@available(iOS 18.0, *)
private struct IPadSidebarPlacementReader: ViewModifier {
    @Environment(\.tabBarPlacement) private var placement
    @Binding var shown: Bool

    func body(content: Content) -> some View {
        content.onChange(of: placement, initial: true) {
            let isSidebar = placement == .sidebar
            if shown != isSidebar {
                shown = isSidebar
            }
        }
    }
}

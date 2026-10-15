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

    /// Lets `motion` know while the sidebar shows or hides. Again on every call: the
    /// controller is found only after the first layout pass.
    static func observeMotion(_ motion: IPadSidebarMotion) {
        guard let sidebar = tabBarController()?.sidebar else { return }
        motion.attach(to: sidebar)
    }

    private static func tabBarController() -> UITabBarController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        return TabBarDiscovery.find(in: window?.rootViewController)
    }
}

/// The sidebar is sliding in or out. `\.tabBarPlacement` turns `.sidebar` as the top bar
/// starts to grow into the sidebar and stays so while the sidebar shrinks back into the
/// bar, so badges keyed on it alone flash in the top bar (DECISIONS: no badges there).
@available(iOS 26.2, *)
@MainActor
@Observable
final class IPadSidebarMotion {
    private(set) var isMoving = false
    @ObservationIgnored private var proxy: IPadSidebarDelegateProxy?

    fileprivate func attach(to sidebar: UITabBarController.Sidebar) {
        if let proxy, sidebar.delegate === proxy { return }
        let proxy = IPadSidebarDelegateProxy(forwarded: sidebar.delegate) { [weak self] animator in
            self?.isMoving = true
            animator.addCompletion { self?.isMoving = false }
        }
        self.proxy = proxy
        sidebar.delegate = proxy
    }
}

/// Hears `sidebarVisibilityWillChange` and hands every delegate call on to the delegate
/// it replaced, if SwiftUI set one.
@available(iOS 26.2, *)
@MainActor
private final class IPadSidebarDelegateProxy: NSObject, UITabBarController.Sidebar.Delegate {
    private weak var forwarded: (any UITabBarController.Sidebar.Delegate)?
    private let willChange: (any UITabBarController.Sidebar.Animating) -> Void

    init(
        forwarded: (any UITabBarController.Sidebar.Delegate)?,
        willChange: @escaping (any UITabBarController.Sidebar.Animating) -> Void
    ) {
        self.forwarded = forwarded
        self.willChange = willChange
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        sidebarVisibilityWillChange sidebar: UITabBarController.Sidebar,
        animator: any UITabBarController.Sidebar.Animating
    ) {
        willChange(animator)
        forwarded?.tabBarController?(tabBarController, sidebarVisibilityWillChange: sidebar, animator: animator)
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (forwarded?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let forwarded, forwarded.responds(to: aSelector) {
            return forwarded
        }
        return super.forwardingTarget(for: aSelector)
    }
}

/// The sidebar as `AppShellCoordinator` drives it for «Развернуть» / «Свернуть»; a fake in
/// unit tests, `IPadSidebarLiveControl` in the app.
@MainActor
protocol IPadSidebarControlling: AnyObject {
    var isSidebarShown: Bool { get }
    var sidebarOverlaysContent: Bool { get }
    func setSidebarHidden(_ hidden: Bool)
}

/// `IPadSidebarControl` behind `IPadSidebarControlling`, set by `AppContainer`.
@available(iOS 26.2, *)
@MainActor
final class IPadSidebarLiveControl: IPadSidebarControlling {
    var isSidebarShown: Bool { IPadSidebarControl.isSidebarShown }
    var sidebarOverlaysContent: Bool { IPadSidebarControl.sidebarOverlaysContent }
    func setSidebarHidden(_ hidden: Bool) { IPadSidebarControl.setSidebarHidden(hidden) }
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

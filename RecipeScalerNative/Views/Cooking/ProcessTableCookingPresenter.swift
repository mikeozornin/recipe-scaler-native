import SwiftUI
import UIKit

/// Host used by layout tests and as the SwiftUI child of the cooking container.
/// Landscape-only while cooking is visible (FR-007 lock until Close).
final class ProcessTableCookingHostingController: UIHostingController<ProcessTableCookingView> {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.isOpaque = true
        // Empty options = fill the parent. Default intrinsic size is the
        // navigation bar (~56pt), which left the recipe card visible.
        sizingOptions = []
        // Cooking applies its own leading/trailing pads. Keep container safe
        // area out of SwiftUI so Close can sit under the Dynamic Island.
        safeAreaRegions = []
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        ProcessTableCookingPresenter.cookingOrientations
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        .landscapeLeft
    }

    override var shouldAutorotate: Bool { true }
}

/// Plain UIKit parent so the window/presented surface is not a UIHostingController.
/// Hosting controllers used as window roots collapse to intrinsic nav-bar height.
final class ProcessTableCookingContainerController: UIViewController {
    let host: ProcessTableCookingHostingController

    init(rootView: ProcessTableCookingView) {
        self.host = ProcessTableCookingHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
        modalPresentationCapturesStatusBarAppearance = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.isOpaque = true
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = true
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.frame = view.bounds
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let window = view.window, view.frame != window.bounds {
            view.frame = window.bounds
        }
        host.view.frame = view.bounds
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        ProcessTableCookingPresenter.cookingOrientations
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        .landscapeLeft
    }

    override var shouldAutorotate: Bool { true }
}

/// Overlay window that refuses to shrink to the hosting controller's intrinsic size.
final class ProcessTableCookingOverlayWindow: UIWindow {
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let windowScene else { return }
        let bounds = windowScene.coordinateSpace.bounds
        if frame != bounds {
            frame = bounds
        }
        rootViewController?.view.frame = bounds
    }
}

struct ProcessTableCookingCoverItem: Identifiable {
    let id = UUID()
    let content: ProcessTableCookingView
}

extension Notification.Name {
    static let processTableCookingCoverChanged = Notification.Name("processTableCookingCoverChanged")
}

@MainActor
@Observable
final class ProcessTableCookingCoverModel {
    static let shared = ProcessTableCookingCoverModel()
    var item: ProcessTableCookingCoverItem?
}

struct ProcessTableCookingRoot<Shell: View>: View {
    @Bindable var cover: ProcessTableCookingCoverModel
    @ViewBuilder var shell: () -> Shell

    var body: some View {
        // Same hosting controller as the recipe shell. A nested
        // UIHostingController (present / window pin) froze simctl on the
        // Instructions framebuffer even when cooking's onAppear fired.
        if let item = cover.item {
            item.content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
        } else {
            shell()
        }
    }
}

/// Hides leftover UIKit chrome (tab bar, nav, recipe host) that keeps painting
/// after SwiftUI swaps the recipe shell for cooking.
private struct ProcessTableCookingChromeHiderProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> ProcessTableCookingChromeHiderView {
        ProcessTableCookingChromeHiderView()
    }

    func updateUIView(_ uiView: ProcessTableCookingChromeHiderView, context: Context) {
        uiView.hideOffPath()
    }
}

final class ProcessTableCookingChromeHiderView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        hideOffPath()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        hideOffPath()
    }

    func hideOffPath() {
        var current: UIView = self
        while let parent = current.superview {
            for subview in parent.subviews where subview !== current {
                if shouldHideLeftover(subview) {
                    subview.isHidden = true
                    subview.alpha = 0
                }
            }
            if let window = parent as? UIWindow, current.frame != window.bounds {
                current.frame = window.bounds
            }
            current = parent
        }
    }

    private func shouldHideLeftover(_ view: UIView) -> Bool {
        if view is UITabBar || view is UINavigationBar || view is UIToolbar {
            return true
        }
        let name = String(describing: type(of: view))
        if name.contains("TabBar") || name.contains("NavigationBar") {
            return true
        }
        if name.contains("Hosting") {
            var ancestor: UIView? = self
            while let node = ancestor {
                if node === view { return false }
                ancestor = node.superview
            }
            return true
        }
        return false
    }
}
private struct ProcessTableWindowFillProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> ProcessTableWindowFillView {
        ProcessTableWindowFillView()
    }

    func updateUIView(_ uiView: ProcessTableWindowFillView, context: Context) {
        uiView.fillWindow()
    }
}

final class ProcessTableWindowFillView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        fillWindow()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        fillWindow()
    }

    func fillWindow() {
        guard let window else { return }
        var view: UIView = self
        while let superview = view.superview, superview !== window {
            view = superview
        }
        if view.frame != window.bounds {
            view.frame = window.bounds
        }
        if let root = window.rootViewController, root.view.frame != window.bounds {
            root.view.frame = window.bounds
        }
        window.rootViewController?.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }
}

/// Cooking is a dedicated overlay window whose root is a plain UIViewController.
/// SwiftUI `fullScreenCover` / UIHostingController-as-root both collapsed to ~56pt
/// (nav bar intrinsic size), so simctl kept capturing the recipe card underneath.
@MainActor
enum ProcessTableCookingPresenter {
    static var cookingOrientations: UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .phone
            ? [.landscapeLeft, .landscapeRight]
            : .all
    }

    private static var sessionActive = false
    private static var cookingRoot: ProcessTableCookingContainerController?
    private static weak var originalRoot: UIViewController?
    private static var hiddenWindowSubviews: [UIView] = []
    private static var hiddenForeignWindows: [UIWindow] = []

    static func supportedInterfaceOrientations(for window: UIWindow?) -> UIInterfaceOrientationMask {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return .all }
        if sessionActive {
            return cookingOrientations
        }
        return .portrait
    }

    static func beginLandscapeSession(requestGeometry: Bool = true) {
        sessionActive = true
        guard requestGeometry else { return }
        requestLandscape()
    }

    static func reassertLandscape() {
        guard sessionActive, UIDevice.current.userInterfaceIdiom == .phone else { return }
        requestLandscape()
    }

    static func presentOverlay(_ view: ProcessTableCookingView) {
        unpinCookingFromKeyWindow()
        restoreOriginalRootIfNeeded()
        ProcessTableCookingCoverModel.shared.item = ProcessTableCookingCoverItem(content: view)
        NotificationCenter.default.post(name: .processTableCookingCoverChanged, object: nil)
    }

    /// Child-VC overlay on the host's view. `present()` froze the compositor;
    /// adding the child's view to the window (not the parent's view) crashed
    /// to SpringBoard.
    private static func pinCookingToKeyWindow(_ view: ProcessTableCookingView) {
        guard let root = keyWindow()?.rootViewController else {
            return
        }
        if cookingRoot != nil {
            unpinCookingFromKeyWindow()
        }
        var host = root
        while let presented = host.presentedViewController {
            host = presented
        }
        let cooking = ProcessTableCookingContainerController(rootView: view)
        _ = cooking.view
        cooking.view.frame = host.view.bounds
        cooking.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cooking.view.isOpaque = true
        cooking.view.backgroundColor = .systemBackground
        cooking.view.layer.zPosition = 10_000
        cooking.view.isHidden = false
        cooking.view.alpha = 1
        host.addChild(cooking)
        host.view.addSubview(cooking.view)
        cooking.didMove(toParent: host)
        cookingRoot = cooking
        host.view.bringSubviewToFront(cooking.view)
        cooking.view.layoutIfNeeded()
    }

    private static func unpinCookingFromKeyWindow() {
        for subview in hiddenWindowSubviews {
            subview.isHidden = false
        }
        hiddenWindowSubviews.removeAll()
        for window in hiddenForeignWindows {
            window.isHidden = false
        }
        hiddenForeignWindows.removeAll()
        if let cooking = cookingRoot {
            cooking.willMove(toParent: nil)
            cooking.view.removeFromSuperview()
            cooking.removeFromParent()
        }
        cookingRoot = nil
    }

    static func hideLeftoverChrome() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for window in scenes.flatMap(\.windows) {
            hideChrome(in: window)
        }
    }

    @discardableResult
    private static func hideChrome(in view: UIView) -> Int {
        var hidden = 0
        if view is UITabBar || view is UINavigationBar || view is UIToolbar {
            view.isHidden = true
            view.alpha = 0
            hidden += 1
        }
        for subview in view.subviews {
            hidden += hideChrome(in: subview)
        }
        return hidden
    }

    private static func restoreOriginalRootIfNeeded() {
        guard let window = keyWindow(), let originalRoot else { return }
        if window.rootViewController !== originalRoot {
            window.rootViewController = originalRoot
        }
        self.originalRoot = nil
        cookingRoot = nil
    }

    private static func installCookingAsWindowRoot(_ view: ProcessTableCookingView) {
        guard let window = keyWindow() else { return }
        if originalRoot == nil {
            originalRoot = window.rootViewController
        }
        let cooking = ProcessTableCookingContainerController(rootView: view)
        _ = cooking.view
        cooking.view.frame = window.bounds
        cooking.view.backgroundColor = .systemBackground
        cookingRoot = cooking
        window.rootViewController = cooking
        for delay in [0.05, 0.15, 0.3, 0.6, 1.0] as [TimeInterval] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let cookingRoot, let window = keyWindow() else { return }
                if window.rootViewController !== cookingRoot {
                    window.rootViewController = cookingRoot
                }
                cookingRoot.view.frame = window.bounds
            }
        }
    }

    static func dismissOverlay(restoreOrientation: Bool = true) {
        ProcessTableCookingCoverModel.shared.item = nil
        NotificationCenter.default.post(name: .processTableCookingCoverChanged, object: nil)
        if let presenter = keyWindow()?.rootViewController, presenter.presentedViewController != nil {
            presenter.dismiss(animated: false)
        }
        unpinCookingFromKeyWindow()
        restoreOriginalRootIfNeeded()
        if restoreOrientation {
            unlockOrientation()
        } else {
            sessionActive = false
        }
    }

    static func unlockOrientation(from viewController: UIViewController? = nil) {
        sessionActive = false
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        guard let scene = scene(for: viewController) else { return }
        invalidateSupportedOrientations(in: scene)
        let prefs = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .portrait)
        scene.requestGeometryUpdate(prefs) { _ in }
    }

    private static func requestLandscape() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        guard let scene = scene(for: nil) else { return }
        // UIKit caches `supportedInterfaceOrientations`; without invalidation the
        // request fails with "Supported: portrait" even though the session flag
        // already allows landscape.
        invalidateSupportedOrientations(in: scene)
        let prefs = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .landscape)
        DispatchQueue.main.async {
            scene.requestGeometryUpdate(prefs) { error in
                AppLog.debug(.ui, "process table geometry update failed: \(error.localizedDescription)")
            }
        }
    }

    private static func invalidateSupportedOrientations(in scene: UIWindowScene) {
        for window in scene.windows {
            var controller = window.rootViewController
            while let current = controller {
                current.setNeedsUpdateOfSupportedInterfaceOrientations()
                controller = current.presentedViewController
            }
        }
    }

    private static func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        let appWindows = windows.filter {
            $0.windowLevel == .normal
                && $0.rootViewController != nil
                && $0.bounds.width >= 320
                && $0.bounds.height >= 500
        }
        return appWindows.first(where: \.isKeyWindow)
            ?? appWindows.max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height })
            ?? windows.first(where: { $0.isKeyWindow && $0.windowLevel == .normal })
            ?? windows.first(where: { $0.windowLevel == .normal })
            ?? windows.first(where: \.isKeyWindow)
            ?? windows.first
    }

    private static func scene(for viewController: UIViewController?) -> UIWindowScene? {
        viewController?.view.window?.windowScene
            ?? keyWindow()?.windowScene
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }
}

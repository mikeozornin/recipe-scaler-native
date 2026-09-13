import SwiftUI
import UIKit

/// Host used by layout tests. Landscape-only while cooking is visible (FR-007).
final class ProcessTableCookingHostingController: UIHostingController<ProcessTableCookingView> {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.isOpaque = true
        sizingOptions = []
        safeAreaRegions = []
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        ProcessTableCookingCoordinator.cookingOrientations
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        .landscapeLeft
    }

    override var shouldAutorotate: Bool { true }
}

struct ProcessTableCookingPresentation: Identifiable {
    let id = UUID()
    let recipe: RecipeData
    let scaleFactor: Double
    let allowsRebuild: Bool
    let restoreAwakeOnDismiss: Bool
    let session: ProcessTableCookingSession

    @MainActor
    init(
        recipe: RecipeData,
        scaleFactor: Double,
        allowsRebuild: Bool,
        restoreAwakeOnDismiss: Bool
    ) {
        self.recipe = recipe
        self.scaleFactor = scaleFactor
        self.allowsRebuild = allowsRebuild
        self.restoreAwakeOnDismiss = restoreAwakeOnDismiss
        self.session = ProcessTableCookingSession()
    }
}

/// App-level cooking cover + iPhone landscape lock. Owned by `AppContainer`.
@MainActor
@Observable
final class ProcessTableCookingCoordinator {
    var presentation: ProcessTableCookingPresentation?
    private(set) var sessionActive = false

    static var cookingOrientations: UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .phone
            ? [.landscapeLeft, .landscapeRight]
            : .all
    }

    func supportedInterfaceOrientations(for window: UIWindow?) -> UIInterfaceOrientationMask {
        _ = window
        guard UIDevice.current.userInterfaceIdiom == .phone else { return .all }
        if sessionActive {
            return Self.cookingOrientations
        }
        return .portrait
    }

    func present(
        recipe: RecipeData,
        scaleFactor: Double,
        allowsRebuild: Bool,
        restoreAwakeOnDismiss: Bool
    ) {
        presentation = ProcessTableCookingPresentation(
            recipe: recipe,
            scaleFactor: scaleFactor,
            allowsRebuild: allowsRebuild,
            restoreAwakeOnDismiss: restoreAwakeOnDismiss
        )
    }

    func beginLandscapeSession(requestGeometry: Bool = true) {
        sessionActive = true
        guard requestGeometry else { return }
        requestLandscape()
    }

    func reassertLandscape() {
        guard sessionActive, UIDevice.current.userInterfaceIdiom == .phone else { return }
        requestLandscape()
    }

    func dismiss(restoreOrientation: Bool = true) {
        presentation = nil
        if restoreOrientation {
            unlockOrientation()
        } else {
            sessionActive = false
        }
    }

    func dismissForLogout() {
        presentation = nil
        unlockOrientation()
    }

    func unlockOrientation(from viewController: UIViewController? = nil) {
        sessionActive = false
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        guard let scene = scene(for: viewController) else { return }
        invalidateSupportedOrientations(in: scene)
        let prefs = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .portrait)
        scene.requestGeometryUpdate(prefs) { _ in }
    }

    private func requestLandscape() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        guard let scene = scene(for: nil) else { return }
        invalidateSupportedOrientations(in: scene)
        let prefs = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .landscape)
        DispatchQueue.main.async { [weak self] in
            guard self?.sessionActive == true else { return }
            scene.requestGeometryUpdate(prefs) { error in
                AppLog.debug(.ui, "process table geometry update failed: \(error.localizedDescription)")
            }
        }
    }

    private func invalidateSupportedOrientations(in scene: UIWindowScene) {
        for window in scene.windows {
            var controller = window.rootViewController
            while let current = controller {
                current.setNeedsUpdateOfSupportedInterfaceOrientations()
                controller = current.presentedViewController
            }
        }
    }

    private func keyWindow() -> UIWindow? {
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

    private func scene(for viewController: UIViewController?) -> UIWindowScene? {
        viewController?.view.window?.windowScene
            ?? keyWindow()?.windowScene
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }
}

struct ProcessTableCookingRoot<Shell: View>: View {
    @Bindable var cooking: ProcessTableCookingCoordinator
    @Bindable var rebuildModel: ProcessTableRebuildModel
    @ViewBuilder var shell: () -> Shell

    var body: some View {
        ZStack {
            shell()
                .opacity(cooking.presentation == nil ? 1 : 0)
                .allowsHitTesting(cooking.presentation == nil)
                .accessibilityHidden(cooking.presentation != nil)

            if let presentation = cooking.presentation {
                ProcessTableCookingView(
                    recipe: presentation.recipe,
                    scaleFactor: presentation.scaleFactor,
                    allowsRebuild: presentation.allowsRebuild,
                    restoreAwakeOnDismiss: presentation.restoreAwakeOnDismiss,
                    session: presentation.session,
                    rebuildModel: rebuildModel
                )
            }
        }
    }
}

import SwiftUI
import UIKit

/// FR-007: iPhone cooking stays in system landscape until Close.
/// Portrait device tilt must not dismiss and must not relayout the matrix.
enum ProcessTableCookingOrientationAction: Equatable {
    case stay
    case reassertLandscape
}

struct ProcessTableCookingOrientationGate {
    /// Window size after a real rotate. Ignores presentation transients.
    static func interfaceOrientation(from size: CGSize) -> UIInterfaceOrientation? {
        guard size.width.isFinite, size.height.isFinite,
              size.width > 200, size.height > 200
        else { return nil }
        if size.width > size.height { return .landscapeLeft }
        if size.height > size.width { return .portrait }
        return nil
    }

    func apply(_ orientation: UIInterfaceOrientation) -> ProcessTableCookingOrientationAction {
        if orientation.isPortrait { return .reassertLandscape }
        return .stay
    }
}

/// Child VC so `viewWillTransition` fires on rotate. A 1×1 `UIView` probe does
/// not get `layoutSubviews` when only the window size changes, so cooking
/// stayed up and the matrix laid out in portrait (clipped).
struct ProcessTableInterfaceOrientationObserver: UIViewControllerRepresentable {
    var onChange: (UIInterfaceOrientation) -> Void

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.onChange = onChange
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.onChange = onChange
    }

    final class Controller: UIViewController {
        var onChange: (UIInterfaceOrientation) -> Void = { _ in }
        private var lastReported: UIInterfaceOrientation = .unknown
        private var orientationObserver: NSObjectProtocol?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
            view.isAccessibilityElement = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            if orientationObserver == nil {
                orientationObserver = NotificationCenter.default.addObserver(
                    forName: UIDevice.orientationDidChangeNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.report()
                }
            }
            report()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if let orientationObserver {
                NotificationCenter.default.removeObserver(orientationObserver)
                self.orientationObserver = nil
            }
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }

        override func viewWillTransition(
            to size: CGSize,
            with coordinator: UIViewControllerTransitionCoordinator
        ) {
            super.viewWillTransition(to: size, with: coordinator)
            coordinator.animate(alongsideTransition: { [weak self] _ in
                self?.report()
            }, completion: { [weak self] _ in
                self?.report()
            })
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            report()
        }

        private func report() {
            let scene = view.window?.windowScene?.effectiveGeometry.interfaceOrientation
            let size = ProcessTableCookingOrientationGate.interfaceOrientation(
                from: view.window?.bounds.size ?? .zero
            )
            let orientation: UIInterfaceOrientation
            if let scene, scene.isLandscape || scene.isPortrait {
                orientation = scene
            } else {
                orientation = size ?? .unknown
            }
            guard orientation != .unknown, orientation != lastReported else { return }
            lastReported = orientation
            onChange(orientation)
        }
    }
}

/// Puts `accessibilityIdentifier` on a real `UIView` so XCTest tree walks
/// find Close even when SwiftUI `glassEffect` does not copy the identifier.
struct ProcessTableAccessibilityIdentifierProbe: UIViewRepresentable {
    let id: String

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.accessibilityIdentifier = id
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        view.accessibilityIdentifier = id
    }
}

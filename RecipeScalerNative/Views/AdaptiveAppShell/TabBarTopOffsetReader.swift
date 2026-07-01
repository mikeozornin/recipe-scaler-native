//
//  TabBarTopOffsetReader.swift
//  RecipeScalerNative
//

import SwiftUI
import UIKit

struct TabBarTopOffsetReader: UIViewControllerRepresentable {
    @Binding var offsetFromLayoutBottom: CGFloat

    func makeUIViewController(context: Context) -> TabBarTopOffsetReaderViewController {
        let controller = TabBarTopOffsetReaderViewController()
        controller.onOffsetChange = { newValue in
            guard offsetFromLayoutBottom != newValue else { return }
            offsetFromLayoutBottom = newValue
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: TabBarTopOffsetReaderViewController, context: Context) {
        uiViewController.onOffsetChange = { newValue in
            guard offsetFromLayoutBottom != newValue else { return }
            offsetFromLayoutBottom = newValue
        }
        uiViewController.view.setNeedsLayout()
    }
}

/// Resolves the `UITabBarController` hosting a window's root view-controller
/// hierarchy. Caches the resolved controller and only re-runs the recursive
/// search when the cached reference is missing (controller deallocated) or its
/// `parent` has changed (modal presentation / reparenting), so a stable layout
/// does not walk the view-controller hierarchy on every `viewDidLayoutSubviews`.
///
/// `search` is injectable so tests can count traversals without polluting
/// production code with test hooks.
final class TabBarDiscovery {
    private weak var cached: UITabBarController?
    private var cachedParent: UIViewController?
    private let search: (UIViewController?) -> UITabBarController?

    init(search: @escaping (UIViewController?) -> UITabBarController? = TabBarDiscovery.find) {
        self.search = search
    }

    func resolve(root: UIViewController?) -> UITabBarController? {
        if let cached, cached.parent === cachedParent {
            return cached
        }
        let resolved = search(root)
        cached = resolved
        cachedParent = resolved?.parent
        return resolved
    }

    static func find(in viewController: UIViewController?) -> UITabBarController? {
        guard let viewController else { return nil }
        if let tabBarController = viewController as? UITabBarController {
            return tabBarController
        }
        for child in viewController.children {
            if let tabBarController = find(in: child) {
                return tabBarController
            }
        }
        if let presented = viewController.presentedViewController,
           let tabBarController = find(in: presented) {
            return tabBarController
        }
        return nil
    }
}

final class TabBarTopOffsetReaderViewController: UIViewController {
    var onOffsetChange: ((CGFloat) -> Void)?
    private let tabBarDiscovery = TabBarDiscovery()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        publishOffsetIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        publishOffsetIfNeeded()
    }

    private func publishOffsetIfNeeded() {
        guard let window = view.window,
              let tabBar = tabBarDiscovery.resolve(root: window.rootViewController)?.tabBar else { return }
        let tabBarFrame = tabBar.convert(tabBar.bounds, to: window)
        let offsetFromWindowBottom = window.bounds.height - tabBarFrame.minY
        let offsetFromLayoutBottom = offsetFromWindowBottom - window.safeAreaInsets.bottom
        guard offsetFromLayoutBottom > 0 else { return }
        onOffsetChange?(offsetFromLayoutBottom)
    }
}
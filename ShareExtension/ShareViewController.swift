//
//  ShareViewController.swift
//  ShareExtension
//
//  UIKit host that bridges NSExtensionContext → SwiftUI ShareView.
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers
import RecipeScalerCore

@objc(ShareViewController)
final class ShareViewController: UIViewController {

    private var hostingController: UIHostingController<ShareView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        // Build the SwiftUI view; capture the extension context for URL opening.
        let shareView = ShareView(extensionContext: extensionContext)
        let host = UIHostingController(rootView: shareView)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        hostingController = host
    }

    override func didSelectCancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: "ShareExtension", code: 0))
    }

    override func didSelectPost() {
        // No-op: submit happens from SwiftUI (`ShareView.submit()`).
        // Keeping the default SLComposeServiceViewController-style hook silenced.
    }
}

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
import ShareExtensionUI

@objc(ShareViewController)
final class ShareViewController: UIViewController {

    private var hostingController: UIHostingController<ShareView>?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        let shareView = ShareView(extensionContext: extensionContext, hostViewController: self)
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

}

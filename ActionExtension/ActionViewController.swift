//
//  ActionViewController.swift
//  ActionExtension
//
//  Hosts the same `ShareView` SwiftUI surface as the Share extension but is
//  activated only from Safari's context menu. The URL of the active page is
//  supplied via JavaScript preprocessing (GetURLFromPage.js).
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit
import RecipeScalerCore
import ShareExtensionUI

@objc(ActionViewController)
final class ActionViewController: UIViewController {

    private var hostingController: UIHostingController<ShareView>?
    private var discoveredURL: URL?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        extractURLFromInputItems()
        mountShareView()
    }

    // MARK: - URL extraction

    /// Pulls the URL preprocessed by `GetURLFromPage.js` (key:
    /// `NSExtensionJavaScriptPreprocessingResultsKey`) and also falls back to
    /// `public.url` attachments for non-Safari hosts that still match the activation rule.
    private func extractURLFromInputItems() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return }

        for item in items {
            // JavaScript preprocessing payload comes through the item's `userInfo`.
            if let userInfo = item.userInfo,
               let preprocessed = userInfo[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any],
               let urlString = preprocessed["currentUrl"] as? String,
               let url = URL(string: urlString) {
                discoveredURL = url
                return
            }

            if let attachments = item.attachments {
                for provider in attachments where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    // Synchronous-looking helper; we'll re-load asynchronously and
                    // re-mount if the URL arrives after initial render.
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] result, _ in
                        guard let self else { return }
                        if let url = result as? URL {
                            DispatchQueue.main.async {
                                self.discoveredURL = url
                                self.mountShareView()
                            }
                        } else if let string = result as? String, let url = URL(string: string) {
                            DispatchQueue.main.async {
                                self.discoveredURL = url
                                self.mountShareView()
                            }
                        }
                    }
                    return
                }
            }
        }
    }

    // MARK: - UI

    private func mountShareView() {
        // Tear down previous host (re-mount after URL discovery).
        if let existing = hostingController {
            existing.willMove(toParent: nil)
            existing.view.removeFromSuperview()
            existing.removeFromParent()
            hostingController = nil
        }

        let initialContent: ShareContent = {
            if let url = discoveredURL {
                return .urls([url])
            }
            return .empty
        }()

        // Inject discovered URL via constructor; ShareView dispatches via ShareContentLoader.
        // The loader still runs but we feed the URL through `extensionContext` so the
        // standard URL-loading path picks it up from `attachments` too.
        let shareView = ShareView(extensionContext: extensionContext, preloaded: initialContent)
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

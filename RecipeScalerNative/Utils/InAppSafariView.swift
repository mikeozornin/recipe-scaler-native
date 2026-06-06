//
//  InAppSafariView.swift
//  RecipeScalerNative
//
//  SwiftUI wrapper for SFSafariViewController — opens an in-app browser sheet
//  for external/marketing pages (e.g. About) without leaving the app.
//

import SafariServices
import SwiftUI

struct InAppSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        configuration.barCollapsingEnabled = true
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.preferredControlTintColor = nil
        controller.dismissButtonStyle = .done
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

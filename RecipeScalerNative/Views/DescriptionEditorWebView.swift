//
//  DescriptionEditorWebView.swift
//  RecipeScalerNative
//

import SwiftUI
import WebKit

struct DescriptionEditorWebView: UIViewRepresentable {
    @ObservedObject var bridge: DescriptionEditorBridge

    func makeCoordinator() -> Coordinator {
        Coordinator(bridge: bridge)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: Coordinator.handlerName)
        config.userContentController = controller
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.keyboardDismissMode = .interactive

        context.coordinator.webView = webView
        bridge.attach(webView: context.coordinator)
        context.coordinator.loadEditor(in: webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.handlerName)
        coordinator.bridge.detach(webView: coordinator)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let handlerName = "descriptionEditor"

        let bridge: DescriptionEditorBridge
        weak var webView: WKWebView?

        init(bridge: DescriptionEditorBridge) {
            self.bridge = bridge
        }

        func loadEditor(in webView: WKWebView) {
            guard let htmlURL = Bundle.main.url(forResource: "description-editor", withExtension: "html") else {
                bridge.reportLoadFailure("Missing description-editor.html in app bundle")
                return
            }
            let readAccessURL = htmlURL.deletingLastPathComponent()
            webView.loadFileURL(htmlURL, allowingReadAccessTo: readAccessURL)
        }

        func sendInit(state: Data) {
            let payload: [String: Any] = [
                "type": "init",
                "state": state.map { NSNumber(value: $0) },
            ]
            sendToJS(payload)
        }

        func sendApplyUpdate(_ update: Data) {
            let payload: [String: Any] = [
                "type": "applyUpdate",
                "update": update.map { NSNumber(value: $0) },
            ]
            sendToJS(payload)
        }

        private func sendToJS(_ payload: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8) else { return }
            let script = "window.__descriptionEditorReceive(\(json));"
            webView?.evaluateJavaScript(script)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.handlerName else { return }
            bridge.handleWebMessage(message.body)
        }
    }
}
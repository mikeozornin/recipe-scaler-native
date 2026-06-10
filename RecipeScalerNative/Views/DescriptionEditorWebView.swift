//
//  DescriptionEditorWebView.swift
//  RecipeScalerNative
//

import SwiftUI
import WebKit

struct DescriptionEditorWebView: UIViewRepresentable {
    @ObservedObject var bridge: DescriptionEditorBridge
    var allowsScrolling: Bool
    var accentColor: Color = .purple

    init(bridge: DescriptionEditorBridge, allowsScrolling: Bool, accentColor: Color = .purple) {
        self.bridge = bridge
        self.allowsScrolling = allowsScrolling
        self.accentColor = accentColor
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(bridge: bridge, accentColor: accentColor)
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
        applyScrollPolicy(on: webView, allowsScrolling: allowsScrolling)

        context.coordinator.webView = webView
        bridge.attach(webView: context.coordinator)
        context.coordinator.loadEditor(in: webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        applyScrollPolicy(on: uiView, allowsScrolling: allowsScrolling)
    }

    private func applyScrollPolicy(on webView: WKWebView, allowsScrolling: Bool) {
        let scrollView = webView.scrollView
        scrollView.isScrollEnabled = allowsScrolling
        scrollView.bounces = allowsScrolling
        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.handlerName)
        coordinator.bridge.detach(webView: coordinator)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let handlerName = "descriptionEditor"

        let bridge: DescriptionEditorBridge
        weak var webView: WKWebView?
        private let accentColor: Color

        init(bridge: DescriptionEditorBridge, accentColor: Color) {
            self.bridge = bridge
            self.accentColor = accentColor
        }

        func loadEditor(in webView: WKWebView) {
            guard let htmlURL = Bundle.main.url(forResource: "description-editor", withExtension: "html") else {
                bridge.reportLoadFailure("Missing description-editor.html in app bundle")
                return
            }
            webView.loadFileURL(htmlURL, allowingReadAccessTo: Bundle.main.bundleURL)
        }

        func sendConfigure(presentation: DescriptionEditorPresentation) {
            let lineHeight = RecipeDescriptionStyle.bodyFontSize + RecipeDescriptionStyle.bodyLineSpacing
            var payload: [String: Any] = [
                "type": "configure",
                "inline": presentation == .inline,
                "fontSize": RecipeDescriptionStyle.bodyFontSize,
                "lineHeight": lineHeight,
                "fontFamily": AppFonts.sans,
            ]
            if let regular = Bundle.main.url(forResource: "MartianGrotesk-NrLt", withExtension: "otf") {
                payload["fontRegularURL"] = regular.absoluteString
            }
            if let medium = Bundle.main.url(forResource: "MartianGrotesk-NrMd", withExtension: "otf") {
                payload["fontMediumURL"] = medium.absoluteString
            }
            // Pass recipe accent color as hex for CSS variables
            let accentUIColor = UIColor(accentColor)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            if accentUIColor.getRed(&r, green: &g, blue: &b, alpha: &a) {
                let hex = String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
                payload["recipeColor"] = hex
            }
            // Pass link color matching view mode
            payload["linkColor"] = "#0072F5"
            sendToJS(payload)
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

        func sendCommand(name: String, args: [String: Any]?) {
            var payload: [String: Any] = [
                "type": "command",
                "name": name,
            ]
            if let args, !args.isEmpty {
                payload["args"] = args
            }
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

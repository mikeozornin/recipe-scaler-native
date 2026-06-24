//
//  DescriptionEditorWebView.swift
//  RecipeScalerNative
//

import SwiftUI
import UIKit
import WebKit

final class DescriptionEditorWKWebView: WKWebView {
    var customInputAccessoryView: UIView?

    override var inputAccessoryView: UIView? {
        customInputAccessoryView
    }
}

struct DescriptionEditorWebView: UIViewRepresentable {
    @Bindable var bridge: DescriptionEditorBridge
    var allowsScrolling: Bool
    var accentColor: Color = .purple
    var onKeyboardDone: (() -> Void)?

    init(
        bridge: DescriptionEditorBridge,
        allowsScrolling: Bool,
        accentColor: Color = .purple,
        onKeyboardDone: (() -> Void)? = nil
    ) {
        self.bridge = bridge
        self.allowsScrolling = allowsScrolling
        self.accentColor = accentColor
        self.onKeyboardDone = onKeyboardDone
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(bridge: bridge, accentColor: accentColor, onKeyboardDone: onKeyboardDone)
    }

    func makeUIView(context: Context) -> DescriptionEditorWKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: Coordinator.handlerName)
        config.userContentController = controller
        config.preferences.setValue(false, forKey: "allowFileAccessFromFileURLs")

        let webView = DescriptionEditorWKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.keyboardDismissMode = .interactive
        applyScrollPolicy(on: webView, allowsScrolling: allowsScrolling)

        context.coordinator.webView = webView
        bridge.attach(webView: context.coordinator)
        applyInlineKeyboardAccessory(on: webView, context: context)
        context.coordinator.loadEditor(in: webView)
        return webView
    }

    func updateUIView(_ uiView: DescriptionEditorWKWebView, context: Context) {
        context.coordinator.onKeyboardDone = onKeyboardDone
        applyScrollPolicy(on: uiView, allowsScrolling: allowsScrolling)
        applyInlineKeyboardAccessory(on: uiView, context: context)
    }

    /// Inline editor: Done on `DescriptionFormattingBar`; full-screen keeps UIKit accessory.
    private func applyInlineKeyboardAccessory(on webView: DescriptionEditorWKWebView, context: Context) {
        let nextAccessory: UIView? = bridge.presentation == .inline
            ? nil
            : context.coordinator.makeKeyboardToolbar()
        guard webView.customInputAccessoryView !== nextAccessory else { return }
        webView.customInputAccessoryView = nextAccessory
        webView.reloadInputViews()
    }

    private func applyScrollPolicy(on webView: DescriptionEditorWKWebView, allowsScrolling: Bool) {
        let scrollView = webView.scrollView
        scrollView.isScrollEnabled = allowsScrolling
        scrollView.bounces = allowsScrolling
        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
    }

    static func dismantleUIView(_ uiView: DescriptionEditorWKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.handlerName)
        coordinator.bridge.detach(webView: coordinator)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let handlerName = "descriptionEditor"

        let bridge: DescriptionEditorBridge
        weak var webView: WKWebView?
        private let accentColor: Color
        var onKeyboardDone: (() -> Void)?

        init(bridge: DescriptionEditorBridge, accentColor: Color, onKeyboardDone: (() -> Void)?) {
            self.bridge = bridge
            self.accentColor = accentColor
            self.onKeyboardDone = onKeyboardDone
        }

        func loadEditor(in webView: WKWebView) {
            guard let htmlURL = Bundle.main.url(forResource: "description-editor", withExtension: "html") else {
                bridge.reportLoadFailure("Missing description-editor.html in app bundle")
                return
            }
            webView.loadFileURL(htmlURL, allowingReadAccessTo: Bundle.main.bundleURL)
        }

        func sendConfigure(presentation: DescriptionEditorPresentation) {
            let lineHeight = RecipeDescriptionStyle.bodyFontSize * RecipeDescriptionStyle.lineHeightMultiple
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

        func sendSetScale(scaleFactor: Double, ingredients: [[String: Any]], locale: String) {
            let payload: [String: Any] = [
                "type": "setScale",
                "scaleFactor": scaleFactor,
                "ingredients": ingredients,
                "locale": locale,
            ]
            sendToJS(payload)
        }

        #if DEBUG
        func sendSimulateText(_ text: String) {
            sendToJS(["type": "simulateText", "text": text])
        }
        #endif

        func resignEditingKeyboard() {
            webView?.resignFirstResponder()
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

        func makeKeyboardToolbar() -> UIToolbar {
            let toolbar = UIToolbar()
            toolbar.sizeToFit()
            let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
            let done = UIBarButtonItem(
                title: Bundle.currentLocalizedString("edit.done"),
                style: AppChromeAppearance.doneBarButtonItemStyle,
                target: self,
                action: #selector(keyboardDoneTapped)
            )
            done.accessibilityIdentifier = AccessibilityIdentifiers.descriptionEditorKeyboardDone
            toolbar.items = [spacer, done]
            return toolbar
        }

        @objc func keyboardDoneTapped() {
            if let onKeyboardDone {
                onKeyboardDone()
            } else {
                bridge.dismissEditingFocus()
            }
        }
    }
}

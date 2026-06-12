import Foundation
import WebKit

enum YjsMergeHelperError: Error {
    case notReady
    case invalidResult
}

/// Runs `Y.mergeUpdates` / `Y.encodeStateAsUpdate` via bundled yjs (web parity).
@MainActor
final class YjsMergeHelper: NSObject {
    static let shared = YjsMergeHelper()

    private var webView: WKWebView?
    private var ready = false
    private var loadContinuations: [CheckedContinuation<Void, Never>] = []

    private override init() {
        super.init()
    }

    func mergeUpdates(_ parts: [Data]) async throws -> Data {
        guard !parts.isEmpty else { return Data() }
        if parts.count == 1 { return parts[0] }
        try await ensureReady()
        let arrays = parts.map { $0.map { NSNumber(value: $0) } }
        let script = "window.__yjsMerge.mergeUpdates(\(Self.jsonArray(arrays)))"
        return try await evaluateByteArray(script: script)
    }

    func encodeFullState(bootstrap: Data?, updates: [Data]) async throws -> Data {
        try await ensureReady()
        let bootstrapArray = bootstrap?.map { NSNumber(value: $0) } ?? []
        let updateArrays = updates.map { $0.map { NSNumber(value: $0) } }
        let script =
            "window.__yjsMerge.encodeFullState(\(Self.jsonArray(bootstrapArray)), \(Self.jsonArray(updateArrays)))"
        return try await evaluateByteArray(script: script)
    }

    private func ensureReady() async throws {
        if ready { return }
        if webView == nil {
            let config = WKWebViewConfiguration()
            config.preferences.setValue(false, forKey: "allowFileAccessFromFileURLs")
            let view = WKWebView(frame: .zero, configuration: config)
            view.navigationDelegate = self
            view.isHidden = true
            webView = view
            guard let htmlURL = Bundle.main.url(forResource: "yjs-merge-helper", withExtension: "html") else {
                throw YjsMergeHelperError.notReady
            }
            view.loadFileURL(htmlURL, allowingReadAccessTo: Bundle.main.bundleURL)
        }
        if ready { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            loadContinuations.append(continuation)
        }
        if !ready { throw YjsMergeHelperError.notReady }
    }

    private func evaluateByteArray(script: String) async throws -> Data {
        guard let webView else { throw YjsMergeHelperError.notReady }
        let value = try await webView.evaluateJavaScript(script)
        guard let numbers = value as? [NSNumber], !numbers.isEmpty else {
            throw YjsMergeHelperError.invalidResult
        }
        return Data(numbers.map { UInt8(truncating: $0) })
    }

    private static func jsonArray(_ arrays: [[NSNumber]]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: arrays),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    private static func jsonArray(_ numbers: [NSNumber]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: numbers),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    private func markReady() {
        guard !ready else { return }
        ready = true
        let waiters = loadContinuations
        loadContinuations.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

extension YjsMergeHelper: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("window.__yjsMergeReady === true") { [weak self] value, _ in
            Task { @MainActor in
                if (value as? Bool) == true {
                    self?.markReady()
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let waiters = loadContinuations
        loadContinuations.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

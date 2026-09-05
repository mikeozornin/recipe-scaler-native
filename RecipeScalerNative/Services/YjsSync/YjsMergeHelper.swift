import Foundation
import WebKit

enum YjsMergeHelperError: Error {
    case notReady
    case invalidResult
}

/// Runs `Y.mergeUpdates` / `Y.encodeStateAsUpdate` via bundled yjs (web parity).
@MainActor
final class YjsMergeHelper: NSObject {
    /// Shim: returns `AppContainer.shared.yjsMergeHelper` when the container
    /// is constructed, otherwise a stand-alone instance.
    static var shared: YjsMergeHelper {
        if let container = AppContainer.shared {
            return container.yjsMergeHelper
        }
        return Standalone
    }

    private static let Standalone = YjsMergeHelper()

    private var webView: WKWebView?
    private var ready = false

    /// A parked `ensureReady()` waiter plus its last-resort timeout task.
    /// Per-waiter ownership matters: a stale timeout must not reset a fresh
    /// retry started by a different caller, so `resume` cancels its own task.
    private final class LoadWaiter {
        let continuation: CheckedContinuation<Bool, Never>
        var timeoutTask: Task<Void, Never>?

        init(continuation: CheckedContinuation<Bool, Never>) {
            self.continuation = continuation
        }

        func resume(returning value: Bool) {
            timeoutTask?.cancel()
            timeoutTask = nil
            continuation.resume(returning: value)
        }
    }

    private var loadWaiters: [LoadWaiter] = []

    /// Upper bound for the bundled HTML load + bootstrap. Local file loads are
    /// fast; anything longer means the WebContent process is wedged/killed.
    private static let loadTimeoutSeconds: TimeInterval = 10

    override init() {
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
        // Bounded wait (review 2026.09.04 №2): a single failed load (network-less
        // bundle, WebContent process killed by the OS) must not park `ensureReady()`
        // forever — callers like `drainOfflineQueue` hold the offline pipeline while
        // waiting. Navigation callbacks resume waiters with the outcome; the per-waiter
        // timeout is the last-resort unblock. `webView` is reset on every failure path
        // so the next call retries with a fresh view instead of a dead instance.
        let loadSucceeded: Bool = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                let waiter = LoadWaiter(continuation: continuation)
                loadWaiters.append(waiter)
                waiter.timeoutTask = Task { [weak self, weak waiter] in
                    try? await Task.sleep(nanoseconds: UInt64(Self.loadTimeoutSeconds * 1_000_000_000))
                    guard !Task.isCancelled, let self, let waiter else { return }
                    // Timed out and still parked: unblock this waiter and
                    // drop the wedged web view so the next call retries.
                    guard self.loadWaiters.contains(where: { $0 === waiter }) else { return }
                    AppLog.notice(.sync, "yjs_merge_helper_load_timeout", data: [
                        "timeoutSeconds": "\(Self.loadTimeoutSeconds)"
                    ])
                    self.loadWaiters.removeAll { $0 === waiter }
                    self.resetWebView()
                    waiter.resume(returning: false)
                    // Other waiters parked on the same dead view fail too.
                    self.resumeWaiters(success: false)
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.resumeWaiters(success: false)
            }
        }
        if !loadSucceeded || !ready {
            throw YjsMergeHelperError.notReady
        }
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
        resumeWaiters(success: true)
    }

    /// Resumes all parked waiters. `success == false` keeps `ready` unset so
    /// `ensureReady()` throws `notReady` after resumption.
    private func resumeWaiters(success: Bool) {
        let waiters = loadWaiters
        loadWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: success)
        }
    }

    /// Drops the failed/killed web view so the next `ensureReady()` call
    /// reloads from scratch instead of hanging on a dead instance.
    private func resetWebView() {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
    }
}

extension YjsMergeHelper: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("window.__yjsMergeReady === true") { [weak self] value, _ in
            Task { @MainActor in
                if (value as? Bool) == true {
                    self?.markReady()
                } else {
                    // HTML loaded but the merge bootstrap never became ready
                    // (broken bundle). Report failure so waiters don't park.
                    self?.resetWebView()
                    self?.resumeWaiters(success: false)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        // Review 2026.09.04 №2: a failed load must reset the view (retry on
        // next call) and unblock waiters with an error, not park them forever.
        resetWebView()
        resumeWaiters(success: false)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // WebContent process killed (memory pressure) — same reset path.
        ready = false
        resetWebView()
        resumeWaiters(success: false)
    }
}

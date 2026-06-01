import Foundation
import YrsC

private final class ObserverCallbackBox: @unchecked Sendable {
    let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }
}

/// RAII wrapper over `yobserve_deep` — unsubscribes via `yunobserve` in `deinit`.
final class YrsObserverToken {
    private let subscription: UnsafeMutablePointer<YSubscription>?
    private let retainedState: UnsafeMutableRawPointer

    init?(branch: UnsafeMutablePointer<Branch>, handler: @escaping () -> Void) {
        let box = ObserverCallbackBox(handler: handler)
        let state = Unmanaged.passRetained(box).toOpaque()

        let subscription = yobserve_deep(branch, state) { state, _, _ in
            guard let state else { return }
            let box = Unmanaged<ObserverCallbackBox>.fromOpaque(state).takeUnretainedValue()
            box.handler()
        }

        guard let subscription else {
            Unmanaged<ObserverCallbackBox>.fromOpaque(state).release()
            return nil
        }

        self.subscription = subscription
        self.retainedState = state
    }

    deinit {
        if let subscription {
            yunobserve(subscription)
        }
        Unmanaged<ObserverCallbackBox>.fromOpaque(retainedState).release()
    }
}

extension YrsDocument {
    /// Subscribe to deep changes on a root-level shared type (e.g. `recipes`, `recipe`).
    func addDeepObserver(rootKey: String, handler: @escaping @Sendable () -> Void) throws -> YrsObserverToken? {
        try withReadTransaction { _, txn in
            guard let branch = ytype_get(txn, rootKey) else { return nil }
            return YrsObserverToken(branch: branch, handler: handler)
        }
    }
}
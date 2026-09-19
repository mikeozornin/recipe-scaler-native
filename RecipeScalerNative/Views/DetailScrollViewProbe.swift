import SwiftUI
import UIKit

final class DetailScrollViewProbeBox {
    weak var host: UIScrollView?
}

struct DetailScrollViewProbe: UIViewRepresentable {
    let box: DetailScrollViewProbeBox

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.box = box
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.box = box
        uiView.discover()
    }

    final class ProbeView: UIView {
        weak var box: DetailScrollViewProbeBox?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            discover()
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            discover()
        }

        func discover() {
            var current: UIView? = superview
            while let view = current {
                if let scroll = view as? UIScrollView, !Self.isWebKitScroll(scroll) {
                    box?.host = scroll
                    return
                }
                current = view.superview
            }
            guard let window else { return }
            box?.host = Self.largestNonWebScroll(in: window)
        }

        private static func isWebKitScroll(_ scroll: UIScrollView) -> Bool {
            let name = NSStringFromClass(type(of: scroll))
            return name.contains("WK") || name.contains("Web")
        }

        private static func largestNonWebScroll(in root: UIView) -> UIScrollView? {
            var candidates: [UIScrollView] = []
            var stack = [root]
            while let view = stack.popLast() {
                stack.append(contentsOf: view.subviews)
                guard let scroll = view as? UIScrollView, !isWebKitScroll(scroll) else { continue }
                candidates.append(scroll)
            }
            let screenH = root.window?.bounds.height ?? root.bounds.height
            let nested = candidates.filter { $0.bounds.height < screenH - 40 }
            let pool = nested.isEmpty ? candidates : nested
            return pool.max(by: { $0.contentSize.height < $1.contentSize.height })
        }
    }
}

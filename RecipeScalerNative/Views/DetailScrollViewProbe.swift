import SwiftUI
import UIKit

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
            box?.host = nil
        }

        private static func isWebKitScroll(_ scroll: UIScrollView) -> Bool {
            let name = NSStringFromClass(type(of: scroll))
            return name.contains("WK") || name.contains("Web")
        }
    }
}

//
//  RecipeDescriptionInlineTextView.swift
//  RecipeScalerNative
//
//  UITextView read-only inline text — SwiftUI Text ignores link foregroundColor (shows black).
//

import SwiftUI
import UIKit

struct RecipeDescriptionInlineTextView: UIViewRepresentable {
    let runs: [RecipeDescriptionInlineRun]
    var accentColor: Color
    var onTimerTap: ((RecipeDescriptionTimerReference, CGRect) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onTimerTap: onTimerTap)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = RecipeDescriptionTextView()
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.isSelectable = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.dataDetectorTypes = []
        textView.adjustsFontForContentSizeCategory = true
        textView.linkTextAttributes = [
            .foregroundColor: RecipeDescriptionStyle.linkUIColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        textView.delegate = context.coordinator
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = true
        textView.addGestureRecognizer(tap)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.onTimerTap = onTimerTap
        context.coordinator.textView = textView
        let styled = Self.attributedString(runs: runs, accentColor: accentColor)
        if let descriptionTextView = textView as? RecipeDescriptionTextView {
            descriptionTextView.timerHighlightColor = UIColor(accentColor)
            descriptionTextView.attributedText = styled
            descriptionTextView.setNeedsLayout()
        } else {
            textView.attributedText = styled
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width - 32
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fitting.height)
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var onTimerTap: ((RecipeDescriptionTimerReference, CGRect) -> Void)?
        weak var textView: UITextView?

        init(onTimerTap: ((RecipeDescriptionTimerReference, CGRect) -> Void)?) {
            self.onTimerTap = onTimerTap
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended,
                  let textView = gesture.view as? UITextView
            else { return }

            let point = gesture.location(in: textView)
            let index = characterIndex(at: point, in: textView)
            guard index < textView.attributedText.length else { return }

            var range = NSRange()
            let attrs = textView.attributedText.attributes(at: index, effectiveRange: &range)
            if let url = attrs[.recipeTimerReference] as? URL,
               let reference = RecipeDescriptionTimerReference.from(link: url),
               let anchor = timerAnchorRect(for: range, in: textView) {
                onTimerTap?(reference, anchor)
                return
            }
            if let link = attrs[.link] as? URL {
                UIApplication.shared.open(link)
            }
        }

        private func timerAnchorRect(for characterRange: NSRange, in textView: UITextView) -> CGRect? {
            let layoutManager = textView.layoutManager
            let container = textView.textContainer
            let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return nil }

            guard let attributedText = textView.attributedText else { return nil }
            let origin = CGPoint(x: textView.textContainerInset.left, y: textView.textContainerInset.top)
            let rect = RecipeDescriptionStyle.timerHighlightRect(
                layoutManager: layoutManager,
                textContainer: container,
                characterRange: characterRange,
                attributedText: attributedText,
                contentOrigin: origin
            )
            return textView.convert(rect, to: nil)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let textView = gestureRecognizer.view as? UITextView else { return false }
            let point = touch.location(in: textView)
            let index = characterIndex(at: point, in: textView)
            guard index < textView.attributedText.length else { return false }
            guard let text = textView.attributedText else { return false }
            return text.attribute(.recipeTimerReference, at: index, effectiveRange: nil) != nil
                || text.attribute(.link, at: index, effectiveRange: nil) != nil
        }

        private func characterIndex(at point: CGPoint, in textView: UITextView) -> Int {
            let insetPoint = CGPoint(
                x: point.x - textView.textContainerInset.left,
                y: point.y - textView.textContainerInset.top
            )
            return textView.layoutManager.characterIndex(
                for: insetPoint,
                in: textView.textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil
            )
        }
    }

    static func attributedString(runs: [RecipeDescriptionInlineRun], accentColor: Color) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let bodyFont = RecipeDescriptionStyle.bodyFont()
        let accentUIColor = UIColor(accentColor)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = RecipeDescriptionStyle.bodyLineSpacing

        let base: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraph,
        ]

        for run in runs {
            switch run {
            case .plain(let value):
                result.append(NSAttributedString(string: value, attributes: base))
            case .strong(let value):
                var attrs = base
                attrs[.font] = RecipeDescriptionStyle.mediumFont()
                result.append(NSAttributedString(string: value, attributes: attrs))
            case .em(let value):
                var attrs = base
                if let italic = UIFont(name: AppFonts.sans, size: RecipeDescriptionStyle.bodyFontSize)?
                    .with(traits: .traitItalic) {
                    attrs[.font] = italic
                }
                result.append(NSAttributedString(string: value, attributes: attrs))
            case .link(let url, let text):
                var attrs = base
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                attrs[.foregroundColor] = RecipeDescriptionStyle.linkUIColor
                if let linkURL = URL(string: url), !url.isEmpty {
                    attrs[.link] = linkURL
                }
                result.append(NSAttributedString(string: text, attributes: attrs))
            case .timer(let reference):
                var attrs = base
                attrs[.foregroundColor] = accentUIColor
                if let payload = reference.linkURL() {
                    attrs[.recipeTimerReference] = payload
                }
                result.append(NSAttributedString(string: reference.displayText, attributes: attrs))
            case .ingredient(let value):
                var attrs = base
                attrs[.foregroundColor] = accentUIColor
                result.append(NSAttributedString(string: value, attributes: attrs))
            case .lineBreak:
                result.append(NSAttributedString(string: "\n", attributes: base))
            }
        }
        return result
    }
}

// MARK: - Rounded timer highlight (web padding + border-radius)

private final class RecipeDescriptionTextView: UITextView {
    var timerHighlightColor: UIColor = .label
    private var highlightLayers: [CALayer] = []

    /// UITextView draws glyphs in the first subview; layers must match that coordinate space.
    private var textLayoutCanvasView: UIView {
        subviews.first ?? self
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateTimerHighlights()
    }

    private func updateTimerHighlights() {
        highlightLayers.forEach { $0.removeFromSuperlayer() }
        highlightLayers.removeAll()

        guard let text = attributedText, text.length > 0 else { return }

        let layoutManager = self.layoutManager
        let container = self.textContainer
        layoutManager.ensureLayout(for: container)

        let origin = CGPoint(x: textContainerInset.left, y: textContainerInset.top)
        let fill = timerHighlightColor.withAlphaComponent(RecipeDescriptionStyle.TimerHighlight.backgroundAlpha)
        let radius = RecipeDescriptionStyle.TimerHighlight.cornerRadius
        let fullRange = NSRange(location: 0, length: text.length)

        text.enumerateAttribute(.recipeTimerReference, in: fullRange) { value, range, _ in
            guard value != nil else { return }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }

            var box = RecipeDescriptionStyle.timerHighlightRect(
                layoutManager: layoutManager,
                textContainer: container,
                characterRange: range,
                attributedText: text,
                contentOrigin: origin
            )
            let host = textLayoutCanvasView
            if host !== self {
                box = host.convert(box, from: self)
            }

            let layer = CAShapeLayer()
            layer.path = UIBezierPath(roundedRect: box, cornerRadius: radius).cgPath
            layer.fillColor = fill.cgColor
            host.layer.insertSublayer(layer, at: 0)
            self.highlightLayers.append(layer)
        }
    }
}

private extension UIFont {
    func with(traits: UIFontDescriptor.SymbolicTraits) -> UIFont? {
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return nil }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
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
    var typography: RecipeDescriptionBlockTypography = .body
    var onTimerTap: ((RecipeDescriptionTimerReference, CGRect) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onTimerTap: onTimerTap)
    }

    func makeUIView(context: Context) -> UITextView {
        // TextKit 1 from the start: the timer highlights and tap handling read `layoutManager`,
        // which switches a TextKit 2 view to TextKit 1 on its first layout anyway. Starting in
        // TextKit 1 skips the TextKit 2 setup, the first TextKit 2 measurement and the switch.
        let textView = RecipeDescriptionTextView()
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.isSelectable = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.dataDetectorTypes = []
        textView.adjustsFontForContentSizeCategory = false
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
        textView.textContainer.widthTracksTextView = true
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onTimerTap = onTimerTap
        coordinator.textView = textView
        // Parent re-renders (servings, timers, collection echo) pass the same content again;
        // rebuilding the attributed string and diffing it with the text view is wasted work.
        let content = ContentKey(runs: runs, accentColor: accentColor, typography: typography)
        guard coordinator.appliedContent != content else { return }
        coordinator.appliedContent = content
        let styled = Self.attributedString(runs: runs, accentColor: accentColor, typography: typography)
        let highlight = UIColor(accentColor)
        // Skip no-op writes — identical attributed text would still force UITextView layout.
        if let descriptionTextView = textView as? RecipeDescriptionTextView,
           descriptionTextView.timerHighlightColor != highlight {
            descriptionTextView.timerHighlightColor = highlight
        }
        if textView.attributedText?.isEqual(to: styled) != true {
            textView.attributedText = styled
            coordinator.measuredHeights.removeAll()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = Self.resolvedMeasureWidth(proposal: proposal, uiView: uiView)
        let containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        if uiView.textContainer.size != containerSize {
            uiView.textContainer.size = containerSize
        }
        // SwiftUI asks again after every update of the parent; the text only changes in
        // `updateUIView`, which drops these heights.
        let coordinator = context.coordinator
        let fittingHeight: CGFloat
        if let cached = coordinator.measuredHeights[width] {
            fittingHeight = cached
        } else {
            fittingHeight = ceil(uiView.sizeThatFits(containerSize).height)
            if coordinator.measuredHeights.count >= Coordinator.measuredHeightsLimit {
                coordinator.measuredHeights.removeAll()
            }
            coordinator.measuredHeights[width] = fittingHeight
        }
        let minHeight = typography.fontSize * RecipeDescriptionStyle.lineHeightMultiple
        return CGSize(width: width, height: max(fittingHeight, minHeight))
    }

    /// SwiftUI may call `sizeThatFits` with width `0` or `inf` before layout; measuring at
    /// those widths yields a single-line height (~24pt) and clips multi-line steps.
    private static func resolvedMeasureWidth(proposal: ProposedViewSize, uiView: UITextView) -> CGFloat {
        if let proposed = proposal.width, proposed.isFinite, proposed > 1 {
            return proposed
        }
        if uiView.bounds.width > 1 {
            return uiView.bounds.width
        }
        // StepsSection horizontal padding + ordered-step badge (22) + spacing (10).
        let screenWidth = UIScreen.main.bounds.width
        return max(220, screenWidth - 64 - 32)
    }

    /// Everything the attributed string is built from.
    struct ContentKey: Equatable {
        let runs: [RecipeDescriptionInlineRun]
        let accentColor: Color
        let typography: TypographyKey

        init(runs: [RecipeDescriptionInlineRun], accentColor: Color, typography: RecipeDescriptionBlockTypography) {
            self.runs = runs
            self.accentColor = accentColor
            self.typography = TypographyKey(typography)
        }
    }

    enum TypographyKey: Equatable {
        case body
        case heading(level: Int)

        init(_ typography: RecipeDescriptionBlockTypography) {
            switch typography {
            case .body: self = .body
            case .heading(let level): self = .heading(level: level)
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        static let measuredHeightsLimit = 8

        var onTimerTap: ((RecipeDescriptionTimerReference, CGRect) -> Void)?
        weak var textView: UITextView?
        /// Content of the attributed text the view shows now.
        var appliedContent: ContentKey?
        /// Fitting heights of the current attributed text, by measured width.
        var measuredHeights: [CGFloat: CGFloat] = [:]

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

    static func attributedString(runs: [RecipeDescriptionInlineRun], accentColor: Color, typography: RecipeDescriptionBlockTypography = .body) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let bodyFont = typography.baseFont
        let accentUIColor = UIColor(accentColor)
        let paragraph = NSMutableParagraphStyle()
        let targetLineHeight = typography.fontSize * RecipeDescriptionStyle.lineHeightMultiple
        // Add spacing only between lines (not before the first line) so the
        // first line's ascender stays at y=0 and the badge aligns correctly.
        paragraph.lineSpacing = max(0, targetLineHeight - bodyFont.lineHeight)

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
                attrs[.font] = typography.mediumFont
                result.append(NSAttributedString(string: value, attributes: attrs))
            case .em(let value):
                var attrs = base
                if let italic = typography.italicFont {
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
            case .ingredient(_, _, _, let value):
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
    var timerHighlightColor: UIColor = .label {
        didSet { highlightGeometry = nil }
    }
    private var highlightLayers: [CALayer] = []
    /// Inputs the current highlight layers were built from.
    private var highlightGeometry: HighlightGeometry?
    /// The text view does not retain the storage of a stack passed in through its container.
    private let ownedTextStorage: NSTextStorage

    /// A TextKit 1 text view. `UITextView(usingTextLayoutManager:)` is an Objective-C factory
    /// that skips Swift initializers on a subclass, leaving the stored properties above unset.
    init() {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(container)
        ownedTextStorage = storage
        super.init(frame: .zero, textContainer: container)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var attributedText: NSAttributedString! {
        didSet { highlightGeometry = nil }
    }

    /// UITextView draws glyphs in the first subview; layers must match that coordinate space.
    private var textLayoutCanvasView: UIView {
        subviews.first ?? self
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Layout runs on every SwiftUI layout pass. The highlight rects only depend on the text
        // (reset in `attributedText`), the color and the geometry below.
        let host = textLayoutCanvasView
        let geometry = HighlightGeometry(
            host: ObjectIdentifier(host),
            hostFrame: host.frame,
            bounds: bounds,
            containerSize: textContainer.size,
            inset: textContainerInset,
            style: traitCollection.userInterfaceStyle,
            contrast: traitCollection.accessibilityContrast
        )
        let layersAttached = highlightLayers.allSatisfy { $0.superlayer === host.layer }
        guard geometry != highlightGeometry || !layersAttached else { return }
        highlightGeometry = geometry
        updateTimerHighlights()
    }

    private struct HighlightGeometry: Equatable {
        let host: ObjectIdentifier
        let hostFrame: CGRect
        let bounds: CGRect
        let containerSize: CGSize
        let inset: UIEdgeInsets
        let style: UIUserInterfaceStyle
        let contrast: UIAccessibilityContrast
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
        let host = textLayoutCanvasView

        text.enumerateAttribute(.recipeTimerReference, in: fullRange) { value, range, _ in
            guard value != nil else { return }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }

            let font = (text.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont)
                ?? RecipeDescriptionStyle.bodyFont()

            // Collect tight glyph bounding rect per visual line fragment.
            // enumerateEnclosingRects returns full-width line rects; we need per-glyph bounds.
            var fragmentRects: [CGRect] = []
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, lineGlyphRange, _ in
                let start = max(glyphRange.location, lineGlyphRange.location)
                let end = min(NSMaxRange(glyphRange), NSMaxRange(lineGlyphRange))
                guard end > start else { return }
                fragmentRects.append(
                    layoutManager.boundingRect(
                        forGlyphRange: NSRange(location: start, length: end - start),
                        in: container
                    )
                )
            }

            for (index, glyphRect) in fragmentRects.enumerated() {
                let isFirst = index == 0
                let isLast = index == fragmentRects.count - 1
                // Slice behaviour: round start-of-span (left) and end-of-span (right) corners only.
                let corners: UIRectCorner = {
                    if isFirst && isLast { return .allCorners }
                    if isFirst { return [.topLeft, .bottomLeft] }
                    if isLast { return [.topRight, .bottomRight] }
                    return []
                }()

                var box = RecipeDescriptionStyle.expandTimerRect(glyphRect, font: font, contentOrigin: origin)
                if host !== self { box = host.convert(box, from: self) }

                let layer = CAShapeLayer()
                layer.path = UIBezierPath(
                    roundedRect: box,
                    byRoundingCorners: corners,
                    cornerRadii: CGSize(width: radius, height: radius)
                ).cgPath
                layer.fillColor = fill.cgColor
                host.layer.insertSublayer(layer, at: 0)
                highlightLayers.append(layer)
            }
        }
    }
}

private extension UIFont {
    func with(traits: UIFontDescriptor.SymbolicTraits) -> UIFont? {
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return nil }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
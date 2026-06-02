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

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.dataDetectorTypes = []
        textView.adjustsFontForContentSizeCategory = true
        textView.linkTextAttributes = [
            .foregroundColor: RecipeDescriptionStyle.linkUIColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.attributedText = Self.attributedString(runs: runs, accentColor: accentColor)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width - 32
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fitting.height)
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
            case .timer(let value):
                var attrs = base
                attrs[.font] = RecipeDescriptionStyle.mediumFont()
                attrs[.foregroundColor] = accentUIColor
                attrs[.backgroundColor] = accentUIColor.withAlphaComponent(0.15)
                result.append(NSAttributedString(string: value, attributes: attrs))
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

private extension UIFont {
    func with(traits: UIFontDescriptor.SymbolicTraits) -> UIFont? {
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return nil }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
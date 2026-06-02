//
//  RecipeDescriptionView.swift
//  RecipeScalerNative
//
//  Native read-only recipe description (replaces slow HTML → NSAttributedString).
//

import SwiftUI

struct RecipeDescriptionView: View {
    let document: RecipeDescriptionDocument
    var accentColor: Color = RecipeAccentColor.color(from: "oklch(0.65 0.25 270)")

    private let bodySize: CGFloat = RecipeDescriptionStyle.bodyFontSize
    private var lineSpacing: CGFloat { RecipeDescriptionStyle.bodyLineSpacing }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(document.blocks) { block in
                blockView(block)
                    .padding(.bottom, blockBottomPadding(block))
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: RecipeDescriptionBlock) -> some View {
        switch block {
        case .paragraph(_, let runs):
            inlineText(runs)
        case .orderedStep(_, let number, let runs):
            HStack(alignment: .top, spacing: 10) {
                stepBadge(number)
                inlineText(runs)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
        case .bullet(_, let runs):
            HStack(alignment: .top, spacing: 8) {
                Text("–")
                    .font(.custom(AppFonts.sans, size: bodySize))
                    .foregroundStyle(accentColor)
                    .frame(width: 12, alignment: .leading)
                inlineText(runs)
            }
            .padding(.vertical, 2)
        case .heading(_, let level, let runs):
            inlineText(runs)
                .font(.custom(AppFonts.display, size: headingSize(level)))
        }
    }

    private func blockBottomPadding(_ block: RecipeDescriptionBlock) -> CGFloat {
        switch block {
        case .paragraph, .heading:
            return bodySize * 0.25
        case .orderedStep:
            return 6
        case .bullet:
            return 4
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 22
        case 2: return 20
        default: return 18
        }
    }

    private func stepBadge(_ number: Int) -> some View {
        Text("\(number)")
            .font(.custom(AppFonts.sansMedium, size: 14))
            .foregroundStyle(accentColor)
            .frame(width: 22, height: 22)
            .background(
                Circle()
                    .strokeBorder(accentColor.opacity(0.32), lineWidth: 0.75)
                    .background(Circle().fill(accentColor.opacity(0.12)))
            )
    }

    private func inlineText(_ runs: [RecipeDescriptionInlineRun]) -> some View {
        RecipeDescriptionInlineTextView(runs: runs, accentColor: accentColor)
    }
}
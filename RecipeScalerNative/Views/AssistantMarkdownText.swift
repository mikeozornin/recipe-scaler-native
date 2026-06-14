//
//  AssistantMarkdownText.swift
//  RecipeScalerNative
//

import SwiftUI

struct AssistantMarkdownText: View {
    let content: String

    private var blocks: [AssistantMarkdownBlock] {
        AssistantMarkdownRenderer.blocks(from: content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if blocks.isEmpty {
                Text(content)
                    .appBody()
                    .foregroundStyle(.primary)
            } else {
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    blockView(block)
                        .padding(
                            .top,
                            AssistantMarkdownRenderer.topSpacing(for: block, isFirst: index == 0)
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .accessibilityIdentifier(AccessibilityIdentifiers.assistantMarkdownContent)
    }

    @ViewBuilder
    private func blockView(_ block: AssistantMarkdownBlock) -> some View {
        switch block {
        case .header(let level, let text):
            Text(AssistantMarkdownRenderer.headerAttributedString(from: text, level: level))
                .lineSpacing(AppTypography.bodyLineSpacing)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

        case .paragraph(let text):
            Text(AssistantMarkdownRenderer.inlineAttributedString(from: text))
                .lineSpacing(AppTypography.bodyLineSpacing)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .appBody()
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 20, alignment: .trailing)
                        Text(AssistantMarkdownRenderer.inlineAttributedString(from: item))
                            .lineSpacing(AppTypography.bodyLineSpacing)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.leading, 4)

        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .appBody()
                            .foregroundStyle(.secondary)
                            .frame(width: 12, alignment: .center)
                        Text(AssistantMarkdownRenderer.inlineAttributedString(from: item))
                            .lineSpacing(AppTypography.bodyLineSpacing)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.leading, 4)
        }
    }
}

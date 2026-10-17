//
//  AssistantMarkdownText.swift
//  RecipeScalerNative
//

import SwiftUI

struct AssistantMarkdownText: View {
    let content: String
    /// True while the reply is still arriving: its text changes on every flush, so
    /// the parse and the last (growing) block are not stored in the shared caches.
    var isStreaming: Bool = false

    var body: some View {
        let blocks = MarkdownCache.shared.blocks(for: content, isStreaming: isStreaming)
        VStack(alignment: .leading, spacing: 0) {
            if blocks.isEmpty {
                Text(content)
                    .appBody()
                    .foregroundStyle(.primary)
            } else {
                let lastIndex = blocks.count - 1
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    // Equatable: during streaming only the block whose text changed
                    // re-renders; finished blocks above it are skipped.
                    AssistantMarkdownBlockView(
                        block: block,
                        storesRendering: !isStreaming || index < lastIndex
                    )
                    .equatable()
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
}

private struct AssistantMarkdownBlockView: View, Equatable {
    let block: AssistantMarkdownBlock
    /// Whether rendered text may be kept in `MarkdownCache` (false for the growing tail).
    let storesRendering: Bool

    /// Output depends only on `block`; `storesRendering` affects caching, not the result.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.block == rhs.block
    }

    var body: some View {
        switch block {
        case .header(let level, let text):
            Text(header(text, level: level))
                .lineSpacing(AppTypography.bodyLineSpacing)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

        case .paragraph(let text):
            Text(inline(text))
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
                        Text(inline(item))
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
                        Text(inline(item))
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

    private func inline(_ text: String) -> AttributedString {
        MarkdownCache.shared.inlineAttributedString(for: text, storesResult: storesRendering)
    }

    private func header(_ text: String, level: Int) -> AttributedString {
        MarkdownCache.shared.headerAttributedString(for: text, level: level, storesResult: storesRendering)
    }
}

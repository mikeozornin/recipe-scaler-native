//
//  AssistantToolStatusRow.swift
//  RecipeScalerNative
//
//  Web parity: Marker tool-status + processing shimmer (spec 073).
//

import SwiftUI

struct AssistantToolStatusRow: View {
    let toolName: String

    var body: some View {
        Text(verbatim: AssistantToolStatusI18n.localizedStatus(for: toolName))
            .appFootnote()
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(height: 1)
            }
            .accessibilityIdentifier("assistant_tool_status_row")
    }
}

struct AssistantProcessingRow: View {
    var body: some View {
        Text("assistant.processing")
            .appFootnote()
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(AssistantTextShimmer())
            .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Subtle text shimmer for assistant processing placeholder (web `.shimmer` parity).
private struct AssistantTextShimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -0.6

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .overlay {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [
                                .clear,
                                Color.primary.opacity(0.35),
                                .clear,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: proxy.size.width * 0.55)
                        .offset(x: proxy.size.width * phase)
                        .blendMode(.sourceAtop)
                    }
                    .mask(content)
                }
                .onAppear {
                    withAnimation(.linear(duration: 1.35).repeatForever(autoreverses: false)) {
                        phase = 1.1
                    }
                }
        }
    }
}

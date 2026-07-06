//
//  AssistantVoiceLevelMeter.swift
//  RecipeScalerNative
//
//  Tape-style equalizer (web parity, commit a9f193ff): 2pt fixed-width bars
//  carrying precomputed heights from `AssistantVoiceRecorder.barHeights`.
//  Newest sample lands on the right edge; old samples scroll left as the
//  buffer fills. Each bar keeps its height once recorded.
//

import SwiftUI

struct AssistantVoiceLevelMeter: View {
    let barHeights: [CGFloat]

    private let barWidth = AssistantVoiceRecorder.meterBarWidth
    private let barSpacing = AssistantVoiceRecorder.meterBarSpacing
    private let minHeight = AssistantVoiceRecorder.meterMinHeight
    private let maxHeight = AssistantVoiceRecorder.meterMaxHeight

    var body: some View {
        GeometryReader { geometry in
            let visibleCount = visibleBarCount(for: geometry.size.width)
            // Show only the bars that physically fit; older history beyond that is trimmed.
            // If fewer bars exist than slots, right-align so the newest stays at the trailing edge.
            let startIndex = max(0, barHeights.count - visibleCount)
            let visibleRange = startIndex..<barHeights.count
            HStack(alignment: .center, spacing: barSpacing) {
                // Each bar id is its absolute index in `barHeights`, so adding a new bar
                // at the right inserts a new view rather than morphing existing ones in place.
                ForEach(visibleRange, id: \.self) { index in
                    bar(height: barHeights[index])
                        .id(index)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .trailing)
            .animation(.easeOut(duration: 0.12), value: barHeights.count)
        }
        .frame(height: maxHeight)
        .accessibilityHidden(true)
    }

    private func bar(height: CGFloat) -> some View {
        Capsule()
            .fill(Color.primary.opacity(0.65))
            .frame(width: barWidth, height: max(minHeight, min(maxHeight, height)))
    }

    private func visibleBarCount(for width: CGFloat) -> Int {
        let step = barWidth + barSpacing
        guard step > 0 else { return 1 }
        return max(1, Int((width + barSpacing) / step))
    }
}

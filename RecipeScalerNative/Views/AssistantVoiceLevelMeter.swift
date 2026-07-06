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
            // Show only the bars that physically fit; trim older history beyond that.
            // If fewer bars exist than slots, we still right-align so newest is at the trailing edge.
            let slice = Array(barHeights.suffix(visibleCount))
            HStack(alignment: .center, spacing: barSpacing) {
                ForEach(Array(slice.enumerated()), id: \.offset) { _, height in
                    bar(height: height)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .trailing)
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

//
//  AssistantVoiceLevelMeter.swift
//  RecipeScalerNative
//
//  iMessage-style waveform: vertical bars driven by live mic `averagePower` samples.
//  Native to iOS for the voice-message context (Messages.app pattern).
//

import SwiftUI

struct AssistantVoiceLevelMeter: View {
    let samples: [CGFloat]

    private let barWidth: CGFloat = 3
    private let minBarSpacing: CGFloat = 2
    private let minHeight: CGFloat = 4
    private let maxHeight: CGFloat = 28

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let barCount = max(8, Int((width + minBarSpacing) / (barWidth + minBarSpacing)))
            let totalBarWidth = CGFloat(barCount) * barWidth
            let barSpacing = barCount > 1
                ? max(minBarSpacing, (width - totalBarWidth) / CGFloat(barCount - 1))
                : 0
            HStack(alignment: .center, spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(barColor(for: index, barCount: barCount))
                        .frame(width: barWidth, height: barHeight(for: index, barCount: barCount))
                        .animation(.easeOut(duration: 0.07), value: samples.last ?? 0)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
        }
        .frame(height: maxHeight)
        .accessibilityHidden(true)
    }

    private func sampleValue(for index: Int, barCount: Int) -> CGFloat {
        guard !samples.isEmpty else { return 0.08 }
        let center = CGFloat(index) / CGFloat(max(barCount - 1, 1))
        let mapped = center * CGFloat(samples.count - 1)
        let lower = Int(mapped.rounded(.down))
        let upper = min(lower + 1, samples.count - 1)
        let fraction = mapped - CGFloat(lower)
        let a = samples[max(0, lower)]
        let b = samples[upper]
        return a + (b - a) * fraction
    }

    private func barHeight(for index: Int, barCount: Int) -> CGFloat {
        let value = sampleValue(for: index, barCount: barCount)
        return max(minHeight, value * maxHeight)
    }

    private func barColor(for index: Int, barCount: Int) -> Color {
        let value = sampleValue(for: index, barCount: barCount)
        if value > 0.75 {
            return .red.opacity(0.9)
        }
        return .primary.opacity(0.55 + Double(value) * 0.45)
    }
}

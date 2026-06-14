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

    private let barCount = 32
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 3
    private let minHeight: CGFloat = 4
    private let maxHeight: CGFloat = 28

    var body: some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(barColor(for: index))
                    .frame(width: barWidth, height: barHeight(for: index))
                    .animation(.easeOut(duration: 0.07), value: samples.last ?? 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: maxHeight)
        .accessibilityHidden(true)
    }

    private func sampleValue(for index: Int) -> CGFloat {
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

    private func barHeight(for index: Int) -> CGFloat {
        let value = sampleValue(for: index)
        return max(minHeight, value * maxHeight)
    }

    private func barColor(for index: Int) -> Color {
        let value = sampleValue(for: index)
        if value > 0.75 {
            return .red.opacity(0.9)
        }
        return .primary.opacity(0.55 + Double(value) * 0.45)
    }
}

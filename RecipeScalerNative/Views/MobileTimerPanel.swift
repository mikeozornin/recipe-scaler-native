//
//  MobileTimerPanel.swift
//  RecipeScalerNative
//

import SwiftUI

/// Phase 1 local timers above tab bar. Cross-device sync: see specs/014-timers-sync/BLOCKER.md.
struct MobileTimerPanel: View {
    @EnvironmentObject private var timerManager: TimerManager

    var body: some View {
        if timerManager.activeTimers.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(timerManager.activeTimers) { timer in
                        HStack(spacing: 6) {
                            Text(timer.name)
                                .font(AppTypography.footnoteSemibold)
                            Text(formatRemaining(timer.remainingTime ?? timer.duration))
                                .font(AppTypography.monoFootnoteDigits)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .background(Color(.systemBackground).opacity(0.9))
        }
    }

    private func formatRemaining(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }
}
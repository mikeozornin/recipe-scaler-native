//
//  MobileTimerPanel.swift
//  RecipeScalerNative
//

import SwiftUI

/// Active timers above tab bar (local + cross-device sync). Compact mobile layout.
struct MobileTimerPanel: View {
    @EnvironmentObject private var timerManager: TimerManager
    @State private var isCollapsed = true

    private var expandedListMaxHeight: CGFloat {
        let rowCount = CGFloat(timerManager.activeTimers.count)
        return min(rowCount, CGFloat(TimerPanelMetrics.maxVisibleRows)) * TimerPanelMetrics.barHeight
    }

    var body: some View {
        if timerManager.activeTimers.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                panelHeader
                if !isCollapsed {
                    Divider()
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(timerManager.activeTimers, id: \.id) { timer in
                                MobileTimerRow(timer: timer)
                                if timer.id != timerManager.activeTimers.last?.id {
                                    Divider().padding(.leading, TimerPanelMetrics.barHeight)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: expandedListMaxHeight)
                }
            }
            .frame(height: isCollapsed ? TimerPanelMetrics.barHeight : nil, alignment: .top)
            .clipped()
            .background(Color(.systemBackground))
            .overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }
            .shadow(color: .black.opacity(0.06), radius: 4, y: -1)
            .accessibilityIdentifier(AccessibilityIdentifiers.mobileTimerPanel)
        }
    }

    private var panelHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCollapsed.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                if isCollapsed {
                    collapsedSummary
                } else {
                    HStack(spacing: 4) {
                        Text("Timers", comment: "Mobile timer panel section title")
                            .font(AppTypography.bodySemibold)
                        Text("·")
                            .font(AppTypography.body)
                            .foregroundStyle(.secondary)
                        HStack(spacing: TimerPanelMetrics.runningIndicatorLeadingInset) {
                            Text("\(timerManager.activeTimers.count)")
                                .font(AppTypography.bodySemibold)
                            if timerManager.activeTimers.contains(where: \.isRunning) {
                                TimerPanelPulsingIndicator(
                                    color: .red,
                                    size: TimerPanelMetrics.runningIndicatorSize
                                )
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                TimerPanelIcon.chevron(isCollapsed ? .up : .down)
            }
            .padding(.horizontal, TimerPanelMetrics.horizontalInset)
            .frame(height: TimerPanelMetrics.barHeight, alignment: .center)
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(AccessibilityIdentifiers.mobileTimerPanelHeader)
    }

    @ViewBuilder
    private var collapsedSummary: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: 4) {
                ForEach(Array(timerManager.activeTimers.enumerated()), id: \.element.id) { index, timer in
                    let remaining = TimerUtils.remainingSeconds(for: timer)
                    let color = chipColor(remaining: remaining, duration: Int(timer.duration))
                    Text(timer.name)
                        .font(AppTypography.bodySemibold)
                        .foregroundStyle(color)
                    Text(TimerUtils.formatTime(seconds: remaining))
                        .font(AppTypography.mono(AppTypography.bodySize).monospacedDigit())
                        .foregroundStyle(color)
                    if index < timerManager.activeTimers.count - 1 {
                        Text("·")
                            .font(AppTypography.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: TimerPanelMetrics.barHeight)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .frame(height: TimerPanelMetrics.barHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chipColor(remaining: Int, duration: Int) -> Color {
        if remaining < 0 { return .red }
        if duration > 0, remaining < duration / 10 { return .yellow }
        return .primary
    }
}

// MARK: - Metrics & SF icons

private enum TimerPanelMetrics {
    /// iOS minimum comfortable tap height; collapsed bar uses this exactly.
    static let barHeight: CGFloat = 44
    static let horizontalInset: CGFloat = 12
    static let controlIconSide: CGFloat = 17
    static let maxVisibleRows = 3
    /// Gap between timer title row and progress (ingredient name → KBJU uses 4pt; slightly more here).
    static let titleToProgressSpacing: CGFloat = 6
    static let runningIndicatorSize: CGFloat = 8
    static let runningIndicatorLeadingInset: CGFloat = 8
}

/// Pulsing dot — same rhythm as `ScreenAwakeStatusBanner`.
private struct TimerPanelPulsingIndicator: View {
    let color: Color
    let size: CGFloat
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(pulse ? 1 : 0.45)
            .onAppear {
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

private enum TimerPanelIcon {
    case chevron(Chevron)

    enum Chevron {
        case up, down
    }

    @ViewBuilder
    static func chevron(_ direction: Chevron) -> some View {
        AppSymbol.compactControlImage(direction == .up ? "chevron.up" : "chevron.down")
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    static func playPause(isRunning: Bool) -> some View {
        AppSymbol.compactControlImage(isRunning ? "pause.fill" : "play.fill")
    }

    @ViewBuilder
    static func close() -> some View {
        AppSymbol.compactControlImage("xmark")
            .foregroundStyle(.secondary)
    }
}

private struct MobileTimerRow: View {
    @EnvironmentObject private var timerManager: TimerManager
    let timer: RecipeTimer

    private var remaining: Int {
        TimerUtils.remainingSeconds(for: timer)
    }

    private var progress: Double {
        guard timer.duration > 0 else { return 0 }
        let elapsed = timer.duration - Double(remaining)
        return min(1, max(0, elapsed / timer.duration))
    }

    private var statusColor: Color {
        if remaining < 0 { return .red }
        if timer.duration > 0, remaining < Int(timer.duration) / 10 { return .yellow }
        return .primary
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: toggleTimer) {
                TimerPanelIcon.playPause(isRunning: timer.isRunning && !timer.isPaused)
                    .frame(width: TimerPanelMetrics.barHeight, height: TimerPanelMetrics.barHeight)
            }
            .buttonStyle(.plain)
            .disabled(remaining < 0)
            .accessibilityIdentifier(AccessibilityIdentifiers.mobileTimerToggle(timerId: timer.id))
            .accessibilityLabel(toggleAccessibilityLabel)

            VStack(alignment: .leading, spacing: TimerPanelMetrics.titleToProgressSpacing) {
                HStack(spacing: 4) {
                    Text(timer.name)
                        .font(AppTypography.body)
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(TimerUtils.formatTime(seconds: remaining))
                        .font(AppTypography.mono(AppTypography.bodySize).monospacedDigit())
                        .foregroundStyle(statusColor)
                }
                ProgressView(value: progress)
                    .tint(progressTint)
                    .frame(height: 2)
            }
            .padding(.vertical, 6)

            Button(role: .destructive, action: { timerManager.deleteTimer(id: timer.id) }) {
                TimerPanelIcon.close()
                    .frame(width: TimerPanelMetrics.barHeight, height: TimerPanelMetrics.barHeight)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityIdentifiers.mobileTimerDelete(timerId: timer.id))
            .accessibilityLabel("Delete timer")
        }
        .frame(height: TimerPanelMetrics.barHeight)
        .accessibilityIdentifier(AccessibilityIdentifiers.mobileTimerChip(timerId: timer.id))
    }

    private var toggleAccessibilityLabel: String {
        if remaining < 0 { return "Overdue" }
        if timer.isRunning, !timer.isPaused { return "Pause" }
        if timer.isPaused { return "Resume" }
        return "Start"
    }

    private var progressTint: Color {
        if remaining < 0 { return .red }
        if timer.duration > 0, remaining < Int(timer.duration) / 10 { return .yellow }
        return .primary
    }

    private func toggleTimer() {
        guard remaining >= 0 else { return }
        if timer.isRunning, !timer.isPaused {
            timerManager.pauseTimer(id: timer.id)
        } else if timer.isPaused {
            timerManager.resumeTimer(id: timer.id)
        } else {
            timerManager.startTimer(id: timer.id)
        }
    }
}
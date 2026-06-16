//
//  MobileTimerPanel.swift
//  RecipeScalerNative
//

import SwiftUI

/// Active timers above tab bar (local + cross-device sync). Compact mobile layout.
struct MobileTimerPanel: View {
    @Environment(TimerManager.self) private var timerManager
    @Binding var isCollapsed: Bool

    private var expandedListMaxHeight: CGFloat {
        let rowCount = CGFloat(timerManager.activeTimers.count)
        return min(rowCount, CGFloat(MobileTimerPanelLayout.maxVisibleRows)) * MobileTimerPanelLayout.barHeight
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
                                    Divider().padding(.leading, MobileTimerPanelLayout.barHeight)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: expandedListMaxHeight)
                }
            }
            .frame(height: isCollapsed ? MobileTimerPanelLayout.barHeight : nil, alignment: .top)
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
                        Text("mobile-timer.panel.title")
                            .font(AppTypography.bodySemibold)
                        Text("·")
                            .font(AppTypography.body)
                            .foregroundStyle(.secondary)
                        HStack(spacing: MobileTimerPanelLayout.runningIndicatorLeadingInset) {
                            Text("\(timerManager.activeTimers.count)")
                                .font(AppTypography.bodySemibold)
                            if timerManager.activeTimers.contains(where: \.isRunning) {
                                TimerPanelPulsingIndicator(
                                    color: .red,
                                    size: MobileTimerPanelLayout.runningIndicatorSize
                                )
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                TimerPanelIcon.chevron(isCollapsed ? .up : .down)
            }
            .padding(.horizontal, MobileTimerPanelLayout.horizontalInset)
            .frame(height: MobileTimerPanelLayout.barHeight, alignment: .center)
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
            .frame(height: MobileTimerPanelLayout.barHeight)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .frame(height: MobileTimerPanelLayout.barHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chipColor(remaining: Int, duration: Int) -> Color {
        if remaining < 0 { return .red }
        if duration > 0, remaining < duration / 10 { return .yellow }
        return .primary
    }
}

// MARK: - Layout metrics (shared with scroll insets)

enum MobileTimerPanelLayout {
    /// iOS minimum comfortable tap height; collapsed bar uses this exactly.
    static let barHeight: CGFloat = 44
    static let horizontalInset: CGFloat = 12
    static let maxVisibleRows = 3
    static let titleToProgressSpacing: CGFloat = 6
    static let runningIndicatorSize: CGFloat = 8
    static let runningIndicatorLeadingInset: CGFloat = 8

    /// Matches visible panel height (web `--mobile-timer-panel-h`).
    static func height(timerCount: Int, isExpanded: Bool) -> CGFloat {
        guard timerCount > 0 else { return 0 }
        if !isExpanded { return barHeight }
        let rows = min(timerCount, maxVisibleRows)
        return barHeight + CGFloat(rows) * barHeight
    }
}

// MARK: - SF icons

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
    @Environment(TimerManager.self) private var timerManager
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
                    .frame(width: MobileTimerPanelLayout.barHeight, height: MobileTimerPanelLayout.barHeight)
            }
            .buttonStyle(.plain)
            .disabled(remaining < 0)
            .accessibilityIdentifier(AccessibilityIdentifiers.mobileTimerToggle(timerId: timer.id))
            .accessibilityLabel(toggleAccessibilityLabel)

            VStack(alignment: .leading, spacing: MobileTimerPanelLayout.titleToProgressSpacing) {
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
                    .frame(width: MobileTimerPanelLayout.barHeight, height: MobileTimerPanelLayout.barHeight)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityIdentifiers.mobileTimerDelete(timerId: timer.id))
            .accessibilityLabel("timer.delete")
        }
        .frame(height: MobileTimerPanelLayout.barHeight)
        .accessibilityIdentifier(AccessibilityIdentifiers.mobileTimerChip(timerId: timer.id))
    }

    private var toggleAccessibilityLabel: String {
        if remaining < 0 { return Bundle.currentLocalizedString("timer.toggle.overdue") }
        if timer.isRunning, !timer.isPaused { return Bundle.currentLocalizedString("timer.toggle.pause") }
        if timer.isPaused { return Bundle.currentLocalizedString("timer.toggle.resume") }
        return Bundle.currentLocalizedString("timer.toggle.start")
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

// MARK: - Scroll content inset (List inside NavigationStack ignores tab-root safeAreaInset)

private struct MobileTimerPanelIsCollapsedKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var mobileTimerPanelIsCollapsed: Bool {
        get { self[MobileTimerPanelIsCollapsedKey.self] }
        set { self[MobileTimerPanelIsCollapsedKey.self] = newValue }
    }
}

/// Padding for non-list tab roots (empty/loading states).
struct MobileTimerPanelBottomPaddingModifier: ViewModifier {
    @Environment(TimerManager.self) private var timerManager
    @Environment(\.mobileTimerPanelIsCollapsed) private var isCollapsed

    private var height: CGFloat {
        MobileTimerPanelLayout.height(
            timerCount: timerManager.activeTimers.count,
            isExpanded: !isCollapsed
        )
    }

    func body(content: Content) -> some View {
        content.padding(.bottom, height)
    }
}

extension View {
    func mobileTimerPanelBottomPadding() -> some View {
        modifier(MobileTimerPanelBottomPaddingModifier())
    }
}

/// Bottom list row so the last cells stay above the shared timer panel (UITableView-safe).
struct MobileTimerPanelListSpacerRow: View {
    @Environment(TimerManager.self) private var timerManager
    @Environment(\.mobileTimerPanelIsCollapsed) private var isCollapsed

    private var height: CGFloat {
        MobileTimerPanelLayout.height(
            timerCount: timerManager.activeTimers.count,
            isExpanded: !isCollapsed
        )
    }

    var body: some View {
        if height > 0 {
            Color.clear
                .frame(height: height)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .accessibilityHidden(true)
        }
    }
}
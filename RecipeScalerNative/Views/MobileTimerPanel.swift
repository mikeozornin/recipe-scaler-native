//
//  MobileTimerPanel.swift
//  RecipeScalerNative
//

import SwiftUI

/// On iOS 26.2+ collapsed state uses `tabViewBottomAccessory` (Liquid Glass capsule);
/// expanded state uses `safeAreaInset` on tab roots because the accessory slot is
/// single-row only. On earlier iOS the legacy path uses opaque `systemBackground`.
enum MobileTimerPanelPresentation {
    case legacy
    /// Single-row mini player inside `.tabViewBottomAccessory`.
    case accessoryCollapsed
    /// Full timer list in tab-root `safeAreaInset` while expanded on iOS 26.2+.
    case insetExpanded
}

private enum MobileTimerPanelChevronNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// When set, the panel chevron uses `matchedGeometryEffect` across accessory ↔ inset.
    var mobileTimerPanelChevronNamespace: Namespace.ID? {
        get { self[MobileTimerPanelChevronNamespaceKey.self] }
        set { self[MobileTimerPanelChevronNamespaceKey.self] = newValue }
    }
}

struct MobileTimerPanel: View {
    @Environment(TimerManager.self) private var timerManager
    @Environment(\.mobileTimerPanelChevronNamespace) private var chevronNamespace
    @Binding var isCollapsed: Bool
    var presentation: MobileTimerPanelPresentation = .legacy

    private var expandedListMaxHeight: CGFloat {
        let rowCount = CGFloat(timerManager.activeTimers.count)
        return min(rowCount, CGFloat(MobileTimerPanelLayout.maxVisibleRows)) * MobileTimerPanelLayout.barHeight
    }

    /// Total intrinsic height of the expanded panel: header + divider + visible timer rows.
    /// Used as an explicit `frame(height:)` inside `safeAreaBar` — otherwise the `VStack`
    /// collapses to 0 because `ScrollView` with `.frame(maxHeight:)` has no intrinsic size.
    private var expandedPanelHeight: CGFloat {
        MobileTimerPanelLayout.barHeight + expandedListMaxHeight
    }

    var body: some View {
        if timerManager.activeTimers.isEmpty {
            EmptyView()
        } else {
            switch presentation {
            case .legacy:
                legacyBody
            case .accessoryCollapsed:
                if #available(iOS 26.2, *) {
                    accessoryCollapsedBody
                } else {
                    legacyBody
                }
            case .insetExpanded:
                if #available(iOS 26.2, *) {
                    insetExpandedBody
                } else {
                    legacyBody
                }
            }
        }
    }

    @available(iOS 26.2, *)
    @ViewBuilder
    private var accessoryCollapsedBody: some View {
        Button {
            isCollapsed = false
        } label: {
            panelHeaderRowContent(collapsed: isCollapsed)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(AccessibilityIdentifiers.mobileTimerPanelHeader)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityIdentifiers.mobileTimerPanel)
    }

    @available(iOS 26.2, *)
    @ViewBuilder
    private var insetExpandedBody: some View {
        VStack(spacing: 0) {
            panelHeader
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
            .frame(height: expandedListMaxHeight)
        }
        .frame(height: expandedPanelHeight)
        .background(.regularMaterial)
        .accessibilityIdentifier(AccessibilityIdentifiers.mobileTimerPanel)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    @ViewBuilder
    private var legacyBody: some View {
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

    private var panelHeader: some View {
        Button {
            isCollapsed.toggle()
        } label: {
            panelHeaderRowContent(collapsed: isCollapsed)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(AccessibilityIdentifiers.mobileTimerPanelHeader)
    }

    @ViewBuilder
    private func panelHeaderRowContent(collapsed: Bool) -> some View {
        HStack(spacing: 6) {
            if collapsed {
                collapsedSummary
            } else {
                expandedTitleRow
            }
            Spacer(minLength: 0)
            panelChevron(collapsed: collapsed)
        }
        .padding(.horizontal, MobileTimerPanelLayout.horizontalInset)
        .frame(height: MobileTimerPanelLayout.barHeight, alignment: .center)
        .contentShape(Rectangle())
        .animation(MobileTimerPanelLayout.toggleAnimation, value: collapsed)
    }

    @ViewBuilder
    private var expandedTitleRow: some View {
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

    @ViewBuilder
    private func panelChevron(collapsed: Bool) -> some View {
        let chevron = TimerPanelIcon.toggleChevron(isCollapsed: collapsed)
            .frame(width: MobileTimerPanelLayout.barHeight, height: MobileTimerPanelLayout.barHeight)
        if let chevronNamespace {
            chevron.matchedGeometryEffect(id: "mobile_timer_panel_chevron", in: chevronNamespace)
        } else {
            chevron
        }
    }

    @ViewBuilder
    private var collapsedSummary: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: 4) {
                    ForEach(Array(timerManager.activeTimers.enumerated()), id: \.element.id) { index, timer in
                        let remaining = TimerUtils.remainingSeconds(for: timer, now: context.date)
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
            .modifier(CollapsedTimerSummaryTrailingFadeMask())
        }
    }

    private func chipColor(remaining: Int, duration: Int) -> Color {
        if remaining < 0 { return .red }
        if duration > 0, remaining < duration / 10 { return .yellow }
        return .primary
    }
}

/// Trailing alpha fade for collapsed timer chips (glass accessory and legacy bar).
private struct CollapsedTimerSummaryTrailingFadeMask: ViewModifier {
    private var fadeWidth: CGFloat { MobileTimerPanelLayout.summaryTrailingFadeWidth }

    func body(content: Content) -> some View {
        content.mask {
            HStack(spacing: 0) {
                Rectangle().fill(Color.black)
                LinearGradient(
                    colors: [.black, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: fadeWidth)
            }
        }
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
    static let toggleAnimation: Animation = .easeInOut(duration: 0.25)
    /// Soft fade before the chevron when collapsed timer chips overflow horizontally.
    static let summaryTrailingFadeWidth: CGFloat = 20

    /// Matches visible panel height (web `--mobile-timer-panel-h`).
    static func height(timerCount: Int, isExpanded: Bool) -> CGFloat {
        guard timerCount > 0 else { return 0 }
        if !isExpanded { return barHeight }
        let rows = min(timerCount, maxVisibleRows)
        return barHeight + CGFloat(rows) * barHeight
    }

    /// Bottom inset for `List` spacer rows. Zero on iOS 26.2+ while collapsed — `tabViewBottomAccessory` handles it.
    static func listSpacerHeight(
        timerCount: Int,
        isExpanded: Bool,
        suppressPanel: Bool
    ) -> CGFloat {
        guard timerCount > 0, !suppressPanel else { return 0 }
        if #available(iOS 26.2, *) {
            if !isExpanded { return 0 }
        }
        return height(timerCount: timerCount, isExpanded: isExpanded)
    }

    /// When `false`, do not add `MobileTimerPanelListSpacerRow` to a `List` — an empty row still costs height with `defaultMinListRowHeight`.
    static func needsListSpacerRow(
        timerCount: Int,
        isExpanded: Bool,
        suppressPanel: Bool
    ) -> Bool {
        listSpacerHeight(timerCount: timerCount, isExpanded: isExpanded, suppressPanel: suppressPanel) > 0
    }

    /// Bottom padding for non-list layouts (ScrollView on detail screens, empty states).
    /// On iOS < 26.2 — always returns panel height (manual `safeAreaInset` on tab root).
    /// On iOS 26.2+ — returns 0 when collapsed (`tabViewBottomAccessory` handles inset on tab roots),
    /// but returns full panel height when expanded because pushed screens inside `NavigationStack`
    /// do NOT inherit the tab root's `safeAreaBar` — their ScrollView needs manual bottom padding.
    static func manualBottomPaddingHeight(
        timerCount: Int,
        isExpanded: Bool,
        suppressPanel: Bool
    ) -> CGFloat {
        guard timerCount > 0, !suppressPanel else { return 0 }
        if #available(iOS 26.2, *) {
            return isExpanded ? height(timerCount: timerCount, isExpanded: isExpanded) : 0
        }
        return height(timerCount: timerCount, isExpanded: isExpanded)
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

    /// Single chevron that rotates instead of swapping up/down SF Symbols.
    @ViewBuilder
    static func toggleChevron(isCollapsed: Bool) -> some View {
        AppSymbol.compactControlImage("chevron.up")
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(isCollapsed ? 0 : 180))
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

    var body: some View {
        Group {
            if timer.isRunning, !timer.isPaused {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    rowContent(now: context.date)
                }
            } else {
                rowContent(now: Date())
            }
        }
        .frame(height: MobileTimerPanelLayout.barHeight)
        .accessibilityIdentifier(AccessibilityIdentifiers.mobileTimerChip(timerId: timer.id))
    }

    private func rowContent(now: Date) -> some View {
        let remaining = TimerUtils.remainingSeconds(for: timer, now: now)
        let progress = progress(for: remaining)
        let statusColor = statusColor(for: remaining)

        return HStack(spacing: 0) {
            Button(action: toggleTimer) {
                TimerPanelIcon.playPause(isRunning: timer.isRunning && !timer.isPaused)
                    .frame(width: MobileTimerPanelLayout.barHeight, height: MobileTimerPanelLayout.barHeight)
            }
            .buttonStyle(.plain)
            .disabled(remaining < 0)
            .accessibilityIdentifier(AccessibilityIdentifiers.mobileTimerToggle(timerId: timer.id))
            .accessibilityLabel(toggleAccessibilityLabel(for: remaining))

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
                    .tint(progressTint(for: remaining))
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
    }

    private func progress(for remaining: Int) -> Double {
        guard timer.duration > 0 else { return 0 }
        let elapsed = timer.duration - Double(remaining)
        return min(1, max(0, elapsed / timer.duration))
    }

    private func statusColor(for remaining: Int) -> Color {
        if remaining < 0 { return .red }
        if timer.duration > 0, remaining < Int(timer.duration) / 10 { return .yellow }
        return .primary
    }

    private func toggleAccessibilityLabel(for remaining: Int) -> String {
        if remaining < 0 { return Bundle.currentLocalizedString("timer.toggle.overdue") }
        if timer.isRunning, !timer.isPaused { return Bundle.currentLocalizedString("timer.toggle.pause") }
        if timer.isPaused { return Bundle.currentLocalizedString("timer.toggle.resume") }
        return Bundle.currentLocalizedString("timer.toggle.start")
    }

    private func progressTint(for remaining: Int) -> Color {
        if remaining < 0 { return .red }
        if timer.duration > 0, remaining < Int(timer.duration) / 10 { return .yellow }
        return .primary
    }

    private func toggleTimer() {
        let remaining = TimerUtils.remainingSeconds(for: timer)
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

private struct MobileTimerPanelFloatingOverlayKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var mobileTimerPanelIsCollapsed: Bool {
        get { self[MobileTimerPanelIsCollapsedKey.self] }
        set { self[MobileTimerPanelIsCollapsedKey.self] = newValue }
    }

    /// Spec 063 — iPad floating overlay (not `tabViewBottomAccessory` / tab-root inset).
    /// When true, scroll/list chrome always reserves the panel height while timers run.
    var mobileTimerPanelFloatingOverlay: Bool {
        get { self[MobileTimerPanelFloatingOverlayKey.self] }
        set { self[MobileTimerPanelFloatingOverlayKey.self] = newValue }
    }
}

/// Padding for non-list tab roots (empty/loading states).
struct MobileTimerPanelBottomPaddingModifier: ViewModifier {
    @Environment(TimerManager.self) private var timerManager
    @Environment(\.mobileTimerPanelIsCollapsed) private var isCollapsed
    @Environment(\.mobileTimerPanelFloatingOverlay) private var floatingOverlay

    /// When `true`, this modifier contributes no bottom padding (e.g. while editing,
    /// another bottom inset is already active). Must be passed explicitly (not via env)
    /// because env set on the content does not reach the modifier's own context.
    var suppress: Bool = false

    private var height: CGFloat {
        guard !suppress else { return 0 }
        if floatingOverlay {
            guard !timerManager.suppressPanelSafeAreaInset else { return 0 }
            return MobileTimerPanelLayout.height(
                timerCount: timerManager.activeTimers.count,
                isExpanded: !isCollapsed
            )
        }
        return MobileTimerPanelLayout.manualBottomPaddingHeight(
            timerCount: timerManager.activeTimers.count,
            isExpanded: !isCollapsed,
            suppressPanel: timerManager.suppressPanelSafeAreaInset
        )
    }

    func body(content: Content) -> some View {
        content.padding(.bottom, height)
    }
}

extension View {
    func mobileTimerPanelBottomPadding(suppress: Bool = false) -> some View {
        modifier(MobileTimerPanelBottomPaddingModifier(suppress: suppress))
    }
}

/// Bottom list row so the last cells stay above the shared timer panel (UITableView-safe).
/// Insert only when `MobileTimerPanelLayout.needsListSpacerRow` is true — otherwise `List`
/// still allocates a row (see `defaultMinListRowHeight`).
struct MobileTimerPanelListSpacerRow: View {
    @Environment(TimerManager.self) private var timerManager
    @Environment(\.mobileTimerPanelIsCollapsed) private var isCollapsed
    @Environment(\.mobileTimerPanelFloatingOverlay) private var floatingOverlay

    private var height: CGFloat {
        if floatingOverlay {
            guard !timerManager.suppressPanelSafeAreaInset else { return 0 }
            return MobileTimerPanelLayout.height(
                timerCount: timerManager.activeTimers.count,
                isExpanded: !isCollapsed
            )
        }
        return MobileTimerPanelLayout.listSpacerHeight(
            timerCount: timerManager.activeTimers.count,
            isExpanded: !isCollapsed,
            suppressPanel: timerManager.suppressPanelSafeAreaInset
        )
    }

    var body: some View {
        Color.clear
            .frame(height: height)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .accessibilityHidden(true)
    }
}

enum MobileTimerPanelListChrome {
    @MainActor
    static func needsSpacer(
        timerManager: TimerManager,
        isCollapsed: Bool,
        floatingOverlay: Bool = false
    ) -> Bool {
        if floatingOverlay {
            return !timerManager.suppressPanelSafeAreaInset
                && !timerManager.activeTimers.isEmpty
        }
        return MobileTimerPanelLayout.needsListSpacerRow(
            timerCount: timerManager.activeTimers.count,
            isExpanded: !isCollapsed,
            suppressPanel: timerManager.suppressPanelSafeAreaInset
        )
    }
}
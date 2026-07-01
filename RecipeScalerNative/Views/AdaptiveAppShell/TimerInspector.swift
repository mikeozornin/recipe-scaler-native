//
//  TimerInspector.swift
//  RecipeScalerNative
//
//  Spec 043 — timers in toolbar / inspector (regular layout).
//

import SwiftUI

struct TimerInspectorToolbarContent: ToolbarContent {
    @Environment(TimerManager.self) private var timerManager
    @Binding var isInspectorPresented: Bool

    var body: some ToolbarContent {
        if !timerManager.suppressPanelSafeAreaInset, !timerManager.activeTimers.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isInspectorPresented.toggle()
                } label: {
                    AppToolbarStyle.iconOnly(systemName: "timer")
                }
                .appToolbarIconButton()
                .accessibilityLabel(Text("mobile-timer.panel.title"))
                .accessibilityIdentifier(AccessibilityIdentifiers.timerInspectorToggle)
            }
        }
    }
}

struct TimerInspectorModifier: ViewModifier {
    @Environment(TimerManager.self) private var timerManager
    @Binding var isInspectorPresented: Bool

    func body(content: Content) -> some View {
        content
            .inspector(isPresented: $isInspectorPresented) {
                if !timerManager.activeTimers.isEmpty {
                    TimerInspectorPanel()
                        .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
                }
            }
    }
}

private struct TimerInspectorPanel: View {
    @Environment(TimerManager.self) private var timerManager
    @State private var collapsed = false

    var body: some View {
        MobileTimerPanel(isCollapsed: $collapsed, presentation: .legacy)
            .environment(timerManager)
            .navigationTitle(Text("mobile-timer.panel.title"))
    }
}

extension View {
    func timerInspector(isPresented: Binding<Bool>) -> some View {
        modifier(TimerInspectorModifier(isInspectorPresented: isPresented))
    }
}
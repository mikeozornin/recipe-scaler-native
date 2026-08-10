//
//  TimerInspector.swift
//  RecipeScalerNative
//
//  Spec 043 — timers in toolbar / inspector (regular layout).
//

import SwiftUI

#if os(macOS)
struct TimerInspectorToolbarContent: ToolbarContent {
    @Environment(TimerManager.self) private var timerManager
    @Binding var isInspectorPresented: Bool

    var body: some ToolbarContent {
        if !timerManager.activeTimers.isEmpty {
            ToolbarItem {
                Button {
                    isInspectorPresented.toggle()
                } label: {
                    AppToolbarStyle.iconOnly(systemName: "timer")
                }
                .appToolbarIconButton()
                .help(Text("mobile-timer.panel.title"))
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
                    MacTimerInspectorPanel()
                        .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
                }
            }
    }
}

private struct MacTimerInspectorPanel: View {
    @Environment(TimerManager.self) private var timerManager

    var body: some View {
        List {
            ForEach(timerManager.activeTimers, id: \.id) { timer in
                HStack(spacing: 8) {
                    AppSymbol.image("timer")
                    Text(timer.name)
                        .appBody()
                        .lineLimit(1)
                    Spacer()
                    Button {
                        if timer.isRunning {
                            timerManager.pauseTimer(id: timer.id)
                        } else {
                            timerManager.resumeTimer(id: timer.id)
                        }
                    } label: {
                        AppSymbol.image(timer.isRunning ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text(timer.isRunning ? "mobile-timer.pause" : "mobile-timer.resume"))
                }
                .padding(.vertical, 4)
                .contextMenu {
                    Button("mobile-timer.delete") {
                        timerManager.deleteTimer(id: timer.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(Text("mobile-timer.panel.title"))
    }
}

extension View {
    func timerInspector(isPresented: Binding<Bool>) -> some View {
        modifier(TimerInspectorModifier(isInspectorPresented: isPresented))
    }
}
#else
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
#endif

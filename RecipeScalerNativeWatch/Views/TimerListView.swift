//
//  TimerListView.swift
//  RecipeScalerNativeWatch Watch App
//
//  Spec 039 — main watch UI. List of active timers with swipe actions,
//  Settings row at the bottom, and dedicated views for Empty / Error /
//  NotAuthorized states. Live countdown + progress via a list-level
//  `TimelineView` (see `verify-claims.md` claim W7).
//

import SwiftUI
import RecipeScalerCore

struct TimerListView: View {
    @StateObject var viewModel: TimerListViewModel
    @State private var hasBootstrapped = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .idle, .loading:
                    loadingView
                case .loaded(let timers):
                    loadedList(timers: timers)
                case .empty:
                    EmptyStateView()
                case .error:
                    ErrorStateView()
                case .notAuthorized:
                    NotAuthorizedStateView()
                }
            }
        }
        .task {
            // Bootstrap on first appearance (covers cold launch + wake).
            guard !hasBootstrapped else { return }
            hasBootstrapped = true
            await viewModel.bootstrap()
        }
        .task {
            await viewModel.foregroundRefreshLoop()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await viewModel.refresh() }
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    private var loadingView: some View {
        VStack {
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadedList(timers: [WatchTimer]) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            List {
                Section {
                    ForEach(timers) { timer in
                        TimerRow(timer: timer, now: timeline.date)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                Task { await viewModel.togglePause(timer) }
                            } label: {
                                Label(
                                    timer.isPaused
                                        ? LocalizedStringKey("watch.timer.action.resume")
                                        : LocalizedStringKey("watch.timer.action.pause"),
                                    systemImage: timer.actionIcon
                                )
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { await viewModel.delete(timer) }
                            } label: {
                                Label(
                                    LocalizedStringKey("watch.timer.action.delete"),
                                    systemImage: "trash"
                                )
                            }
                        }
                    }
                }

                if showsSettings {
                    Section {
                        SettingsRow()
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    /// Store frame of three timers leaves the settings row off so all three
    /// names stay on screen. Empty / error / signed-out keep the real row.
    private var showsSettings: Bool {
        #if DEBUG
        if WatchScreenshotFixture.scene == .timers { return false }
        #endif
        return true
    }
}

// MARK: - Previews

#Preview("List — mix") {
    TimerListView(viewModel: TimerListViewModel())
        .task { /* no bootstrap */ }
}

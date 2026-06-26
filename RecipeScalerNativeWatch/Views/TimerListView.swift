//
//  TimerListView.swift
//  RecipeScalerNativeWatch Watch App
//
//  Spec 039 — main watch UI. List of active timers with swipe actions,
//  Settings row at the bottom, and dedicated views for Empty / Error /
//  NotAuthorized states. Live countdown via Text(timerInterval:) — no
//  manual timer driver (battery).
//

import SwiftUI
import RecipeScalerCore

struct TimerListView: View {
    @StateObject var viewModel: TimerListViewModel
    @State private var hasBootstrapped = false

    var body: some View {
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
        .task {
            // Bootstrap on first appearance (covers cold launch + wake).
            guard !hasBootstrapped else { return }
            hasBootstrapped = true
            await viewModel.bootstrap()
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
        List {
            Section {
                ForEach(timers) { timer in
                    TimerRow(timer: timer)
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

            Section {
                SettingsRow()
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Previews

#Preview("List — mix") {
    TimerListView(viewModel: TimerListViewModel())
        .task { /* no bootstrap */ }
}

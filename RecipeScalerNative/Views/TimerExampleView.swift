//
//  TimerExampleView.swift
//  RecipeScalerNative
//
//

import RecipeScalerCore
import SwiftUI

/// Example view demonstrating TimerManager usage
struct TimerExampleView: View {
    @Environment(TimerManager.self) var timerManager
    @State private var timerName = "Bake Cookies"
    @State private var timerDuration = 12.0
    @State private var selectedType: RecipeTimer.TimerType = .minutes

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // MARK: - Create Timer Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Create New Timer")
                        .font(AppTypography.bodySemibold)

                    TextField("Timer Name", text: $timerName)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        VStack(alignment: .leading) {
                            Text("Duration")
                                .appFootnote()
                            Stepper(value: $timerDuration, in: 1...120, step: 1) {
                                Text("\(Int(timerDuration))")
                                    .font(AppTypography.title3)
                            }
                        }

                        Picker("Type", selection: $selectedType) {
                            Text("Seconds").tag(RecipeTimer.TimerType.seconds)
                            Text("Minutes").tag(RecipeTimer.TimerType.minutes)
                            Text("Hours").tag(RecipeTimer.TimerType.hours)
                        }
                        .pickerStyle(.segmented)
                    }

                    Button(action: createTimer) {
                        HStack {
                            AppSymbol.image("plus.circle.fill")
                            Text("Create Timer")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)

                // MARK: - Active Timers Section
                VStack(alignment: .leading, spacing: 12) {
                    Text(verbatim: Bundle.appPluralizedString(
                        key: "timer.example.active-timers",
                        count: timerManager.activeTimers.count
                    ))
                        .font(AppTypography.bodySemibold)

                    if timerManager.activeTimers.isEmpty {
                        Text("timer.example.no-active-timers")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        ScrollView {
                            VStack(spacing: 10) {
                                ForEach(timerManager.activeTimers, id: \.id) { timer in
                                    ActiveTimerRow(timer: timer)
                                        .environment(timerManager)
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)

                // MARK: - All Timers Section
                VStack(alignment: .leading, spacing: 12) {
                    Text(verbatim: Bundle.appPluralizedString(
                        key: "timer.example.all-timers",
                        count: timerManager.timers.count
                    ))
                        .font(AppTypography.bodySemibold)

                    if timerManager.timers.isEmpty {
                        Text("timer.example.no-timers")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        ScrollView {
                            VStack(spacing: 10) {
                                ForEach(timerManager.timers, id: \.id) { timer in
                                    TimerRow(timer: timer)
                                        .environment(timerManager)
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)

                Spacer()
            }
            .padding()
            .navigationTitle(Text(verbatim: Bundle.currentLocalizedString("timer.example.title")))
        }
    }

    private func createTimer() {
        let duration: TimeInterval
        switch selectedType {
        case .seconds:
            duration = timerDuration
        case .minutes:
            duration = timerDuration * 60
        case .hours:
            duration = timerDuration * 3600
        }

        _ = timerManager.createTimer(
            name: timerName.isEmpty ? "Timer" : timerName,
            duration: duration,
            type: selectedType
        )

        // Reset form
        timerName = "Bake Cookies"
        timerDuration = 12.0
        selectedType = .minutes
    }
}

// MARK: - Active Timer Row
struct ActiveTimerRow: View {
    @Environment(TimerManager.self) var timerManager
    let timer: RecipeTimer
    
    var displayTime: String {
        guard let remaining = timer.remainingTime, remaining > 0 else {
            return "00:00"
        }
        let totalSeconds = Int(remaining)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    var body: some View {
        HStack(spacing: 15) {
            VStack(alignment: .leading, spacing: 4) {
                Text(timer.name)
                    .font(AppTypography.bodySemibold)
                Text(displayTime)
                    .font(AppTypography.sansMedium(AppTypography.title2Size))
                    .monospacedDigit()
                    .foregroundColor(.blue)
            }

            Spacer()

            VStack(spacing: 8) {
                Button(action: { timerManager.pauseTimer(id: timer.id) }) {
                    AppSymbol.image("pause.fill")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)

                Button(action: { timerManager.deleteTimer(id: timer.id) }) {
                    AppSymbol.image("trash.fill")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .border(Color.blue, width: 2)
    }
}

// MARK: - Timer Row
struct TimerRow: View {
    @Environment(TimerManager.self) var timerManager
    let timer: RecipeTimer

    var statusText: String {
        if timer.hasCompleted {
            return "Completed"
        } else if timer.isRunning {
            return "Running"
        } else if timer.isPaused {
            return "Paused"
        } else {
            return "Stopped"
        }
    }

    var statusColor: Color {
        if timer.hasCompleted {
            return .green
        } else if timer.isRunning {
            return .blue
        } else if timer.isPaused {
            return .orange
        } else {
            return .gray
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(timer.name)
                    .font(AppTypography.bodySemibold)
                Text(statusText)
                    .appFootnote()
                    .foregroundColor(statusColor)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(verbatim: Bundle.appPluralizedString(
                    key: "timer.example.seconds",
                    count: Int(timer.duration)
                ))
                    .appFootnote()
                    .foregroundColor(.secondary)
            }

            Menu {
                if !timer.isRunning && !timer.hasCompleted {
                    Button(action: { timerManager.startTimer(id: timer.id) }) {
                        AppLabel.make("Start", symbol: "play.fill")
                    }
                }

                if timer.isRunning {
                    Button(action: { timerManager.pauseTimer(id: timer.id) }) {
                        AppLabel.make("Pause", symbol: "pause.fill")
                    }
                }

                if timer.isPaused {
                    Button(action: { timerManager.resumeTimer(id: timer.id) }) {
                        AppLabel.make("Resume", symbol: "play.fill")
                    }
                }

                if !timer.hasCompleted {
                    Button(action: { timerManager.resetTimer(id: timer.id) }) {
                        AppLabel.make("Reset", symbol: "arrow.counterclockwise")
                    }
                }

                Divider()

                Button(role: .destructive, action: { timerManager.deleteTimer(id: timer.id) }) {
                    AppLabel.make("Delete", symbol: "trash.fill")
                }
            } label: {
                AppSymbol.image("ellipsis.circle.fill")
                    .font(AppTypography.title3)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

#Preview {
    TimerExampleView()
        .environment(TimerManager())
}

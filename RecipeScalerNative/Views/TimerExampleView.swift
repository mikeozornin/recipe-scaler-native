//
//  TimerExampleView.swift
//  RecipeScalerNative
//
//

import SwiftUI

/// Example view demonstrating TimerManager usage
struct TimerExampleView: View {
    @EnvironmentObject var timerManager: TimerManager
    @State private var timerName = "Bake Cookies"
    @State private var timerDuration = 12.0
    @State private var selectedType: RecipeTimer.TimerType = .minutes

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // MARK: - Create Timer Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Create New Timer")
                        .font(.custom(AppFonts.sansMedium, size: 17))

                    TextField("Timer Name", text: $timerName)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        VStack(alignment: .leading) {
                            Text("Duration")
                                .font(.custom(AppFonts.sans, size: 12))
                            Stepper(value: $timerDuration, in: 1...120, step: 1) {
                                Text("\(Int(timerDuration))")
                                    .font(.custom(AppFonts.sansMedium, size: 20))
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
                            Image(systemName: "plus.circle.fill")
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
                    Text("Active Timers (\(timerManager.activeTimers.count))")
                        .font(.custom(AppFonts.sansMedium, size: 17))

                    if timerManager.activeTimers.isEmpty {
                        Text("No active timers")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        ScrollView {
                            VStack(spacing: 10) {
                                ForEach(timerManager.activeTimers, id: \.id) { timer in
                                    ActiveTimerRow(timer: timer)
                                        .environmentObject(timerManager)
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
                    Text("All Timers (\(timerManager.timers.count))")
                        .font(.custom(AppFonts.sansMedium, size: 17))

                    if timerManager.timers.isEmpty {
                        Text("No timers created yet")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        ScrollView {
                            VStack(spacing: 10) {
                                ForEach(timerManager.timers, id: \.id) { timer in
                                    TimerRow(timer: timer)
                                        .environmentObject(timerManager)
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
            .navigationTitle("Timer Manager")
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
    @EnvironmentObject var timerManager: TimerManager
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
                    .font(.custom(AppFonts.sansMedium, size: 17))
                Text(displayTime)
                    .font(.custom(AppFonts.sansMedium, size: 22))
                    .monospacedDigit()
                    .foregroundColor(.blue)
            }

            Spacer()

            VStack(spacing: 8) {
                Button(action: { timerManager.pauseTimer(id: timer.id) }) {
                    Image(systemName: "pause.fill")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)

                Button(action: { timerManager.deleteTimer(id: timer.id) }) {
                    Image(systemName: "trash.fill")
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
    @EnvironmentObject var timerManager: TimerManager
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
                    .font(.custom(AppFonts.sansMedium, size: 17))
                Text(statusText)
                    .font(.custom(AppFonts.sans, size: 12))
                    .foregroundColor(statusColor)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(Int(timer.duration)) sec")
                    .font(.custom(AppFonts.sans, size: 12))
                    .foregroundColor(.secondary)
            }

            Menu {
                if !timer.isRunning && !timer.hasCompleted {
                    Button(action: { timerManager.startTimer(id: timer.id) }) {
                        Label("Start", systemImage: "play.fill")
                    }
                }

                if timer.isRunning {
                    Button(action: { timerManager.pauseTimer(id: timer.id) }) {
                        Label("Pause", systemImage: "pause.fill")
                    }
                }

                if timer.isPaused {
                    Button(action: { timerManager.resumeTimer(id: timer.id) }) {
                        Label("Resume", systemImage: "play.fill")
                    }
                }

                if !timer.hasCompleted {
                    Button(action: { timerManager.resetTimer(id: timer.id) }) {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                }

                Divider()

                Button(role: .destructive, action: { timerManager.deleteTimer(id: timer.id) }) {
                    Label("Delete", systemImage: "trash.fill")
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.custom(AppFonts.sansMedium, size: 20))
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

#Preview {
    TimerExampleView()
        .environmentObject(TimerManager())
}

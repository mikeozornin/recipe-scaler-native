//
//  StartTimerIntent.swift
//  RecipeScalerNative
//

import AppIntents

struct StartTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a cooking timer"
    static var description = IntentDescription("Starts a countdown timer in Recipe Scaler.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Minutes", description: "Number of minutes to count down.", default: 0)
    var minutes: Int

    @Parameter(title: "Hours", description: "Number of hours to count down.", default: 0)
    var hours: Int

    @Parameter(title: "Timer name", description: "Label for the timer.", default: "Cooking timer")
    var name: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let totalSeconds = hours * 3600 + minutes * 60
        guard totalSeconds > 0 else {
            throw TimerIntentError.zeroDuration
        }

        let timerType: RecipeTimer.TimerType
        if hours > 0 && minutes == 0 {
            timerType = .hours
        } else if hours == 0 {
            timerType = .minutes
        } else {
            timerType = .seconds
        }

        let label = name.trimmingCharacters(in: .whitespaces).isEmpty ? "Cooking timer" : name

        await TimerManager.configureForIntentIfNeeded()
        await TimerManager.shared.createAndStartTimer(
            name: label,
            duration: TimeInterval(totalSeconds),
            type: timerType
        )

        let dialog = buildDialog(hours: hours, minutes: minutes)
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }

    private func buildDialog(hours: Int, minutes: Int) -> String {
        switch (hours, minutes) {
        case (let h, 0) where h > 0:
            return "Timer set for \(h) hour\(h == 1 ? "" : "s")."
        case (0, let m):
            return "Timer set for \(m) minute\(m == 1 ? "" : "s")."
        default:
            return "Timer set for \(hours) hour\(hours == 1 ? "" : "s") and \(minutes) minute\(minutes == 1 ? "" : "s")."
        }
    }
}

private enum TimerIntentError: Error, CustomLocalizedStringResourceConvertible {
    case zeroDuration
    var localizedStringResource: LocalizedStringResource {
        "Please specify at least 1 minute or 1 hour."
    }
}

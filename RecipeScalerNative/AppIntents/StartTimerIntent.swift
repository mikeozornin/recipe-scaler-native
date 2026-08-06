//
//  StartTimerIntent.swift
//  RecipeScalerNative
//

import AppIntents
import RecipeScalerCore

struct StartTimerIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource(
        "timer.intent.intent.title",
        defaultValue: "Start a cooking timer"
    )
    static var description = IntentDescription(LocalizedStringResource(
        "timer.intent.intent.description",
        defaultValue: "Starts a countdown timer in Recipe Scaler."
    ))
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: LocalizedStringResource("timers.time-types.minutes"),
        description: LocalizedStringResource("timer.intent.parameter.minutes.description"),
        default: 0
    )
    var minutes: Int

    @Parameter(
        title: LocalizedStringResource("timers.time-types.hours"),
        description: LocalizedStringResource("timer.intent.parameter.hours.description"),
        default: 0
    )
    var hours: Int

    @Parameter(
        title: LocalizedStringResource("timer.intent.parameter.name"),
        description: LocalizedStringResource("timer.intent.parameter.name.description"),
        default: ""
    )
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

        let label = name.trimmingCharacters(in: .whitespaces).isEmpty
            ? Bundle.currentLocalizedString("timer.intent.default-name")
            : name

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
            return String(
                format: Bundle.currentLocalizedString("timer.intent.dialog.hours-only"),
                Bundle.appPluralizedString(key: "timer.intent.hours", count: h)
            )
        case (0, let m):
            return String(
                format: Bundle.currentLocalizedString("timer.intent.dialog.minutes-only"),
                Bundle.appPluralizedString(key: "timer.intent.minutes", count: m)
            )
        default:
            return String(
                format: Bundle.currentLocalizedString("timer.intent.dialog.hours-and-minutes"),
                Bundle.appPluralizedString(key: "timer.intent.hours", count: hours),
                Bundle.appPluralizedString(key: "timer.intent.minutes", count: minutes)
            )
        }
    }
}

/// Spotlight / Top Hit preset: fixed 10-minute timer. Must be a named `AppIntent` type —
/// inline configured `StartTimerIntent()` in `AppShortcut` breaks `AppIntentsSSUTraining`.
struct StartTenMinuteTimerIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource(
        "timer.intent.preset-10min.title",
        defaultValue: "Start a 10-minute timer"
    )
    static var description = IntentDescription(LocalizedStringResource(
        "timer.intent.preset-10min.description",
        defaultValue: "Starts a 10-minute countdown timer in Recipe Scaler."
    ))
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var intent = StartTimerIntent()
        intent.minutes = 10
        return try await intent.perform()
    }
}

private enum TimerIntentError: Error, CustomLocalizedStringResourceConvertible {
    case zeroDuration
    var localizedStringResource: LocalizedStringResource {
        LocalizedStringResource("timer.intent.error.zero-duration")
    }
}

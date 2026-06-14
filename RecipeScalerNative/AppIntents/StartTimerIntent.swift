//
//  StartTimerIntent.swift
//  RecipeScalerNative
//

import AppIntents
import RecipeScalerCore

struct StartTimerIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("timer.siri.intent.title")
    static var description = IntentDescription(LocalizedStringResource("timer.siri.intent.description"))
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: LocalizedStringResource("timers.time-types.minutes"),
        description: LocalizedStringResource("timer.siri.parameter.minutes.description"),
        default: 0
    )
    var minutes: Int

    @Parameter(
        title: LocalizedStringResource("timers.time-types.hours"),
        description: LocalizedStringResource("timer.siri.parameter.hours.description"),
        default: 0
    )
    var hours: Int

    @Parameter(
        title: LocalizedStringResource("timer.siri.parameter.name"),
        description: LocalizedStringResource("timer.siri.parameter.name.description"),
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
            ? Bundle.currentLocalizedString("timer.siri.default-name")
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
                format: Bundle.currentLocalizedString("timer.siri.dialog.hours-only"),
                Bundle.appPluralizedString(key: "timer.siri.hours", count: h)
            )
        case (0, let m):
            return String(
                format: Bundle.currentLocalizedString("timer.siri.dialog.minutes-only"),
                Bundle.appPluralizedString(key: "timer.siri.minutes", count: m)
            )
        default:
            return String(
                format: Bundle.currentLocalizedString("timer.siri.dialog.hours-and-minutes"),
                Bundle.appPluralizedString(key: "timer.siri.hours", count: hours),
                Bundle.appPluralizedString(key: "timer.siri.minutes", count: minutes)
            )
        }
    }
}

private enum TimerIntentError: Error, CustomLocalizedStringResourceConvertible {
    case zeroDuration
    var localizedStringResource: LocalizedStringResource {
        LocalizedStringResource("timer.siri.error.zero-duration")
    }
}

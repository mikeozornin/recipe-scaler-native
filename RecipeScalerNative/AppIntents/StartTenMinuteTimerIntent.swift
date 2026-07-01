//
//  StartTenMinuteTimerIntent.swift
//  RecipeScalerNative
//

import AppIntents

/// Parameterless preset for Spotlight Top Hit and one-tap shortcuts.
struct StartTenMinuteTimerIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("timer.siri.ten-minute.title")
    static var description = IntentDescription(LocalizedStringResource("timer.siri.ten-minute.description"))
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog = try await CookingTimerIntentRunner.run(hours: 0, minutes: 10, name: "")
        return .result(dialog: dialog)
    }
}

//
//  PauseTimerIntent.swift
//  RecipeScalerNative
//

import AppIntents

struct PauseTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause cooking timer"
    static var description = IntentDescription("Pauses the active Recipe Scaler timer.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Timer ID", description: "Optional timer identifier. If omitted, the running timer is paused.")
    var timerId: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await TimerManager.configureForIntentIfNeeded()

        guard let id = await resolveTimerId() else {
            return .result(dialog: "There are no running timers to pause.")
        }

        await TimerManager.shared.pauseTimer(id: id)
        return .result(dialog: "Timer paused.")
    }

    private func resolveTimerId() async -> String? {
        if let timerId, !timerId.isEmpty {
            return timerId
        }
        return await MainActor.run {
            TimerManager.shared.timers.first { $0.isRunning }?.id
        }
    }
}

//
//  StopTimerIntent.swift
//  RecipeScalerNative
//

import AppIntents

struct StopTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop cooking timer"
    static var description = IntentDescription("Stops the active Recipe Scaler timer.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Timer ID", description: "Optional timer identifier. If omitted, the active timer is stopped.")
    var timerId: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await TimerManager.configureForIntentIfNeeded()

        guard let id = await resolveTimerId() else {
            return .result(dialog: "There are no active timers to stop.")
        }

        await TimerManager.shared.deleteTimer(id: id)
        return .result(dialog: "Timer stopped.")
    }

    private func resolveTimerId() async -> String? {
        if let timerId, !timerId.isEmpty {
            return timerId
        }
        return await MainActor.run {
            TimerManager.shared.timers.first { $0.isRunning || $0.isPaused }?.id
        }
    }
}

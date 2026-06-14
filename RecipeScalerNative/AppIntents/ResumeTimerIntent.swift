//
//  ResumeTimerIntent.swift
//  RecipeScalerNative
//

import AppIntents

struct ResumeTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume cooking timer"
    static var description = IntentDescription("Resumes a paused Recipe Scaler timer.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Timer ID", description: "Optional timer identifier. If omitted, the paused timer is resumed.")
    var timerId: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await TimerManager.configureForIntentIfNeeded()

        guard let id = await resolveTimerId() else {
            return .result(dialog: "There are no paused timers to resume.")
        }

        await TimerManager.shared.resumeTimer(id: id)
        return .result(dialog: "Timer resumed.")
    }

    private func resolveTimerId() async -> String? {
        if let timerId, !timerId.isEmpty {
            return timerId
        }
        return await MainActor.run {
            TimerManager.shared.timers.first { $0.isPaused }?.id
        }
    }
}

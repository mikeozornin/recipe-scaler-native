//
//  TimerLiveActivityIntents.swift
//  RecipeScalerNative
//

import AppIntents
import Foundation

struct PauseRecipeTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause timer"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Timer ID")
    var timerId: String

    init() {
        self.timerId = ""
    }

    init(timerId: String) {
        self.timerId = timerId
    }

    func perform() async throws -> some IntentResult {
        // Spec 030 Phase A: ActivityKit + snapshot + widget reload, then ActionQueue.
        await TimerLiveActivityIntentPerformer.performPause(timerId: timerId)
        return .result()
    }
}

struct ResumeRecipeTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Resume timer"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Timer ID")
    var timerId: String

    init() {
        self.timerId = ""
    }

    init(timerId: String) {
        self.timerId = timerId
    }

    func perform() async throws -> some IntentResult {
        // Spec 030 Phase A: ActivityKit + snapshot + widget reload, then ActionQueue.
        await TimerLiveActivityIntentPerformer.performResume(timerId: timerId)
        return .result()
    }
}

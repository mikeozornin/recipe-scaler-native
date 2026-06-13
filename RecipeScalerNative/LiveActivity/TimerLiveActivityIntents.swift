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
        TimerLiveActivityActionQueue.enqueue(action: .pause, timerId: timerId)
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
        TimerLiveActivityActionQueue.enqueue(action: .resume, timerId: timerId)
        return .result()
    }
}

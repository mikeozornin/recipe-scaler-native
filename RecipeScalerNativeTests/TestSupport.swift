import Foundation
import SwiftData
@testable import RecipeScalerNative

enum TestSupport {
    static func makeInMemoryContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: RecipeTimer.self,
            configurations: config
        )
    }

    /// The test host shares the app's UserDefaults, so timer events queued by a
    /// test (userId is nil there) would be flushed by the next real launch under
    /// the signed-in account. Call from setUp and tearDown of tests that create timers.
    static func clearQueuedTimerSyncEvents() {
        UserDefaults.standard.removeObject(forKey: "timer_sync_state")
    }
}

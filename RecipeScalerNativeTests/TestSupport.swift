import Darwin
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

    /// SwiftUI only exposes `.accessibilityIdentifier` to UIKit tree walks
    /// when accessibility automation is on, which depends on simulator state
    /// (XCUITest turns it on, a fresh simulator has it off). Turns it on once
    /// per test process and restores the simulator setting at exit. Elements
    /// appear asynchronously, so poll for them after layout.
    @MainActor
    static func enableAccessibilityAutomation() {
        guard !accessibilityAutomationEnabled, let api = AccessibilityAutomationAPI.shared else { return }
        accessibilityAutomationEnabled = true
        AccessibilityAutomationAPI.initialValue = api.isEnabled()
        api.setEnabled(1)
        atexit { AccessibilityAutomationAPI.shared?.setEnabled(AccessibilityAutomationAPI.initialValue) }
    }

    @MainActor private static var accessibilityAutomationEnabled = false
}

/// `libAccessibility` automation switch, the same one KIF uses for in-process UI tests.
private struct AccessibilityAutomationAPI {
    let isEnabled: @convention(c) () -> Int32
    let setEnabled: @convention(c) (Int32) -> Void

    nonisolated(unsafe) static var initialValue: Int32 = 0

    static let shared: AccessibilityAutomationAPI? = {
        guard let handle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_LOCAL),
              let get = dlsym(handle, "_AXSAutomationEnabled"),
              let set = dlsym(handle, "_AXSSetAutomationEnabled") else { return nil }
        return AccessibilityAutomationAPI(
            isEnabled: unsafeBitCast(get, to: (@convention(c) () -> Int32).self),
            setEnabled: unsafeBitCast(set, to: (@convention(c) (Int32) -> Void).self)
        )
    }()
}

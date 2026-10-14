import Foundation
import notify
import UIKit
import XCTest

/// Not a check: a tool for `scripts/capture-app-store-screenshots.sh --device ipad-13`
/// (spec 081 T055). `simctl` cannot rotate a simulator, and the Simulator app's Device menu
/// needs Automation access, so landscape App Store shots go through this test.
///
/// XCUIDevice turns only an app that XCTest launched itself: an app started by
/// `simctl launch` keeps the orientation it came up in. So for each orientation pass the test
/// stays running and launches the app for the script. It turns the device, prints
/// `STORE_CAPTURE_ORIENTATION_READY`, then follows the Darwin notification state
/// `ru.recipescaler.debug.store-capture-release` (`simctl spawn <udid> notifyutil -s … n`,
/// then `-p`):
/// - 0 — hold;
/// - 1 — finish: the device goes back to portrait;
/// - n ≥ 2 — launch the app with the arguments and environment from the JSON file
///   `STORE_CAPTURE_LAUNCH_FILE` (`{"arguments": [...], "environment": {...}}`), turn the
///   device, print `STORE_CAPTURE_ORIENTATION_APPLIED n`. The script then takes its shots
///   with `simctl io screenshot`.
///
/// The script passes `STORE_CAPTURE_ORIENTATION=landscape|portrait`, `STORE_CAPTURE_LAUNCH_FILE`
/// and optionally `STORE_CAPTURE_HOLD_SECONDS` (default 3600) and `STORE_CAPTURE_BUNDLE_ID`
/// with the `TEST_RUNNER_` prefix. Without the orientation (any normal test run) the test
/// skips. The data is whatever the script's launch arguments point at (store demo users).
final class StoreScreenshotOrientationSpec: XCTestCase {
    private static let releaseName = "ru.recipescaler.debug.store-capture-release"

    private struct LaunchRequest: Decodable {
        let arguments: [String]
        let environment: [String: String]
    }

    @MainActor
    func testHoldOrientationForStoreCapture() throws {
        let environment = ProcessInfo.processInfo.environment
        let wanted = environment["STORE_CAPTURE_ORIENTATION"] ?? ""
        let orientation: UIDeviceOrientation
        switch wanted {
        case "landscape": orientation = .landscapeLeft
        case "portrait": orientation = .portrait
        default: throw XCTSkip("STORE_CAPTURE_ORIENTATION is not set: only the store capture script runs this")
        }
        let holdSeconds = TimeInterval(environment["STORE_CAPTURE_HOLD_SECONDS"] ?? "") ?? 3600
        let bundleID = environment["STORE_CAPTURE_BUNDLE_ID"] ?? "ru.recipescaler.RecipeScaler"
        let launchFile = environment["STORE_CAPTURE_LAUNCH_FILE"].map(URL.init(fileURLWithPath:))

        var token = NOTIFY_TOKEN_INVALID
        XCTAssertEqual(notify_register_check(Self.releaseName, &token), UInt32(NOTIFY_STATUS_OK))
        defer { notify_cancel(token) }
        notify_set_state(token, 0)

        XCUIDevice.shared.orientation = orientation
        pause(seconds: 1)
        print("STORE_CAPTURE_ORIENTATION_READY \(wanted)")

        let deadline = Date().addingTimeInterval(holdSeconds)
        var state: UInt64 = 0
        var applied: UInt64 = 0
        var tick = 0
        while Date() < deadline {
            notify_get_state(token, &state)
            if state == 1 { break }
            tick += 1
            if tick % 4 == 0 { allowSystemAlert() }
            if state >= 2, state != applied {
                applied = state
                let app = XCUIApplication(bundleIdentifier: bundleID)
                if let launchFile,
                   let data = try? Data(contentsOf: launchFile),
                   let request = try? JSONDecoder().decode(LaunchRequest.self, from: data) {
                    app.launchArguments = request.arguments
                    app.launchEnvironment = request.environment
                    app.launch()
                } else {
                    print("STORE_CAPTURE_LAUNCH_FILE unreadable: \(launchFile?.path ?? "not set")")
                    app.activate()
                }
                turn(app, to: orientation)
                let frame = app.windows.firstMatch.frame
                print("STORE_CAPTURE_ORIENTATION_APPLIED \(state) window=\(Int(frame.width))x\(Int(frame.height))")
            }
            pause(seconds: 0.3)
        }
        // The runner does not always put the device back: leave it in portrait for the next pass.
        XCUIDevice.shared.orientation = .portrait
        pause(seconds: 1)
        print("STORE_CAPTURE_ORIENTATION_RELEASED \(wanted) state=\(state)")
    }

    /// The app asks for notifications when a timer starts (02-cooking); a fresh install by
    /// XCTest has no answer yet. The capture script's AppleScript fallback needs Automation
    /// access, so the test answers «Allow» itself.
    @MainActor
    private func allowSystemAlert() {
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        guard alert.exists else { return }
        for label in ["Allow", "Разрешить"] where alert.buttons[label].exists {
            alert.buttons[label].tap()
            print("STORE_CAPTURE_ALERT_ALLOWED \(label)")
            return
        }
    }

    /// Setting the orientation the device already has does not turn a freshly launched app:
    /// go the other way first, then wait until the window has the wanted shape.
    @MainActor
    private func turn(_ app: XCUIApplication, to orientation: UIDeviceOrientation) {
        let wantsLandscape = orientation.isLandscape
        func turned() -> Bool {
            let frame = app.windows.firstMatch.frame
            return frame.width > 0 && wantsLandscape == (frame.width > frame.height)
        }
        for attempt in 0..<3 {
            if attempt > 0 || !turned() {
                XCUIDevice.shared.orientation = wantsLandscape ? .portrait : .landscapeLeft
                pause(seconds: 1)
            }
            XCUIDevice.shared.orientation = orientation
            for _ in 0..<10 where !turned() { pause(seconds: 0.5) }
            if turned() { return }
        }
        print("STORE_CAPTURE_ORIENTATION_NOT_TURNED \(orientation.rawValue)")
    }

    @MainActor
    private func pause(seconds: TimeInterval) {
        let tick = expectation(description: "pause")
        tick.isInverted = true
        wait(for: [tick], timeout: seconds)
    }
}

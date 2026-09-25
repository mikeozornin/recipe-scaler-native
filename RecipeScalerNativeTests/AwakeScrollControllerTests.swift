import XCTest
@testable import RecipeScalerNative

@MainActor
final class AwakeScrollControllerTests: XCTestCase {
    private func armedFlags(voice: Bool = true, hand: Bool = false, face: Bool = false) -> AwakeScrollArmFlags {
        AwakeScrollArmFlags(
            recipeId: "r1",
            detailVisible: true,
            isScreenAwakeActive: true,
            voiceEnabled: voice,
            handEnabled: hand,
            faceEnabled: face,
            cookingPresented: false,
            assistantSheetOpen: false
        )
    }

    private func makeController(
        permissions: AwakeScrollPermissionSnapshot = AwakeScrollPermissionSnapshot(
            micGranted: true,
            speechGranted: true,
            cameraGranted: false
        )
    ) -> AwakeScrollController {
        let controller = AwakeScrollController()
        controller.startsRealEngines = false
        controller.writesStorage = false
        controller.permissionRequester = { _, _ in permissions }
        return controller
    }

    func test_predicate_false_teardown() async {
        let controller = makeController()
        var started = 0
        var stopped = 0
        controller.onStartChannels = { _, _ in started += 1 }
        controller.onStopChannels = { stopped += 1 }
        controller.flags = armedFlags()
        controller.syncArmState()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(started, 1)
        controller.flags.voiceEnabled = false
        controller.syncArmState()
        XCTAssertEqual(stopped, 1)
        XCTAssertGreaterThan(controller.sessionEpoch, 0)
    }

    func test_hands_free_off_keeps_awake() async {
        let suite = UserDefaults(suiteName: "awake-scroll-test-\(UUID().uuidString)")!
        AwakeHandsFreeStorage.defaults = suite
        defer { AwakeHandsFreeStorage.defaults = .standard }
        AwakeHandsFreeStorage.voiceEnabled = true
        let controller = makeController()
        controller.flags = armedFlags()
        controller.syncArmState()
        try? await Task.sleep(nanoseconds: 50_000_000)
        controller.flags.voiceEnabled = false
        controller.syncArmState()
        XCTAssertTrue(controller.flags.isScreenAwakeActive)
        XCTAssertTrue(AwakeHandsFreeStorage.voiceEnabled)
    }

    func test_awake_off_teardown() async {
        let suite = UserDefaults(suiteName: "awake-scroll-awake-off-\(UUID().uuidString)")!
        AwakeHandsFreeStorage.defaults = suite
        defer { AwakeHandsFreeStorage.defaults = .standard }
        AwakeHandsFreeStorage.voiceEnabled = true
        let controller = makeController()
        var stopped = 0
        controller.onStopChannels = { stopped += 1 }
        controller.flags = armedFlags()
        controller.syncArmState()
        try? await Task.sleep(nanoseconds: 50_000_000)
        controller.flags.isScreenAwakeActive = false
        controller.syncArmState()
        XCTAssertEqual(stopped, 1)
        XCTAssertTrue(AwakeHandsFreeStorage.voiceEnabled)
    }

    func test_cooking_cover_disarm() async {
        let controller = makeController()
        var stopped = 0
        controller.onStopChannels = { stopped += 1 }
        controller.flags = armedFlags()
        controller.syncArmState()
        try? await Task.sleep(nanoseconds: 50_000_000)
        controller.flags.cookingPresented = true
        controller.syncArmState()
        XCTAssertEqual(stopped, 1)
        XCTAssertTrue(controller.flags.voiceEnabled)
    }

    func test_stale_permission_ignored() async {
        let controller = makeController()
        controller.permissionRequester = { _, _ in
            try? await Task.sleep(nanoseconds: 80_000_000)
            return AwakeScrollPermissionSnapshot(
                micGranted: true,
                speechGranted: true,
                cameraGranted: false
            )
        }
        var started = 0
        controller.onStartChannels = { _, _ in started += 1 }
        controller.flags = armedFlags()
        controller.syncArmState()
        controller.flags.voiceEnabled = false
        controller.syncArmState()
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(started, 0)
    }

    func test_both_denied_no_camera_modality() async {
        let controller = makeController(permissions: .denied)
        controller.flags = armedFlags()
        controller.syncArmState()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(controller.cameraModality, .none)
        XCTAssertFalse(controller.flags.voiceEnabled)
        XCTAssertEqual(controller.channelStartCount, 0)
    }

    func test_recipe_leave_stops() async {
        let controller = makeController()
        var stopped = 0
        controller.onStopChannels = { stopped += 1 }
        controller.flags = armedFlags()
        controller.syncArmState()
        try? await Task.sleep(nanoseconds: 50_000_000)
        controller.flags.detailVisible = false
        controller.flags.recipeId = "r2"
        controller.syncArmState()
        XCTAssertEqual(stopped, 1)
    }

    func test_stale_epoch_ignores_apply() {
        let controller = makeController()
        controller.flags = armedFlags()
        let old = controller.sessionEpoch
        controller.stop(reason: "test")
        controller.handleAction(.down, epoch: old, channel: .voice)
        XCTAssertNil(controller.lastAppliedEpoch)
        XCTAssertNil(controller.lastPulseByChannel[.voice])
    }

    func test_pulse_without_probe() {
        let controller = makeController()
        controller.flags = armedFlags()
        controller.handleAction(.down, epoch: controller.sessionEpoch, channel: .voice, phrase: "вниз")
        XCTAssertNotNil(controller.lastPulseByChannel[.voice])
        XCTAssertEqual(controller.lastVoiceChip, .down)
        XCTAssertEqual(controller.lastActionByChannel[.voice], .down)
        controller.handleAction(.up, epoch: controller.sessionEpoch, channel: .face)
        XCTAssertNotNil(controller.lastPulseByChannel[.face])
        XCTAssertEqual(controller.lastActionByChannel[.face], .up)
        controller.handleAction(.down, epoch: controller.sessionEpoch, channel: .hand)
        XCTAssertNotNil(controller.lastPulseByChannel[.hand])
        XCTAssertEqual(controller.lastActionByChannel[.hand], .down)
    }

    func test_help_sheet_does_not_disarm_flags() {
        let flags = armedFlags()
        XCTAssertTrue(flags.isArmed)
    }

    func test_hand_xor_disables_face() {
        let suite = UserDefaults(suiteName: "awake-xor-hand-\(UUID().uuidString)")!
        AwakeHandsFreeStorage.defaults = suite
        defer { AwakeHandsFreeStorage.defaults = .standard }
        suite.set(true, forKey: AwakeHandsFreeStorage.migrationKey)
        AwakeHandsFreeStorage.setFaceEnabled(true)
        AwakeHandsFreeStorage.setHandEnabled(true)
        XCTAssertTrue(AwakeHandsFreeStorage.handEnabled)
        XCTAssertFalse(AwakeHandsFreeStorage.faceEnabled)
    }

    func test_face_xor_disables_hand() {
        let suite = UserDefaults(suiteName: "awake-xor-face-\(UUID().uuidString)")!
        AwakeHandsFreeStorage.defaults = suite
        defer { AwakeHandsFreeStorage.defaults = .standard }
        suite.set(true, forKey: AwakeHandsFreeStorage.migrationKey)
        AwakeHandsFreeStorage.setHandEnabled(true)
        AwakeHandsFreeStorage.setFaceEnabled(true)
        XCTAssertTrue(AwakeHandsFreeStorage.faceEnabled)
        XCTAssertFalse(AwakeHandsFreeStorage.handEnabled)
    }

    func test_mic_denied_snaps_voice_off() async {
        let suite = UserDefaults(suiteName: "awake-snap-\(UUID().uuidString)")!
        AwakeHandsFreeStorage.defaults = suite
        defer { AwakeHandsFreeStorage.defaults = .standard }
        suite.set(true, forKey: AwakeHandsFreeStorage.migrationKey)
        AwakeHandsFreeStorage.voiceEnabled = true
        let controller = makeController(permissions: .denied)
        controller.writesStorage = true
        controller.flags = armedFlags()
        controller.syncArmState()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(controller.flags.voiceEnabled)
        XCTAssertFalse(AwakeHandsFreeStorage.voiceEnabled)
    }

    func test_migrates_legacy_hands_free_to_voice_and_hand() {
        let suite = UserDefaults(suiteName: "awake-mig-\(UUID().uuidString)")!
        AwakeHandsFreeStorage.defaults = suite
        defer { AwakeHandsFreeStorage.defaults = .standard }
        suite.set(true, forKey: AwakeHandsFreeStorage.legacyKey)
        AwakeHandsFreeStorage.migrateIfNeeded(trueDepthAvailable: false)
        XCTAssertTrue(AwakeHandsFreeStorage.voiceEnabled)
        XCTAssertTrue(AwakeHandsFreeStorage.handEnabled)
        XCTAssertFalse(AwakeHandsFreeStorage.faceEnabled)
    }

    func test_migrates_legacy_hands_free_to_voice_and_face() {
        let suite = UserDefaults(suiteName: "awake-mig-face-\(UUID().uuidString)")!
        AwakeHandsFreeStorage.defaults = suite
        defer { AwakeHandsFreeStorage.defaults = .standard }
        suite.set(true, forKey: AwakeHandsFreeStorage.legacyKey)
        AwakeHandsFreeStorage.migrateIfNeeded(trueDepthAvailable: true)
        XCTAssertTrue(AwakeHandsFreeStorage.voiceEnabled)
        XCTAssertFalse(AwakeHandsFreeStorage.handEnabled)
        XCTAssertTrue(AwakeHandsFreeStorage.faceEnabled)
    }

    func test_voice_only_no_camera_request() async {
        var requestedCamera = false
        let controller = makeController()
        controller.permissionRequester = { voice, camera in
            requestedCamera = camera
            XCTAssertTrue(voice)
            return AwakeScrollPermissionSnapshot(
                micGranted: true,
                speechGranted: true,
                cameraGranted: false
            )
        }
        controller.flags = armedFlags(voice: true)
        controller.syncArmState()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(requestedCamera)
        XCTAssertEqual(controller.cameraModality, .none)
        XCTAssertEqual(controller.channelStartCount, 1)
    }

    func test_locale_change_restarts_voice() async {
        let controller = makeController()
        var started = 0
        var stopped = 0
        controller.onStartChannels = { _, _ in started += 1 }
        controller.onStopChannels = { stopped += 1 }
        controller.flags = armedFlags(voice: true)
        controller.syncArmState()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(started, 1)
        controller.restartVoiceForLocaleChange()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(stopped, 1)
        XCTAssertEqual(started, 2)
    }

    func test_granted_snapshot_after_denied_reenables_toggles() {
        let controller = makeController()
        controller.applyPermissionSnapshot(.denied)
        XCTAssertTrue(controller.lastPermissions.voiceDenied)
        XCTAssertTrue(controller.lastPermissions.showsOpenSettings)
        controller.applyPermissionSnapshot(
            AwakeScrollPermissionSnapshot(
                micGranted: true,
                speechGranted: true,
                cameraGranted: true
            )
        )
        XCTAssertFalse(controller.lastPermissions.voiceDenied)
        XCTAssertFalse(controller.lastPermissions.showsOpenSettings)
    }

    func test_shows_open_settings_includes_speech_denied() {
        let snapshot = AwakeScrollPermissionSnapshot(
            micGranted: true,
            speechGranted: false,
            cameraGranted: true,
            speechDenied: true
        )
        XCTAssertTrue(snapshot.voiceDenied)
        XCTAssertTrue(snapshot.showsOpenSettings)
    }

    func test_reconfigure_during_in_flight_start() async {
        let controller = makeController()
        controller.prefersTrueDepthFace = { false }
        controller.permissionRequester = { _, _ in
            try? await Task.sleep(nanoseconds: 80_000_000)
            return AwakeScrollPermissionSnapshot(
                micGranted: true,
                speechGranted: true,
                cameraGranted: true
            )
        }
        controller.flags = armedFlags(voice: true, hand: false)
        controller.syncArmState()
        controller.flags.handEnabled = true
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(controller.channelStartCount, 1)
        XCTAssertEqual(controller.cameraModality, .hand)
    }

    func test_partial_engine_start_failure_does_not_hot_loop() async {
        let suite = UserDefaults(suiteName: "awake-partial-start-\(UUID().uuidString)")!
        AwakeHandsFreeStorage.defaults = suite
        defer { AwakeHandsFreeStorage.defaults = .standard }
        suite.set(true, forKey: AwakeHandsFreeStorage.migrationKey)
        AwakeHandsFreeStorage.voiceEnabled = true
        AwakeHandsFreeStorage.setHandEnabled(true)

        let controller = makeController(
            permissions: AwakeScrollPermissionSnapshot(
                micGranted: true,
                speechGranted: true,
                cameraGranted: true
            )
        )
        controller.writesStorage = true
        controller.prefersTrueDepthFace = { false }
        controller.voiceStartResult = false
        controller.cameraStartResult = true
        controller.flags = armedFlags(voice: true, hand: true)
        controller.syncArmState()
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(controller.channelStartCount, 1)
        XCTAssertFalse(controller.flags.voiceEnabled)
        XCTAssertFalse(AwakeHandsFreeStorage.voiceEnabled)
        XCTAssertEqual(controller.cameraModality, .hand)
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(controller.channelStartCount, 1)
        XCTAssertEqual(controller.channelStopCount, 0)
    }

    func test_voice_off_keeps_hand_camera() async {
        let controller = makeController(
            permissions: AwakeScrollPermissionSnapshot(
                micGranted: true,
                speechGranted: true,
                cameraGranted: true
            )
        )
        controller.prefersTrueDepthFace = { false }
        var stopped = 0
        controller.onStopChannels = { stopped += 1 }
        controller.flags = armedFlags(voice: true, hand: true)
        controller.syncArmState()
        try? await Task.sleep(nanoseconds: 50_000_000)
        let epoch = controller.sessionEpoch
        XCTAssertEqual(controller.cameraModality, .hand)
        XCTAssertEqual(controller.channelStartCount, 1)
        controller.flags.voiceEnabled = false
        controller.syncArmState()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(stopped, 0)
        XCTAssertEqual(controller.channelStopCount, 0)
        XCTAssertEqual(controller.cameraModality, .hand)
        XCTAssertEqual(controller.sessionEpoch, epoch)
        XCTAssertEqual(controller.channelStartCount, 1)
    }

    func test_locale_change_keeps_hand_camera() async {
        let controller = makeController(
            permissions: AwakeScrollPermissionSnapshot(
                micGranted: true,
                speechGranted: true,
                cameraGranted: true
            )
        )
        controller.prefersTrueDepthFace = { false }
        var stopped = 0
        controller.onStopChannels = { stopped += 1 }
        controller.flags = armedFlags(voice: true, hand: true)
        controller.syncArmState()
        try? await Task.sleep(nanoseconds: 50_000_000)
        let epoch = controller.sessionEpoch
        controller.restartVoiceForLocaleChange()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(stopped, 0)
        XCTAssertEqual(controller.cameraModality, .hand)
        XCTAssertEqual(controller.sessionEpoch, epoch)
        XCTAssertEqual(controller.channelStartCount, 2)
    }

    func test_restricted_speech_does_not_snap_voice_pref() async {
        let controller = makeController(
            permissions: AwakeScrollPermissionSnapshot(
                micGranted: true,
                speechGranted: false,
                cameraGranted: false,
                speechRestricted: true
            )
        )
        controller.flags = armedFlags(voice: true)
        controller.syncArmState()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(controller.flags.voiceEnabled)
        XCTAssertEqual(controller.channelStartCount, 0)
        XCTAssertFalse(controller.lastPermissions.showsOpenSettings)
        XCTAssertTrue(controller.lastPermissions.voiceBlocked)
    }

    func test_awake_scroll_selectors_are_mirrored_in_ui_tests() throws {
        let testsRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let selectors = try String(
            contentsOf: testsRoot.appendingPathComponent("RecipeScalerNativeUITests/Helpers/Selectors.swift"),
            encoding: .utf8
        )
        let ids = [
            AccessibilityIdentifiers.screenAwakeBannerMenu,
            AccessibilityIdentifiers.screenAwakeBannerIconVoice,
            AccessibilityIdentifiers.screenAwakeBannerIconHand,
            AccessibilityIdentifiers.screenAwakeBannerIconFace,
            AccessibilityIdentifiers.screenAwakeVoiceToggle,
            AccessibilityIdentifiers.screenAwakeHandToggle,
            AccessibilityIdentifiers.screenAwakeFaceToggle,
            AccessibilityIdentifiers.screenAwakeOpenSettings,
            AccessibilityIdentifiers.screenAwakeHelpTitle,
            AccessibilityIdentifiers.screenAwakeHelpIconHandUp,
            AccessibilityIdentifiers.screenAwakeHelpIconHandDown,
            AccessibilityIdentifiers.screenAwakeHelpIconFaceUp,
            AccessibilityIdentifiers.screenAwakeHelpIconFaceDown,
        ]
        for id in ids {
            XCTAssertTrue(selectors.contains("\"\(id)\""), "missing UI-test mirror for \(id)")
        }
        XCTAssertTrue(
            selectors.contains("screen_awake_help_chip_"),
            "missing UI-test mirror for voice chips"
        )
    }

    func test_stopIfViewRemoved_stops_channels_and_drops_callback() async {
        let controller = makeController()
        controller.flags = armedFlags()
        controller.syncArmState()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertGreaterThan(controller.channelStartCount, 0)
        let stopsBefore = controller.channelStopCount
        controller.onChannelPrefsChanged = {}
        controller.stopIfViewRemoved()
        XCTAssertGreaterThan(controller.channelStopCount, stopsBefore)
        XCTAssertNil(controller.onChannelPrefsChanged)
        XCTAssertFalse(controller.flags.detailVisible)
    }
}

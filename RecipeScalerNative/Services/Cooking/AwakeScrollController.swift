import Foundation
import UIKit

/// Weak UIScrollView port for hands-free deltas. Lives in Services so the
/// controller does not import a Views type; the SwiftUI probe stays in Views.
final class DetailScrollViewProbeBox {
    weak var host: UIScrollView?
}

@MainActor
@Observable
final class AwakeScrollController {
    var flags = AwakeScrollArmFlags()
    private(set) var sessionEpoch: UInt64 = 0
    private(set) var isStarting = false
    private(set) var lastAppliedEpoch: UInt64?
    private(set) var lastPermissions = AwakeScrollPermissionSnapshot.unknown
    private(set) var cameraModality: AwakeScrollCameraModality = .none
    private(set) var channelStartCount = 0
    private(set) var channelStopCount = 0
    private(set) var lastPulseByChannel: [AwakeScrollInputChannel: Date] = [:]
    private(set) var lastActionByChannel: [AwakeScrollInputChannel: AwakeScrollAction] = [:]
    private(set) var lastVoiceChip: AwakeScrollVoiceChip?

    var cooldown: TimeInterval = 0.6
    var now: () -> Date = { Date() }
    var prefersTrueDepthFace: () -> Bool = {
        AwakeScrollCaptureSession.supportsFaceTracking
    }
    var speechLocale: () -> Locale = {
        AwakeScrollVoiceEngine.recognizerLocale(for: AppLanguagePreference.current)
    }
    var permissionRequester: (_ voice: Bool, _ camera: Bool) async -> AwakeScrollPermissionSnapshot = {
        await AwakeScrollPermissions.request(voice: $0, camera: $1)
    }
    var onStartChannels: ((UInt64, AwakeScrollPermissionSnapshot) -> Void)?
    var onStopChannels: (() -> Void)?
    var onChannelPrefsChanged: (() -> Void)?
    var startsRealEngines = true
    var writesStorage = true
    /// Test seams mirroring `startsRealEngines`: force a channel's engine
    /// start result to simulate partial failures (reconfigure-loop tests).
    var voiceStartResult: Bool?
    var cameraStartResult: Bool?

    let probe = DetailScrollViewProbeBox()
    let voiceEngine = AwakeScrollVoiceEngine()
    let captureSession = AwakeScrollCaptureSession()

    private var cooldownUntil: Date?
    private var channelsRunning = false
    private var runningVoice = false
    private var runningModality: AwakeScrollCameraModality = .none
    private var startID: UInt64 = 0

    var showsFaceChannel: Bool { prefersTrueDepthFace() }

    func isChannelArmed(_ channel: AwakeScrollInputChannel) -> Bool {
        guard flags.isBaseArmed else { return false }
        switch channel {
        case .voice:
            return flags.voiceEnabled && lastPermissions.micGranted && lastPermissions.speechGranted
        case .hand:
            return lastPermissions.cameraGranted && cameraModality == .hand
        case .face:
            return lastPermissions.cameraGranted && cameraModality == .face
        }
    }

    func refreshPermissions() {
        lastPermissions = AwakeScrollPermissions.currentSnapshot()
    }

    func applyPermissionSnapshot(_ snapshot: AwakeScrollPermissionSnapshot) {
        lastPermissions = snapshot
    }

    func notePulse(
        _ channel: AwakeScrollInputChannel,
        action: AwakeScrollAction,
        chip: AwakeScrollVoiceChip? = nil
    ) {
        var next = lastPulseByChannel
        next[channel] = now()
        lastPulseByChannel = next
        var actions = lastActionByChannel
        actions[channel] = action
        lastActionByChannel = actions
        if channel == .voice, let chip {
            lastVoiceChip = chip
        }
    }

    func handleAction(
        _ action: AwakeScrollAction,
        epoch: UInt64,
        channel: AwakeScrollInputChannel,
        phrase: String? = nil
    ) {
        guard epoch == sessionEpoch else { return }
        let chip = phrase.flatMap { AwakeScrollVoiceClassifier.chip(from: $0) }
        notePulse(channel, action: action, chip: chip)
        guard flags.isArmed else { return }
        let instant = now()
        if let cooldownUntil, instant < cooldownUntil { return }
        apply(action)
        lastAppliedEpoch = epoch
        cooldownUntil = instant.addingTimeInterval(cooldown)
    }

    func restartVoiceForLocaleChange() {
        guard flags.wantsVoice else { return }
        stopVoice(reason: "speech_locale")
        syncArmState()
    }

    func apply(_ action: AwakeScrollAction) {
        guard flags.isArmed else { return }
        guard let scrollView = probe.host else {
            AppLog.debug(.gesture, "awake_scroll_probe_missing")
            return
        }
        let viewport = AwakeScrollViewport(
            boundsHeight: scrollView.bounds.height,
            contentHeight: scrollView.contentSize.height,
            adjustedInsetTop: scrollView.adjustedContentInset.top,
            adjustedInsetBottom: scrollView.adjustedContentInset.bottom,
            contentOffsetY: scrollView.contentOffset.y
        )
        let y = AwakeScrollEngine.offsetY(action: action, viewport: viewport)
        guard abs(y - scrollView.contentOffset.y) >= 0.5 else { return }
        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: y),
            animated: true
        )
    }

    /// Detail left the hierarchy (including a pop that raced a help sheet).
    /// Drops the prefs callback and disarms so a later sheet `onDismiss`
    /// cannot restart the camera or mic.
    func stopIfViewRemoved() {
        onChannelPrefsChanged = nil
        flags.detailVisible = false
        syncArmState()
    }

    func syncArmState() {
        let wantVoice = effectiveWantVoice()
        let wantModality = effectiveWantModality()
        if !wantVoice, wantModality == .none {
            stop(reason: "disarmed")
            return
        }
        if runningVoice == wantVoice, runningModality == wantModality {
            return
        }
        if runningVoice, !wantVoice {
            stopVoice(reason: "voice_off")
        }
        if runningModality != .none, runningModality != wantModality {
            let reason = wantModality == .none ? "camera_off" : "camera_reconfigure"
            stopCamera(reason: reason)
        }
        if (wantVoice && !runningVoice) || (wantModality != .none && runningModality != wantModality) {
            startIfNeeded()
        }
    }

    func stop(reason: String) {
        let wasRunning = channelsRunning
        tearDownVoice()
        tearDownCamera()
        startID += 1
        isStarting = false
        sessionEpoch += 1
        cooldownUntil = nil
        cameraModality = .none
        runningVoice = false
        runningModality = .none
        channelsRunning = false
        guard wasRunning else { return }
        channelStopCount += 1
        onStopChannels?()
        AppLog.debug(.gesture, "awake_scroll_stop", data: ["reason": reason])
    }

    private func stopVoice(reason: String) {
        let wasLast = runningModality == .none
        let hadVoice = runningVoice || isStarting
        tearDownVoice()
        finishChannelStop(reason: reason, bumpEpoch: wasLast && hadVoice)
    }

    private func stopCamera(reason: String) {
        let wasLast = !runningVoice
        let hadCamera = runningModality != .none || isStarting
        tearDownCamera()
        finishChannelStop(reason: reason, bumpEpoch: wasLast && hadCamera)
    }

    private func tearDownVoice() {
        runningVoice = false
        voiceEngine.stop()
    }

    private func tearDownCamera() {
        runningModality = .none
        cameraModality = .none
        captureSession.stop()
    }

    private func finishChannelStop(reason: String, bumpEpoch: Bool) {
        startID += 1
        isStarting = false
        if bumpEpoch {
            sessionEpoch += 1
            cooldownUntil = nil
        }
        let idle = !runningVoice && runningModality == .none
        guard idle, channelsRunning else { return }
        channelsRunning = false
        channelStopCount += 1
        onStopChannels?()
        AppLog.debug(.gesture, "awake_scroll_stop", data: ["reason": reason])
    }

    private func effectiveWantVoice() -> Bool {
        flags.wantsVoice && !lastPermissions.voiceRestricted
    }

    private func effectiveWantModality() -> AwakeScrollCameraModality {
        guard !lastPermissions.cameraRestricted else { return .none }
        return flags.desiredCameraModality(trueDepthAvailable: prefersTrueDepthFace())
    }

    private func startIfNeeded() {
        let wantVoice = effectiveWantVoice() && !runningVoice
        let wantModality = effectiveWantModality()
        let needCamera = wantModality != .none && runningModality != wantModality
        guard wantVoice || needCamera, !isStarting else { return }
        isStarting = true
        startID += 1
        let thisStart = startID
        let epoch = sessionEpoch
        let requestVoice = wantVoice
        let requestCamera = needCamera
        Task { @MainActor in
            defer {
                if startID == thisStart {
                    isStarting = false
                }
            }
            let permissions = await permissionRequester(requestVoice, requestCamera)
            guard epoch == sessionEpoch, startID == thisStart else { return }
            lastPermissions = permissions
            applyDeniedSnapOff(permissions)
            guard flags.isArmed else { return }
            beginChannels(epoch: epoch, permissions: permissions)
        }
    }

    private func applyDeniedSnapOff(_ permissions: AwakeScrollPermissionSnapshot) {
        var changed = false
        if flags.voiceEnabled, permissions.voiceDenied {
            flags.voiceEnabled = false
            if writesStorage { AwakeHandsFreeStorage.voiceEnabled = false }
            changed = true
        }
        if (flags.handEnabled || flags.faceEnabled), permissions.cameraDenied {
            flags.handEnabled = false
            flags.faceEnabled = false
            if writesStorage {
                AwakeHandsFreeStorage.setHandEnabled(false)
                AwakeHandsFreeStorage.setFaceEnabled(false)
            }
            changed = true
        }
        if changed {
            onChannelPrefsChanged?()
        }
    }

    private func beginChannels(epoch: UInt64, permissions: AwakeScrollPermissionSnapshot) {
        let wantVoice = flags.wantsVoice
            && permissions.micGranted
            && permissions.speechGranted
            && !permissions.voiceRestricted
        let wantModality = flags.desiredCameraModality(trueDepthAvailable: prefersTrueDepthFace())
        let cameraModality: AwakeScrollCameraModality =
            permissions.cameraGranted && !permissions.cameraRestricted ? wantModality : .none
        let addingVoice = wantVoice && !runningVoice
        let addingCamera = cameraModality != .none && runningModality != cameraModality
        guard addingVoice || addingCamera || runningVoice || runningModality != .none else { return }

        var voiceStarted = runningVoice
        if addingVoice {
            voiceStarted = startVoiceChannel(epoch: epoch)
        }
        var cameraStarted = runningModality == cameraModality && cameraModality != .none
        if addingCamera {
            cameraStarted = startCameraChannel(modality: cameraModality, epoch: epoch)
        }
        applyEngineStartFailureSnapOff(
            wantVoice: addingVoice,
            voiceStarted: addingVoice && voiceStarted,
            requestedModality: addingCamera ? cameraModality : .none,
            cameraStarted: addingCamera && cameraStarted
        )
        let nextVoice = addingVoice ? voiceStarted : runningVoice
        let nextModality: AwakeScrollCameraModality = {
            if addingCamera {
                return cameraStarted ? cameraModality : .none
            }
            return runningModality
        }()
        guard nextVoice || nextModality != .none else { return }
        commitRunning(
            voice: nextVoice,
            modality: nextModality,
            epoch: epoch,
            permissions: permissions,
            startedNewChannel: (addingVoice && voiceStarted) || (addingCamera && cameraStarted)
        )
    }

    private func startVoiceChannel(epoch: UInt64) -> Bool {
        if let voiceStartResult { return voiceStartResult }
        guard startsRealEngines else { return true }
        return voiceEngine.start(
            epoch: epoch,
            locale: speechLocale()
        ) { [weak self] action, voiceEpoch, phrase in
            self?.handleAction(action, epoch: voiceEpoch, channel: .voice, phrase: phrase)
        }
    }

    private func startCameraChannel(
        modality: AwakeScrollCameraModality,
        epoch: UInt64
    ) -> Bool {
        if let cameraStartResult { return cameraStartResult }
        guard startsRealEngines else { return true }
        let channel: AwakeScrollInputChannel = modality == .face ? .face : .hand
        return captureSession.start(modality: modality, epoch: epoch) { [weak self] action, captureEpoch in
            self?.handleAction(action, epoch: captureEpoch, channel: channel)
        }
    }

    /// Engine-start failure is not a permission denial, so `applyDeniedSnapOff`
    /// cannot break the post-start `syncArmState` loop. Snap the failed channel
    /// off so `running*` matches `want*` on the trailing re-sync.
    private func applyEngineStartFailureSnapOff(
        wantVoice: Bool,
        voiceStarted: Bool,
        requestedModality: AwakeScrollCameraModality,
        cameraStarted: Bool
    ) {
        var changed = false
        if wantVoice, !voiceStarted {
            flags.voiceEnabled = false
            if writesStorage { AwakeHandsFreeStorage.voiceEnabled = false }
            changed = true
        }
        if requestedModality != .none, !cameraStarted {
            flags.handEnabled = false
            flags.faceEnabled = false
            if writesStorage {
                AwakeHandsFreeStorage.setHandEnabled(false)
                AwakeHandsFreeStorage.setFaceEnabled(false)
            }
            changed = true
        }
        if changed {
            onChannelPrefsChanged?()
        }
    }

    private func commitRunning(
        voice: Bool,
        modality: AwakeScrollCameraModality,
        epoch: UInt64,
        permissions: AwakeScrollPermissionSnapshot,
        startedNewChannel: Bool
    ) {
        let wasRunning = channelsRunning
        channelsRunning = true
        runningVoice = voice
        runningModality = modality
        cameraModality = modality
        if startedNewChannel {
            channelStartCount += 1
            onStartChannels?(epoch, permissions)
        } else if !wasRunning {
            channelStartCount += 1
            onStartChannels?(epoch, permissions)
        }
    }
}

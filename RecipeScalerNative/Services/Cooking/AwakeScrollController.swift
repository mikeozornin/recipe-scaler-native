import Foundation
import UIKit

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
        stop(reason: "speech_locale")
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

    func syncArmState() {
        let wantVoice = flags.wantsVoice
        let wantModality = flags.desiredCameraModality(trueDepthAvailable: prefersTrueDepthFace())
        if !wantVoice, wantModality == .none {
            stop(reason: "disarmed")
            return
        }
        if channelsRunning,
           runningVoice == wantVoice,
           runningModality == wantModality {
            return
        }
        if channelsRunning {
            stop(reason: "reconfigure")
        }
        startIfNeeded()
    }

    func stop(reason: String) {
        sessionEpoch += 1
        startID += 1
        isStarting = false
        cooldownUntil = nil
        cameraModality = .none
        runningVoice = false
        runningModality = .none
        guard channelsRunning else { return }
        channelsRunning = false
        channelStopCount += 1
        voiceEngine.stop()
        captureSession.stop()
        onStopChannels?()
        AppLog.debug(.gesture, "awake_scroll_stop", data: ["reason": reason])
    }

    private func startIfNeeded() {
        let wantVoice = flags.wantsVoice
        let wantModality = flags.desiredCameraModality(trueDepthAvailable: prefersTrueDepthFace())
        guard wantVoice || wantModality != .none, !channelsRunning, !isStarting else { return }
        isStarting = true
        startID += 1
        let thisStart = startID
        let epoch = sessionEpoch
        let requestVoice = wantVoice
        let requestCamera = wantModality != .none
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
            if channelsRunning {
                syncArmState()
            }
        }
    }

    private func applyDeniedSnapOff(_ permissions: AwakeScrollPermissionSnapshot) {
        var changed = false
        if flags.voiceEnabled, !(permissions.micGranted && permissions.speechGranted) {
            flags.voiceEnabled = false
            if writesStorage { AwakeHandsFreeStorage.voiceEnabled = false }
            changed = true
        }
        if (flags.handEnabled || flags.faceEnabled), !permissions.cameraGranted {
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
        let wantVoice = flags.wantsVoice && permissions.micGranted && permissions.speechGranted
        let wantModality = flags.desiredCameraModality(trueDepthAvailable: prefersTrueDepthFace())
        let cameraModality: AwakeScrollCameraModality =
            permissions.cameraGranted ? wantModality : .none
        guard wantVoice || cameraModality != .none else { return }
        guard startsRealEngines else {
            commitRunning(
                voice: wantVoice,
                modality: cameraModality,
                epoch: epoch,
                permissions: permissions
            )
            return
        }
        var voiceStarted = false
        if wantVoice {
            voiceStarted = voiceEngine.start(
                epoch: epoch,
                locale: speechLocale()
            ) { [weak self] action, voiceEpoch, phrase in
                self?.handleAction(action, epoch: voiceEpoch, channel: .voice, phrase: phrase)
            }
        }
        var cameraStarted = false
        if cameraModality != .none {
            let channel: AwakeScrollInputChannel = cameraModality == .face ? .face : .hand
            cameraStarted = captureSession.start(modality: cameraModality, epoch: epoch) { [weak self] action, captureEpoch in
                self?.handleAction(action, epoch: captureEpoch, channel: channel)
            }
        }
        guard voiceStarted || cameraStarted else { return }
        commitRunning(
            voice: voiceStarted,
            modality: cameraStarted ? cameraModality : .none,
            epoch: epoch,
            permissions: permissions
        )
    }

    private func commitRunning(
        voice: Bool,
        modality: AwakeScrollCameraModality,
        epoch: UInt64,
        permissions: AwakeScrollPermissionSnapshot
    ) {
        channelsRunning = true
        runningVoice = voice
        runningModality = modality
        cameraModality = modality
        channelStartCount += 1
        onStartChannels?(epoch, permissions)
    }
}

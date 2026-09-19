import Foundation

struct AwakeScrollArmFlags: Equatable, Sendable {
    var recipeId: String = ""
    var detailVisible: Bool = false
    var isScreenAwakeActive: Bool = false
    var voiceEnabled: Bool = false
    var handEnabled: Bool = false
    var faceEnabled: Bool = false
    var cookingPresented: Bool = false
    var assistantSheetOpen: Bool = false

    var isAnyChannelEnabled: Bool {
        voiceEnabled || handEnabled || faceEnabled
    }

    var isBaseArmed: Bool {
        detailVisible
            && isScreenAwakeActive
            && !cookingPresented
            && !assistantSheetOpen
    }

    var isArmed: Bool {
        isBaseArmed && isAnyChannelEnabled
    }

    var wantsVoice: Bool {
        isBaseArmed && voiceEnabled
    }

    func desiredCameraModality(trueDepthAvailable: Bool) -> AwakeScrollCameraModality {
        guard isBaseArmed else { return .none }
        if faceEnabled, trueDepthAvailable { return .face }
        if handEnabled { return .hand }
        return .none
    }
}

enum AwakeScrollCameraModality: Equatable, Sendable {
    case none
    case hand
    case face
}

struct AwakeScrollPermissionSnapshot: Equatable, Sendable {
    var micGranted: Bool
    var speechGranted: Bool
    var cameraGranted: Bool
    var micDenied: Bool = false
    var speechDenied: Bool = false
    var cameraDenied: Bool = false

    static let denied = AwakeScrollPermissionSnapshot(
        micGranted: false,
        speechGranted: false,
        cameraGranted: false,
        micDenied: true,
        speechDenied: true,
        cameraDenied: true
    )

    static let unknown = AwakeScrollPermissionSnapshot(
        micGranted: false,
        speechGranted: false,
        cameraGranted: false
    )

    var voiceDenied: Bool { micDenied || speechDenied }
    var showsOpenSettings: Bool { micDenied || cameraDenied }
}

enum AwakeScrollVoiceChip: String, Equatable, CaseIterable, Sendable {
    case up
    case scrollUp
    case down
    case scrollDown

    var localizationKey: String {
        switch self {
        case .up: "recipe.awake-scroll.help.chip.up"
        case .scrollUp: "recipe.awake-scroll.help.chip.scroll-up"
        case .down: "recipe.awake-scroll.help.chip.down"
        case .scrollDown: "recipe.awake-scroll.help.chip.scroll-down"
        }
    }

    var action: AwakeScrollAction {
        switch self {
        case .up, .scrollUp: .up
        case .down, .scrollDown: .down
        }
    }
}

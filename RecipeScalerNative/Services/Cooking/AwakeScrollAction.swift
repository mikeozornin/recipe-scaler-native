import Foundation

enum AwakeScrollAction: Equatable, Sendable {
    case up
    case down
}

enum AwakeScrollInputChannel: Hashable, Sendable {
    case voice
    case hand
    case face
}

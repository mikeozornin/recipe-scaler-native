import Foundation

/// Per-recipe write synchronization state for the detail UI.
enum WriteSyncState: Equatable, Sendable {
    case idle
    case pendingLocal
    case syncing
    case synced
    case queued
    case error(String)
}
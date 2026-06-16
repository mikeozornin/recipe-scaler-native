import Foundation

/// NDJSON debug trace (`/debug` workflow). Filter device logs by `[sync]` or `topic":"sync"`.
/// Compatibility wrapper — delegates to `AppLog`.
enum AgentSyncDebugLog {
    /// Socket.IO connection lifecycle (send these lines when reporting sync bugs).
    static func sync(
        location: String,
        message: String,
        data: [String: String] = [:]
    ) {
        var enriched = data
        enriched["topic"] = "sync"
        write(hypothesisId: "sync", location: location, message: message, data: enriched)
    }

    static func write(
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: String]
    ) {
        #if DEBUG
        guard AgentDebugLogging.isEnabled else { return }
        AppLog.agent(hypothesisId: hypothesisId, location: location, message: message, data: data)
        #endif
    }

    /// On-device NDJSON session log, for export/sharing from the account screen.
    static func sessionLogFileURL() -> URL? {
        AppLog.currentLogFileURL()
    }
}

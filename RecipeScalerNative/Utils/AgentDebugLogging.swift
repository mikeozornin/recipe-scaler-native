import Foundation

/// Master switch for agent NDJSON debug traces (`AgentSyncDebugLog`, …).
///
/// On by default in DEBUG builds. Opt out via scheme env `AGENT_DEBUG_LOG_DISABLED=1`.
/// Optional Cursor ingest: `CURSOR_DEBUG_INGEST_URL`, `CURSOR_DEBUG_SESSION_ID`.
enum AgentDebugLogging {
    #if DEBUG
    static var isEnabled: Bool {
        AppLog.isFileLoggingEnabled
    }

    static var cursorIngestURL: URL? {
        guard isEnabled,
              let raw = ProcessInfo.processInfo.environment["CURSOR_DEBUG_INGEST_URL"],
              let url = URL(string: raw),
              !raw.isEmpty else { return nil }
        return url
    }

    static var cursorSessionId: String {
        ProcessInfo.processInfo.environment["CURSOR_DEBUG_SESSION_ID"] ?? "native-debug"
    }
    #else
    static let isEnabled = false
    static var cursorIngestURL: URL? { nil }
    static let cursorSessionId = ""
    #endif
}

import Foundation
import OSLog

/// NDJSON debug trace for sync/color investigations (`/debug` workflow).
enum AgentSyncDebugLog {
    private static let logger = Logger(subsystem: "com.recipescaler.native", category: "AgentSyncDebug")

    static func write(
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: String]
    ) {
        #if DEBUG
        var payload: [String: Any] = [
            "sessionId": "sync-color-native",
            "location": location,
            "message": message,
            "hypothesisId": hypothesisId,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
        ]
        payload["data"] = data
        guard let json = try? JSONSerialization.data(withJSONObject: payload),
              let line = String(data: json, encoding: .utf8) else { return }
        logger.info("\(line, privacy: .public)")
        appendToSessionFile(line + "\n")
        #endif
    }

    #if DEBUG
    private static var sessionLogURL: URL {
        let env = ProcessInfo.processInfo.environment
        if let override = env["AGENT_DEBUG_LOG"] ?? env["SIMCTL_CHILD_AGENT_DEBUG_LOG"],
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("debug-session.ndjson", isDirectory: false)
    }

    private static func appendToSessionFile(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        let url = sessionLogURL
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: data)
        } else {
            FileManager.default.createFile(atPath: url.path, contents: data)
        }
    }
    #endif
}
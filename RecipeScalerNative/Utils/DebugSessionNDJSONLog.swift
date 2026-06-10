//
//  DebugSessionNDJSONLog.swift
//  Cursor debug session NDJSON (session 9c8634).
//

import Foundation

enum DebugSessionNDJSONLog {
    private static let sessionId = "d125bd"
    private static let logPath = "/Users/mike/work/git-repos/projects/recipe-scaler/recipe-scaler-native/.cursor/debug-d125bd.log"

    static func write(
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: String] = [:],
        runId: String = "pre-fix"
    ) {
        #if DEBUG
        var payload: [String: Any] = [
            "sessionId": sessionId,
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "runId": runId,
        ]
        if !data.isEmpty { payload["data"] = data }
        guard let json = try? JSONSerialization.data(withJSONObject: payload) else { return }
        if let ingest = URL(string: "http://127.0.0.1:7258/ingest/d44036cd-d056-4b6b-9734-275196e613c4") {
            var request = URLRequest(url: ingest)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(sessionId, forHTTPHeaderField: "X-Debug-Session-Id")
            request.httpBody = json
            URLSession.shared.dataTask(with: request).resume()
        }
        AgentSyncDebugLog.write(
            hypothesisId: hypothesisId,
            location: location,
            message: message,
            data: data.merging(["topic": "gesture"]) { _, new in new }
        )
        if let line = String(data: json, encoding: .utf8) {
            let url = URL(fileURLWithPath: logPath)
            let dir = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                if let bytes = (line + "\n").data(using: .utf8) {
                    try? handle.write(contentsOf: bytes)
                }
            } else {
                FileManager.default.createFile(atPath: url.path, contents: (line + "\n").data(using: .utf8))
            }
        }
        #endif
    }
}
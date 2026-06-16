//
//  AssistantPendingActionDebugTrace.swift
//  RecipeScalerNative
//
//  DEBUG NDJSON trace for session 46cef9 — investigates 021 AssistantPendingActionView bugs:
//    1) confirm/cancel buttons missing in live stream (only after re-open)
//    2) user bubble shows raw "confirm_delete" instead of localized "Удалить"
//    3) assistant final answer is empty instead of "Рецепт «…» успешно удален."
//
//  Writes one JSON object per line to .cursor/debug-46cef9.log AND POSTs the same
//  payload to the Cursor ingest endpoint so the harness can pick it up.
//
//  Remove this file after the debug session is closed.
//

import Foundation

enum AssistantPendingActionDebugTrace {
    private static let sessionID = "46cef9"
    private static let logPath =
        "/Users/mike/work/git-repos/projects/recipe-scaler/recipe-scaler-native/.cursor/debug-46cef9.log"
    private static let ingestURLString =
        "http://127.0.0.1:7258/ingest/d44036cd-d056-4b6b-9734-275196e613c4"
    private static let queue = DispatchQueue(label: "debug-logger.46cef9")

    static func write(
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: Any] = [:],
        runId: String = "pre-fix"
    ) {
        let payload: [String: Any] = [
            "sessionId": sessionID,
            "id": "log_\(Int(Date().timeIntervalSince1970 * 1000))_\(UUID().uuidString.prefix(8))",
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "location": location,
            "message": message,
            "data": data,
            "runId": runId,
            "hypothesisId": hypothesisId
        ]
        queue.async {
            Self.appendLine(payload)
            Self.postToIngest(payload: payload)
        }
    }

    // MARK: - JSON helpers (safe lazy conversion)

    /// Best-effort JSON-safe conversion for arbitrary data payloads.
    /// Keeps nested dicts/arrays, stringifies anything else.
    static func jsonSafe(_ value: Any) -> Any {
        if value is NSNull {
            return value
        }
        if let dict = value as? [String: Any] {
            return dict.mapValues { jsonSafe($0) }
        }
        if let arr = value as? [Any] {
            return arr.map { jsonSafe($0) }
        }
        if value is String || value is NSNumber || value is Bool {
            return value
        }
        return String(describing: value)
    }

    private static func appendLine(_ payload: [String: Any]) {
        let safe = (jsonSafe(payload) as? [String: Any]) ?? [:]
        guard let lineData = try? JSONSerialization.data(withJSONObject: safe),
              let line = String(data: lineData, encoding: .utf8) else { return }
        let url = URL(fileURLWithPath: logPath)
        let data = (line + "\n").data(using: .utf8) ?? Data()
        if FileManager.default.fileExists(atPath: logPath) {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        } else {
            let dir = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: url)
        }
    }

    private static func postToIngest(payload: [String: Any]) {
        guard let url = URL(string: ingestURLString) else { return }
        let safe = (jsonSafe(payload) as? [String: Any]) ?? [:]
        guard let body = try? JSONSerialization.data(withJSONObject: safe) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(sessionID, forHTTPHeaderField: "X-Debug-Session-Id")
        request.httpBody = body
        URLSession.shared.dataTask(with: request).resume()
    }
}

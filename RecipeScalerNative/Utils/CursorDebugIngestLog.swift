//
//  CursorDebugIngestLog.swift
//  DEBUG traces via AgentSyncDebugLog (+ optional Cursor ingest when enabled).
//

import Foundation

enum CursorDebugIngestLog {
    static func write(
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: String] = [:],
        runId: String = "pre-fix"
    ) {
        #if DEBUG
        guard AgentDebugLogging.isEnabled else { return }
        var enriched = data
        enriched["debugSessionId"] = AgentDebugLogging.cursorSessionId
        if runId != "pre-fix" {
            enriched["runId"] = runId
        }
        AgentSyncDebugLog.write(
            hypothesisId: hypothesisId,
            location: location,
            message: message,
            data: enriched
        )
        postToCursorIngestIfConfigured(
            hypothesisId: hypothesisId,
            location: location,
            message: message,
            data: enriched,
            runId: runId
        )
        #endif
    }

    #if DEBUG
    private static func postToCursorIngestIfConfigured(
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: String],
        runId: String
    ) {
        guard let url = AgentDebugLogging.cursorIngestURL else { return }
        var payload: [String: Any] = [
            "sessionId": AgentDebugLogging.cursorSessionId,
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "data": data,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
        ]
        if runId != "pre-fix" {
            payload["runId"] = runId
        }
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AgentDebugLogging.cursorSessionId, forHTTPHeaderField: "X-Debug-Session-Id")
        request.httpBody = body
        URLSession.shared.dataTask(with: request).resume()
    }
    #endif

    /// Plain-text fingerprint of an HTML string (works with logging disabled).
    static func fingerprint(_ html: String, prefix keyPrefix: String = "text") -> [String: String] {
        let plain = html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let head = String(plain.prefix(140))
        let tail = String(plain.suffix(140))
        let anchor = String(plain.prefix(40))
        var repeatCount = 0
        if anchor.count >= 8 {
            var search = plain.startIndex
            while let r = plain.range(of: anchor, range: search..<plain.endIndex) {
                repeatCount += 1
                search = r.upperBound
            }
        }
        return [
            "\(keyPrefix)Len": String(plain.count),
            "\(keyPrefix)Head": head,
            "\(keyPrefix)Tail": tail,
            "\(keyPrefix)AnchorRepeat": String(repeatCount),
        ]
    }
}

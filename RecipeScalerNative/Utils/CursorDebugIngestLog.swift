//
//  CursorDebugIngestLog.swift
//  DEBUG traces via AgentSyncDebugLog (simulator: debug-session.ndjson, pull via sim-verify-lib).
//

import Foundation

enum CursorDebugIngestLog {
    private static let debugSessionId = "d19d57"

    static func write(
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: String] = [:],
        runId: String = "pre-fix"
    ) {
        #if DEBUG
        var enriched = data
        enriched["debugSessionId"] = debugSessionId
        if runId != "pre-fix" {
            enriched["runId"] = runId
        }
        AgentSyncDebugLog.write(
            hypothesisId: hypothesisId,
            location: location,
            message: message,
            data: enriched
        )
        #endif
    }

    /// Plain-text fingerprint of an HTML string so we can eyeball *which* content
    /// is present (not just its length). Used to tell stale-read from stale-UI.
    static func fingerprint(_ html: String, prefix keyPrefix: String = "text") -> [String: String] {
        let plain = html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let head = String(plain.prefix(140))
        let tail = String(plain.suffix(140))
        // Duplication detector: how many times does the opening anchor recur in
        // the full text? 1 == normal; N>1 == content multiplied N times on itself.
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

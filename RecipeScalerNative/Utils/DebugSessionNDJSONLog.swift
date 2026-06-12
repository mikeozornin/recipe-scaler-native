//
//  DebugSessionNDJSONLog.swift
//  DEBUG NDJSON traces (gesture / description editor sessions).
//

import Foundation

enum DebugSessionNDJSONLog {
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
        enriched["topic"] = "gesture"
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
}

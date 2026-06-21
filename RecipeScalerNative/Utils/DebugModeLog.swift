//
//  DebugModeLog.swift
//  RecipeScalerNative
//
//  Session-scoped NDJSON instrumentation writer for DEBUG-mode investigation.
//

import Foundation

#if DEBUG
enum DebugModeLog {
    private static let logPath =
        "/Users/mike/work/git-repos/projects/recipe-scaler/recipe-scaler-native/.cursor/debug-4678be.log"
    private static let sessionId = "4678be"
    private static let queue = DispatchQueue(label: "debug-mode-log-4678be")

    static func write(
        _ message: String,
        location: String = #file,
        line: Int = #line,
        function: String = #function,
        hypothesisId: String,
        runId: String = "default",
        data: [String: String] = [:]
    ) {
        let shortFile = (location as NSString).lastPathComponent
        queue.async {
            let payload: [String: Any] = [
                "sessionId": sessionId,
                "id": "log_\(Int(Date().timeIntervalSince1970 * 1000))_\(UUID().uuidString.prefix(8))",
                "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                "location": "\(shortFile):\(line) \(function)",
                "message": message,
                "data": data,
                "runId": runId,
                "hypothesisId": hypothesisId,
            ]
            guard let line = try? JSONSerialization.data(
                withJSONObject: payload,
                options: [.sortedKeys]
            ),
            let lineString = String(data: line, encoding: .utf8) else { return }
            guard let handle = try? FileHandle(
                forWritingTo: URL(fileURLWithPath: logPath)
            ) else {
                FileManager.default.createFile(atPath: logPath, contents: nil)
                guard let handle = try? FileHandle(
                    forWritingTo: URL(fileURLWithPath: logPath)
                ) else { return }
                handle.seekToEndOfFile()
                if let d = lineString.data(using: .utf8) { handle.write(d) }
                if let nl = "\n".data(using: .utf8) { handle.write(nl) }
                try? handle.close()
                return
            }
            handle.seekToEndOfFile()
            if let d = lineString.data(using: .utf8) { handle.write(d) }
            if let nl = "\n".data(using: .utf8) { handle.write(nl) }
            try? handle.close()
        }
    }
}
#endif

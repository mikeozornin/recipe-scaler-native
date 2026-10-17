//
//  AppLog.swift
//  RecipeScalerNative
//
//  Unified logging: NDJSON journal (DEBUG) + os.Logger (all builds).
//

import Foundation
import OSLog

/// Single entry point for app logging. DEBUG builds write NDJSON to Application Support;
/// all builds mirror to Apple unified logging.
enum AppLog {
    enum Category: String, Sendable {
        case app
        case sync
        case document
        case database
        case timer
        case spotlight
        case push
        case gesture
        case agent
        case ui
        case reminders
        case image
    }

    enum Level: String, Sendable {
        case debug
        case info
        case notice
        case error
        case fault
    }

    private static let subsystem = "com.recipescaler.native"
    private static let sessionId = "sync-connection-native"
    private static let logFileName = "debug-session.ndjson"
    private static let maxFileBytes = 5 * 1024 * 1024
    private static let maxArchiveCount = 3

    #if DEBUG
    private static let writeQueue = DispatchQueue(label: "com.recipescaler.native.applog.file")
    #endif

    // MARK: - Public API

    static func debug(
        _ category: Category,
        _ message: String,
        data: [String: String] = [:],
        file: String = #fileID,
        line: Int = #line
    ) {
        emit(level: .debug, category: category, message: message, data: data, file: file, line: line)
    }

    static func info(
        _ category: Category,
        _ message: String,
        data: [String: String] = [:],
        file: String = #fileID,
        line: Int = #line
    ) {
        emit(level: .info, category: category, message: message, data: data, file: file, line: line)
    }

    static func notice(
        _ category: Category,
        _ message: String,
        data: [String: String] = [:],
        file: String = #fileID,
        line: Int = #line
    ) {
        emit(level: .notice, category: category, message: message, data: data, file: file, line: line)
    }

    static func error(
        _ category: Category,
        _ message: String,
        data: [String: String] = [:],
        file: String = #fileID,
        line: Int = #line
    ) {
        emit(level: .error, category: category, message: message, data: data, file: file, line: line)
    }

    static func fault(
        _ category: Category,
        _ message: String,
        data: [String: String] = [:],
        file: String = #fileID,
        line: Int = #line
    ) {
        emit(level: .fault, category: category, message: message, data: data, file: file, line: line)
    }

    /// Agent-compatible NDJSON entry (preserves `hypothesisId` / `location` schema).
    static func agent(
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: String] = [:]
    ) {
        var enriched = data
        enriched["category"] = Category.agent.rawValue
        enriched["level"] = Level.info.rawValue
        mirrorToOSLog(level: .info, category: .agent, message: message, location: location, data: enriched)
        #if DEBUG
        guard isFileLoggingEnabled else { return }
        writeAgentLine(
            hypothesisId: hypothesisId,
            location: location,
            message: message,
            data: enriched
        )
        #endif
    }

    /// Current session log file URL, or `nil` in Release / when file logging is disabled.
    static func currentLogFileURL() -> URL? {
        #if DEBUG
        guard isFileLoggingEnabled else { return nil }
        let url = resolvedLogFileURL()
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
        #else
        return nil
        #endif
    }

    /// Deletes the current NDJSON journal and rotated archives (`.1`…`.N`). No-op in Release.
    static func clearLogFiles() {
        #if DEBUG
        writeQueue.sync {
            let url = resolvedLogFileURL()
            let fm = FileManager.default
            try? fm.removeItem(at: url)
            for index in 1...maxArchiveCount {
                try? fm.removeItem(atPath: "\(url.path).\(index)")
            }
        }
        #endif
    }

    #if DEBUG
    /// Resolved log path (may not exist yet). Used by tests and agent pull helpers.
    static func resolvedLogFileURL() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let override = env["AGENT_DEBUG_LOG"] ?? env["SIMCTL_CHILD_AGENT_DEBUG_LOG"],
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(logFileName, isDirectory: false)
    }

    static var isFileLoggingEnabled: Bool {
        ProcessInfo.processInfo.environment["AGENT_DEBUG_LOG_DISABLED"] != "1"
    }

    /// Rotate when current file exceeds size cap. Exposed for unit tests.
    static func rotateIfNeeded(at url: URL = resolvedLogFileURL()) {
        writeQueue.sync {
            rotateIfNeededUnsynchronized(at: url)
        }
    }

    /// Test hook: write raw line without OSLog (file only).
    static func _testAppendLine(_ line: String, to url: URL = resolvedLogFileURL()) {
        guard isFileLoggingEnabled else { return }
        writeQueue.sync {
            rotateIfNeededUnsynchronized(at: url)
            appendLineUnsynchronized(line + "\n", to: url)
        }
    }
    #endif

    // MARK: - Internals

    private static func emit(
        level: Level,
        category: Category,
        message: String,
        data: [String: String],
        file: String,
        line: Int
    ) {
        var enriched = data
        enriched["category"] = category.rawValue
        enriched["level"] = level.rawValue
        let location = "\(file):\(line)"
        mirrorToOSLog(level: level, category: category, message: message, location: location, data: enriched)
        #if DEBUG
        guard isFileLoggingEnabled else { return }
        writeAgentLine(hypothesisId: category.rawValue, location: location, message: message, data: enriched)
        #endif
    }

    private static func mirrorToOSLog(
        level: Level,
        category: Category,
        message: String,
        location: String,
        data: [String: String]
    ) {
        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        let prefix = data["topic"] == "sync" ? "[sync] " : ""
        let text = "\(prefix)\(message) @ \(location)"
        switch level {
        case .debug:
            logger.debug("\(text, privacy: .private)")
        case .info:
            logger.info("\(text, privacy: .private)")
        case .notice:
            logger.notice("\(text, privacy: .private)")
        case .error:
            logger.error("\(text, privacy: .private)")
        case .fault:
            logger.fault("\(text, privacy: .private)")
        }
    }

    /// Truncate to `maxChars` and collapse newlines/tabs into single spaces
    /// so server strings can't inject multi-line or oversized fragments into log entries.
    static func sanitizeForLog(_ value: String, maxChars: Int = 120) -> String {
        let collapsed = value.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        if collapsed.count <= maxChars { return collapsed }
        return String(collapsed.prefix(maxChars)) + "…"
    }

    #if DEBUG
    private static func writeAgentLine(
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: String]
    ) {
        var payload: [String: Any] = [
            "sessionId": sessionId,
            "location": location,
            "message": message,
            "hypothesisId": hypothesisId,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
        ]
        payload["data"] = data
        guard let json = try? JSONSerialization.data(withJSONObject: payload),
              let line = String(data: json, encoding: .utf8) else { return }
        writeQueue.sync {
            let url = resolvedLogFileURL()
            rotateIfNeededUnsynchronized(at: url)
            appendLineUnsynchronized(line + "\n", to: url)
        }
    }

    private static func rotateIfNeededUnsynchronized(at url: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path),
              let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64,
              size >= maxFileBytes else { return }

        let basePath = url.path
        let oldest = "\(basePath).\(maxArchiveCount)"
        if fm.fileExists(atPath: oldest) {
            try? fm.removeItem(atPath: oldest)
        }
        var index = maxArchiveCount - 1
        while index >= 1 {
            let from = "\(basePath).\(index)"
            let to = "\(basePath).\(index + 1)"
            if fm.fileExists(atPath: from) {
                try? fm.removeItem(atPath: to)
                try? fm.moveItem(atPath: from, toPath: to)
            }
            index -= 1
        }
        let firstArchive = "\(basePath).1"
        try? fm.removeItem(atPath: firstArchive)
        try? fm.moveItem(atPath: basePath, toPath: firstArchive)
    }

    private static func appendLineUnsynchronized(_ line: String, to url: URL) {
        guard let data = line.data(using: .utf8) else { return }
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

/// Launch and navigation milestones for `scripts/measure-perf.sh`. Each milestone logs one
/// unified-log line (category `perf`) and an Instruments signpost, once per process:
/// `perf_mark <name> t=<ms since process start> idle=<ms when the main run loop next went idle>`.
/// `idle` covers the synchronous work queued behind the mark (body, layout, commit).
@MainActor
enum PerfMark {
    private nonisolated static let logger = Logger(subsystem: "com.recipescaler.native", category: "perf")
    private nonisolated static let signposter = OSSignposter(logger: logger)
    private static var reported: Set<String> = []
    private static var intervals: [String: ContinuousClock.Instant] = [:]

    /// Reports `name` the first time it is reached in this process.
    static func once(_ name: String) {
        guard reported.insert(name).inserted else { return }
        let t = millisecondsSinceProcessStart()
        signposter.emitEvent("milestone", "\(name, privacy: .public)")
        whenMainRunLoopIdle { idle in
            logger.notice("perf_mark \(name, privacy: .public) t=\(t, privacy: .public) idle=\(idle, privacy: .public)")
        }
    }

    /// Starts a user-interaction interval, e.g. a tap that opens a recipe. A later `begin` restarts it.
    static func begin(_ name: String) {
        intervals[name] = .now
    }

    /// Ends the interval started by `begin`; no-op when none is running.
    static func end(_ name: String) {
        guard let start = intervals.removeValue(forKey: name) else { return }
        let ms = Int((ContinuousClock.now - start) / .milliseconds(1))
        whenMainRunLoopIdle { _ in
            let idle = Int((ContinuousClock.now - start) / .milliseconds(1))
            logger.notice("perf_interval \(name, privacy: .public) ms=\(ms, privacy: .public) idle=\(idle, privacy: .public)")
        }
    }

    /// Milliseconds since the kernel created this process, so pre-main (dyld) time is included.
    nonisolated static func millisecondsSinceProcessStart() -> Int {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return -1 }
        let start = info.kp_proc.p_un.__p_starttime
        let startSeconds = Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000
        return Int((Date().timeIntervalSince1970 - startSeconds) * 1000)
    }

    private static func whenMainRunLoopIdle(_ report: @escaping @MainActor (Int) -> Void) {
        let observer = CFRunLoopObserverCreateWithHandler(
            nil, CFRunLoopActivity.beforeWaiting.rawValue, false, Int.max
        ) { observer, _ in
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
            MainActor.assumeIsolated { report(millisecondsSinceProcessStart()) }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }
}

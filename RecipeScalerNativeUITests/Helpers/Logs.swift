import Foundation
import XCTest

/// Post-test crash detection from the app's NDJSON debug log.
///
/// Web parity: there's no direct equivalent; on web, Playwright itself
/// surfaces console errors and uncaught exceptions. On native, the app
/// writes a structured NDJSON stream (`debug-session.ndjson`) to its
/// sandbox container. From inside the UI test runner we cannot invoke
/// `xcrun simctl` reliably (Process is not available in the iOS test
/// bundle's process model), so crash detection here is best-effort:
/// we attempt a direct file read via `~/.debug-session.ndjson` (the
/// canonical path the app writes to when running under the simulator's
/// shared container) and skip silently if not found.
///
/// Authoritative crash detection still runs in `scripts/verify-ui-smoke.sh`
/// via `simctl get_app_container` from the host shell — that path is the
/// single source of truth for CI gates.
enum Logs {
    /// Structured crash signatures matched against the JSON payload of NDJSON
    /// log lines. Free-text substring matching (the previous approach) would
    /// false-positive on benign log lines that quote these tokens (e.g. a
    /// stack-trace helper or an error message). See review finding
    /// Performance Medium + Security Medium #7.
    private static let fatalLinePatterns = [
        #""level"\s*:\s*"fatal""#,
        #""level"\s*:\s*"error""#,
    ]

    /// Raw process-level crash signatures. These are kept as plain substring
    /// matches because they come from the OS, not from JSON-encoded log lines.
    private static let crashSignatures = [
        "FatalError",
        "fatalError",
        "Precondition",
        "EXC_BAD_ACCESS",
        "SIGABRT",
        "SIGSEGV",
    ]

    /// Maximum tail size (in bytes) of the NDJSON log we scan. Logs grow
    /// unbounded across tests in a run; scanning the whole file is O(n) per
    /// `tearDown`. See review finding Performance High.
    private static let maxScanBytes = 256 * 1024  // 256 KiB tail

    /// Best-effort crash-detection from NDJSON log. Does not fail if the log
    /// is missing — see class docs for why.
    static func assertNoCrash(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        guard let log = readDebugLog() else { return }
        // OS-level crash signatures: anywhere in the tail.
        for signature in crashSignatures where log.contains(signature) {
            XCTFail("Crash signature '\(signature)' found in app debug log",
                    file: file, line: line)
            return
        }
        // Structured fatal/error log lines: regex against the tail.
        for pattern in fatalLinePatterns {
            if log.range(of: pattern, options: .regularExpression) != nil {
                XCTFail("Fatal/error log line matched pattern '\(pattern)' in app debug log",
                        file: file, line: line)
                return
            }
        }
    }

    /// Try common locations of the app's NDJSON debug log. Returns only the
    /// last `maxScanBytes` tail of the file to keep `tearDown` cost bounded.
    private static func readDebugLog() -> String? {
        let candidates = [
            // Pulled by scripts/pull-app-logs.sh to repo root.
            "/tmp/recipe-scaler-debug-session.ndjson",
            // Sandbox path under the booted simulator (best-effort).
            NSHomeDirectory() + "/Library/Application Support/debug-session.ndjson",
        ]
        for path in candidates {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  !data.isEmpty
            else { continue }
            let scanData = data.count > maxScanBytes
                ? data.suffix(maxScanBytes)
                : data
            return String(data: scanData, encoding: .utf8)
        }
        return nil
    }
}

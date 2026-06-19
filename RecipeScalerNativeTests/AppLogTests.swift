//
//  AppLogTests.swift
//  RecipeScalerNativeTests
//

import XCTest
@testable import RecipeScalerNative

final class AppLogTests: XCTestCase {

    private var tempDir: URL!
    private var logURL: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("applog-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        logURL = tempDir.appendingPathComponent("debug-session.ndjson")
        setenv("AGENT_DEBUG_LOG", logURL.path, 1)
        unsetenv("AGENT_DEBUG_LOG_DISABLED")
    }

    override func tearDownWithError() throws {
        unsetenv("AGENT_DEBUG_LOG")
        unsetenv("AGENT_DEBUG_LOG_DISABLED")
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testResolvedLogFileURLUsesEnvironmentOverride() {
        XCTAssertEqual(AppLog.resolvedLogFileURL().path, logURL.path)
    }

    func testInfoWritesNDJSONLine() {
        AppLog.info(.app, "test_event", data: ["key": "value"])
        let contents = try? String(contentsOf: logURL, encoding: .utf8)
        XCTAssertNotNil(contents)
        XCTAssertTrue(contents?.contains("\"message\":\"test_event\"") == true)
        XCTAssertTrue(contents?.contains("\"category\":\"app\"") == true)
    }

    func testImageCategoryWritesNDJSONLine() {
        AppLog.info(.image, "recipe_image_fetch_failed", data: ["recipeId": "test-id"])
        let contents = try? String(contentsOf: logURL, encoding: .utf8)
        XCTAssertNotNil(contents)
        XCTAssertTrue(contents?.contains("\"message\":\"recipe_image_fetch_failed\"") == true)
        XCTAssertTrue(contents?.contains("\"category\":\"image\"") == true)
    }

    func testAgentWritePreservesHypothesisId() {
        AppLog.agent(hypothesisId: "sync", location: "Test.swift:1", message: "sync_event", data: ["topic": "sync"])
        let contents = try? String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(contents?.contains("\"hypothesisId\":\"sync\"") == true)
        XCTAssertTrue(contents?.contains("\"topic\":\"sync\"") == true)
    }

    func testCurrentLogFileURLNilWhenMissing() {
        XCTAssertNil(AppLog.currentLogFileURL())
    }

    func testCurrentLogFileURLAfterWrite() {
        AppLog.info(.database, "db_open")
        XCTAssertEqual(AppLog.currentLogFileURL()?.path, logURL.path)
    }

    func testRotationCreatesArchiveFiles() {
        let line = String(repeating: "x", count: 1024) + "\n"
        let chunk = String(repeating: line, count: 6000)
        AppLog._testAppendLine(chunk, to: logURL)
        AppLog.rotateIfNeeded(at: logURL)
        let archive = URL(fileURLWithPath: logURL.path + ".1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
    }

    func testDisabledViaEnvironmentSkipsFileWrite() {
        setenv("AGENT_DEBUG_LOG_DISABLED", "1", 1)
        AppLog.info(.app, "should_not_appear")
        XCTAssertFalse(FileManager.default.fileExists(atPath: logURL.path))
    }
}

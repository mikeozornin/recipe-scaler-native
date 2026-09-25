import XCTest
@testable import RecipeScalerNative

final class AwakeScrollVoiceEngineTests: XCTestCase {
    func test_cancelled_url_error_is_ignorable() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCancelled
        )
        XCTAssertTrue(AwakeScrollVoiceEngine.isIgnorableRecognitionError(error))
    }

    func test_speech_task_cancel_code_216_is_ignorable() {
        let error = NSError(domain: "kAFAssistantErrorDomain", code: 216)
        XCTAssertTrue(AwakeScrollVoiceEngine.isIgnorableRecognitionError(error))
    }

    func test_user_cancelled_is_ignorable() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        XCTAssertTrue(AwakeScrollVoiceEngine.isIgnorableRecognitionError(error))
    }

    func test_generic_recognition_error_is_not_ignorable() {
        let error = NSError(domain: "kAFAssistantErrorDomain", code: 203)
        XCTAssertFalse(AwakeScrollVoiceEngine.isIgnorableRecognitionError(error))
    }

    @MainActor
    func test_rotate_without_session_is_noop() {
        let engine = AwakeScrollVoiceEngine()
        XCTAssertEqual(engine.audioEngineBuildCount, 0)
        engine.rotateRecognitionForTesting()
        XCTAssertEqual(engine.audioEngineBuildCount, 0)
        XCTAssertEqual(engine.recognitionTaskCount, 0)
    }

    @MainActor
    func test_final_result_rotates_recognition() {
        let engine = AwakeScrollVoiceEngine()
        engine.testStartSessionResult = true
        XCTAssertTrue(engine.start(epoch: 1, onAction: { _, _, _ in }))
        let before = engine.recognitionTaskCount
        engine.deliverRecognitionResultForTesting(transcript: "вниз", isFinal: false)
        XCTAssertEqual(engine.recognitionTaskCount, before)
        engine.deliverRecognitionResultForTesting(transcript: "вниз", isFinal: true)
        XCTAssertGreaterThan(engine.recognitionTaskCount, before)
        engine.stop()
    }

    @MainActor
    func test_failed_restart_retries_until_start_succeeds() async {
        let engine = AwakeScrollVoiceEngine()
        engine.testRestartDelayOverride = 0.02
        engine.testStartSessionResult = true
        XCTAssertTrue(engine.start(epoch: 1, onAction: { _, _, _ in }))
        engine.testStartSessionResult = false
        engine.failRestartForTesting()
        XCTAssertFalse(engine.isRunning)
        engine.testStartSessionResult = true
        let deadline = Date().addingTimeInterval(1)
        while !engine.isRunning, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(engine.isRunning)
        engine.stop()
    }
}

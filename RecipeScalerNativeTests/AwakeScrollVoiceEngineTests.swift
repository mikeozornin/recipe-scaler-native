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
}

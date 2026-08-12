import XCTest
@testable import RecipeScalerNative

@MainActor
final class AccountFeedbackSubmitTests: XCTestCase {
    func testEmptyMessageCannotSend() {
        let model = AccountFeedbackModel()
        XCTAssertFalse(model.canSend)
        XCTAssertFalse(FeedbackAttachmentLimits.canSend(message: "   "))
        model.message = "hello"
        XCTAssertTrue(model.canSend)
    }

    func testRejectsSixthFile() {
        let model = AccountFeedbackModel()
        let data = Data(repeating: 1, count: 10)
        for index in 0..<5 {
            XCTAssertNil(
                model.addAttachments([
                    FeedbackAttachment(fileName: "\(index).txt", mimeType: "text/plain", data: data)
                ])
            )
        }
        let error = model.addAttachments([
            FeedbackAttachment(fileName: "6.txt", mimeType: "text/plain", data: data)
        ])
        XCTAssertEqual(error, "account.feedback.max-files")
        XCTAssertEqual(model.attachments.count, 5)
    }

    func testRejectsLargeFile() {
        let model = AccountFeedbackModel()
        let data = Data(repeating: 1, count: FeedbackAttachmentLimits.maxBytesPerFile + 1)
        let error = model.addAttachments([
            FeedbackAttachment(fileName: "big.bin", mimeType: "application/octet-stream", data: data)
        ])
        XCTAssertEqual(error, "account.feedback.too-large")
        XCTAssertTrue(model.attachments.isEmpty)
    }

    func testSingleFlight() async {
        let model = AccountFeedbackModel()
        model.message = "hello"
        var started = 0
        model.submitHandler = { _, _ in
            started += 1
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        async let first = model.submit(isOnline: true, isAuthenticated: true)
        try? await Task.sleep(nanoseconds: 20_000_000)
        async let second = model.submit(isOnline: true, isAuthenticated: true)
        _ = await (first, second)
        XCTAssertEqual(started, 1)
        XCTAssertEqual(model.message, "")
    }

    func testStaleCompletionDoesNotClear() async {
        let model = AccountFeedbackModel()
        model.message = "hello"
        model.submitHandler = { _, _ in
            try await Task.sleep(nanoseconds: 80_000_000)
        }
        let task = Task {
            await model.submit(isOnline: true, isAuthenticated: true)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
        model.bumpGeneration()
        let ok = await task.value
        XCTAssertFalse(ok)
        XCTAssertEqual(model.message, "hello")
    }

    func testOfflineDoesNotSubmit() async {
        let model = AccountFeedbackModel()
        model.message = "hello"
        var started = 0
        model.submitHandler = { _, _ in started += 1 }
        let ok = await model.submit(isOnline: false, isAuthenticated: true)
        XCTAssertFalse(ok)
        XCTAssertEqual(started, 0)
    }
}

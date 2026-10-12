//
//  AssistantSessionModelTests.swift
//
//  Spec 081 (T032a) — the shared assistant session: a panel ↔ sheet swap keeps
//  the chat, the draft and the stream; close / logout / session epoch drop it.
//  No network: every call goes through an in-memory fake client.
//

import XCTest
@testable import RecipeScalerNative

@MainActor
final class AssistantSessionModelTests: XCTestCase {

    // MARK: - Swap (the other presentation appears without a close)

    func testDraftSurvivesViewSwap() async {
        let backend = FakeAssistantBackend()
        let model = backend.makeModel()
        await openAndBootstrap(model, backend: backend)

        model.input = "Черновик вопроса"
        model.attachments = [
            AssistantRecipeAttachment(recipeId: "r1", recipeName: "Борщ", recipeColor: nil)
        ]
        // Regular → compact: the panel goes away, the sheet appears.
        model.viewDidAppear(shakeRequest: nil)
        await settle()

        XCTAssertEqual(model.input, "Черновик вопроса")
        XCTAssertEqual(model.attachments.map(\.recipeId), ["r1"])
        XCTAssertEqual(backend.listThreadsCalls, 1, "a swap must not bootstrap the chat again")
    }

    func testInFlightStreamSurvivesViewSwap() async {
        let backend = FakeAssistantBackend()
        let model = backend.makeModel()
        await openAndBootstrap(model, backend: backend)

        model.input = "Как спасти соус?"
        model.launchSend()
        await waitUntil { backend.continuation != nil }
        backend.continuation?.yield(.textDelta("Сними"))
        await waitUntil { model.messages.last?.text == "Сними" }

        model.viewDidAppear(shakeRequest: nil)
        backend.continuation?.yield(.textDelta(" с огня"))
        await waitUntil { model.messages.last?.text == "Сними с огня" }

        XCTAssertFalse(backend.streamTerminated, "a swap must not cancel the stream")
        XCTAssertEqual(model.messages.map(\.role), ["user", "assistant"])
        XCTAssertTrue(model.isSending)

        backend.continuation?.finish()
        await waitUntil { !model.isSending }
        XCTAssertEqual(backend.streamCalls.count, 1)
    }

    func testExternalRequestIsNotResentOnViewSwap() async {
        let backend = FakeAssistantBackend()
        let model = backend.makeModel()
        model.beginPresentation(
            openRequest: AssistantOpenRequest(requestId: 7, message: "Подбери гарнир"),
            shakeRequest: nil
        )
        model.viewDidAppear(shakeRequest: nil)
        await waitUntil { backend.streamCalls.count == 1 }

        model.viewDidAppear(shakeRequest: nil)
        await settle()

        XCTAssertEqual(backend.streamCalls.map(\.message), ["Подбери гарнир"])
    }

    // MARK: - Close / reopen (iPhone behavior unchanged)

    func testCloseCancelsStream() async {
        let backend = FakeAssistantBackend()
        let model = backend.makeModel()
        await openAndBootstrap(model, backend: backend)

        model.input = "Как спасти соус?"
        model.launchSend()
        await waitUntil { backend.continuation != nil }
        backend.continuation?.yield(.textDelta("Сними"))
        await waitUntil { model.messages.last?.text == "Сними" }

        model.close()
        await waitUntil { backend.streamTerminated }
        backend.continuation?.yield(.textDelta(" с огня"))
        await settle()

        XCTAssertTrue(backend.streamTerminated)
        XCTAssertEqual(model.messages.last?.text, "Сними", "a closed chat must not take stream events")
        XCTAssertEqual(backend.persistedThreadIds.last ?? nil, "thread-new")
    }

    /// iPhone: the sheet reopens like before (bootstrap, thread restore), only
    /// the typed draft survives (plan.md Р7).
    func testDraftSurvivesCloseAndReopen() async {
        let backend = FakeAssistantBackend()
        let model = backend.makeModel()
        await openAndBootstrap(model, backend: backend)
        model.input = "Как спасти соус?"
        model.launchSend()
        await waitUntil { backend.continuation != nil }
        backend.continuation?.finish()
        await waitUntil { !model.isSending }
        model.input = "Черновик"
        XCTAssertEqual(model.messages.count, 2)

        model.close()
        // The dismissal animation still shows the content.
        XCTAssertEqual(model.messages.count, 2)

        await openAndBootstrap(model, backend: backend)
        XCTAssertEqual(model.input, "Черновик")
        XCTAssertTrue(model.messages.isEmpty, "no saved thread to restore: a new chat, as before")
        XCTAssertEqual(backend.listThreadsCalls, 2)
    }

    func testNewChatClearsDraft() async {
        let backend = FakeAssistantBackend()
        let model = backend.makeModel()
        await openAndBootstrap(model, backend: backend)
        model.input = "Черновик"

        model.startNewChat()

        XCTAssertEqual(model.input, "")
    }

    // MARK: - Session teardown

    func testEpochChangeDropsStaleStream() async {
        let backend = FakeAssistantBackend()
        let model = backend.makeModel()
        await openAndBootstrap(model, backend: backend)

        model.input = "Как спасти соус?"
        model.launchSend()
        await waitUntil { backend.continuation != nil }
        backend.continuation?.yield(.textDelta("Сними"))
        await waitUntil { model.messages.last?.text == "Сними" }

        model.teardownForSessionInvalidation()
        backend.continuation?.yield(.textDelta(" с огня"))
        await waitUntil { backend.streamTerminated }
        await settle()

        XCTAssertTrue(model.messages.isEmpty)
        XCTAssertNil(model.threadId)
        XCTAssertFalse(model.isSending)
    }

    func testLogoutResetsSession() async {
        let backend = FakeAssistantBackend()
        let model = backend.makeModel()
        await openAndBootstrap(model, backend: backend)
        model.input = "Черновик прошлого аккаунта"
        model.launchSend()
        await waitUntil { backend.continuation != nil }

        model.resetForLogout()
        await waitUntil { backend.streamTerminated }

        XCTAssertEqual(model.input, "")
        XCTAssertTrue(model.messages.isEmpty)
        XCTAssertTrue(model.threads.isEmpty)
        XCTAssertNil(model.threadId)
        XCTAssertFalse(model.isSending)

        await openAndBootstrap(model, backend: backend)
        XCTAssertEqual(backend.listThreadsCalls, 2, "the next account bootstraps its own chat")
    }

    // MARK: - Helpers

    private func openAndBootstrap(_ model: AssistantSessionModel, backend: FakeAssistantBackend) async {
        let before = backend.listThreadsCalls
        model.beginPresentation(openRequest: nil, shakeRequest: nil)
        model.viewDidAppear(shakeRequest: nil)
        await waitUntil { backend.listThreadsCalls == before + 1 && !model.isBootstrapping }
    }

    private func waitUntil(
        _ condition: () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), "condition not reached", file: file, line: line)
    }

    /// Lets queued main-actor work run (a stale event would land here).
    private func settle() async {
        for _ in 0..<10 {
            await Task.yield()
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
}

/// In-memory backend: counts calls and hands the test the stream continuation.
@MainActor
private final class FakeAssistantBackend {
    var listThreadsCalls = 0
    var streamCalls: [(threadId: String, message: String)] = []
    var continuation: AsyncThrowingStream<AssistantStreamEvent, Error>.Continuation?
    var streamTerminated = false
    var persistedThreadIds: [String?] = []

    func makeModel() -> AssistantSessionModel {
        AssistantSessionModel(
            client: client(),
            isOnline: { true },
            collectionEntries: { [] }
        )
    }

    private func client() -> AssistantSessionClient {
        AssistantSessionClient(
            listThreads: { [unowned self] in
                listThreadsCalls += 1
                return []
            },
            createThread: {
                AssistantThreadDTO(
                    id: "thread-new",
                    title: nil,
                    createdAt: "2026-10-13T10:00:00.000Z",
                    updatedAt: "2026-10-13T10:00:00.000Z",
                    lastMessageAt: nil
                )
            },
            getMessages: { _ in [] },
            deleteThread: { _ in },
            stream: { [unowned self] threadId, message, _ in
                streamCalls.append((threadId: threadId, message: message))
                let (stream, continuation) = AsyncThrowingStream<AssistantStreamEvent, Error>.makeStream()
                continuation.onTermination = { [weak self] _ in
                    Task { @MainActor in self?.streamTerminated = true }
                }
                self.streamTerminated = false
                self.continuation = continuation
                return stream
            },
            savedThreadId: { nil },
            lastOpenedAt: { 0 },
            persistThreadId: { [unowned self] threadId in
                persistedThreadIds.append(threadId)
            },
            clearThreadId: {}
        )
    }
}

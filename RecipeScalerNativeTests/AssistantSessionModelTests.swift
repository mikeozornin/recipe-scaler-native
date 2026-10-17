//
//  AssistantSessionModelTests.swift
//
//  Spec 081 (T032a) — the shared assistant session: a panel ↔ sheet swap keeps
//  the chat, the draft and the stream; close / logout / session epoch drop it.
//  T034 — ✦ on «Покупки» / «Подборки» opens a new chat instead of the recent one.
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

    /// The shell routes a request straight into an open chat and the chat's own
    /// `openRequest` observer delivers it again: one send, the stream keeps running.
    func testRepeatedExternalRequestWhileOpenIsSentOnce() async {
        let backend = FakeAssistantBackend()
        let model = backend.makeModel()
        await openAndBootstrap(model, backend: backend)
        let request = AssistantOpenRequest(requestId: 11, message: "Подбери гарнир")

        model.receiveExternalRequest(request)
        await waitUntil { backend.continuation != nil }
        backend.continuation?.yield(.textDelta("Рис"))
        await waitUntil { model.messages.last?.text == "Рис" }

        model.receiveExternalRequest(request)
        await settle()

        XCTAssertEqual(backend.streamCalls.map(\.message), ["Подбери гарнир"])
        XCTAssertFalse(backend.streamTerminated, "the duplicate must not restart the chat")
        XCTAssertEqual(model.messages.map(\.text), ["Подбери гарнир", "Рис"])
        XCTAssertTrue(model.isSending)

        // Another request is not a duplicate.
        backend.continuation?.finish()
        await waitUntil { !model.isSending }
        model.receiveExternalRequest(AssistantOpenRequest(requestId: 12, message: "А десерт?"))
        await waitUntil { backend.streamCalls.count == 2 }
        XCTAssertEqual(backend.streamCalls.last?.message, "А десерт?")
    }

    /// A request that arrives while the bootstrap waits for the server is sent once,
    /// after it, into a new chat.
    func testExternalRequestDuringBootstrapIsSentOnceAfterIt() async {
        let backend = FakeAssistantBackend()
        backend.recentThreadId = "thread-recent"
        backend.holdsListThreads = true
        let model = backend.makeModel()
        model.beginPresentation(openRequest: nil, shakeRequest: nil)
        model.viewDidAppear(shakeRequest: nil)
        await waitUntil { backend.listThreadsCalls == 1 }
        XCTAssertTrue(model.isBootstrapping)

        model.receiveExternalRequest(AssistantOpenRequest(requestId: 21, message: "Чем заменить сливки?"))
        await settle()
        XCTAssertTrue(backend.streamCalls.isEmpty, "nothing is sent before the bootstrap ends")

        backend.releaseListThreads()
        await waitUntil { backend.streamCalls.count == 1 }
        await settle()

        XCTAssertEqual(backend.streamCalls.map(\.message), ["Чем заменить сливки?"])
        XCTAssertEqual(backend.streamCalls.first?.threadId, "thread-new")
        XCTAssertTrue(backend.getMessagesCalls.isEmpty, "the request opens a new chat, not the recent one")
        XCTAssertEqual(model.messages.first?.text, "Чем заменить сливки?")
        XCTAssertEqual(backend.listThreadsCalls, 1)
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

        XCTAssertEqual(model.threadId, "thread-new")
        XCTAssertTrue(model.isSending)

        // Events the server sent before the close: a stream delivers what it buffered
        // even after the consumer is cancelled, so only the model's guard keeps them out.
        backend.continuation?.yield(.textDelta(" с огня"))
        backend.continuation?.yield(.final(Self.finalEvent(threadId: "thread-stale")))
        model.close()
        await waitUntil { backend.streamTerminated }
        await settle()

        XCTAssertEqual(model.messages.last?.text, "Сними", "a closed chat must not take stream events")
        XCTAssertEqual(model.messages.map(\.role), ["user", "assistant"])
        XCTAssertEqual(model.threadId, "thread-new", "a stale final must not switch the thread")
        XCTAssertTrue(model.isSending, "close leaves the content to the dismissal animation")
        XCTAssertFalse(backend.persistedThreadIds.contains("thread-stale"))
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

    // MARK: - Open with a new chat (spec 081, FR-021)

    /// The tab and the recipe ✦ reopen a chat closed less than a minute ago.
    func testReopenRestoresRecentThread() async {
        let backend = FakeAssistantBackend()
        backend.recentThreadId = "thread-recent"
        let model = backend.makeModel()

        await openAndBootstrap(model, backend: backend)
        await waitUntil { model.threadId == "thread-recent" }

        XCTAssertEqual(backend.getMessagesCalls, ["thread-recent"])
    }

    /// ✦ on «Покупки» and «Подборки» opens a new chat, even right after a recent one;
    /// the typed draft stays.
    func testStartsNewChatSkipsRecentThread() async {
        let backend = FakeAssistantBackend()
        backend.recentThreadId = "thread-recent"
        let model = backend.makeModel()
        model.input = "Черновик"

        model.beginPresentation(openRequest: nil, shakeRequest: nil, startsNewChat: true)
        model.viewDidAppear(shakeRequest: nil)
        await waitUntil { backend.listThreadsCalls == 1 && !model.isBootstrapping }
        await settle()

        XCTAssertNil(model.threadId)
        XCTAssertTrue(model.messages.isEmpty)
        XCTAssertTrue(backend.getMessagesCalls.isEmpty)
        XCTAssertEqual(model.input, "Черновик")

        // The next plain open restores again.
        model.close()
        await openAndBootstrap(model, backend: backend)
        await waitUntil { model.threadId == "thread-recent" }
    }

    // MARK: - Context recipe

    /// A new chat opened from a recipe starts with that recipe attached.
    func testNewChatAttachesContextRecipe() async {
        let backend = FakeAssistantBackend()
        backend.entries = [Self.entry(id: "r1", name: "Борщ")]
        let model = backend.makeModel()

        model.beginPresentation(openRequest: nil, shakeRequest: nil, contextRecipeId: "R1")
        model.viewDidAppear(shakeRequest: nil)
        await waitUntil { backend.listThreadsCalls == 1 && !model.isBootstrapping }

        XCTAssertNil(model.threadId)
        XCTAssertEqual(model.attachments.map(\.recipeId), ["r1"])
        XCTAssertEqual(model.attachments.first?.recipeName, "Борщ")

        // The user's «новый чат» starts from the recipe again, once.
        model.attachments = []
        model.startNewChat(attachingRecipeId: "r1")
        model.startNewChat(attachingRecipeId: nil)
        XCTAssertTrue(model.attachments.isEmpty)
        model.startNewChat(attachingRecipeId: "r1")
        XCTAssertEqual(model.attachments.map(\.recipeId), ["r1"])
    }

    /// A restored recent chat is already under way: nothing is attached to it.
    func testRestoredThreadDoesNotAttachContextRecipe() async {
        let backend = FakeAssistantBackend()
        backend.recentThreadId = "thread-recent"
        backend.entries = [Self.entry(id: "r1", name: "Борщ")]
        let model = backend.makeModel()

        model.beginPresentation(openRequest: nil, shakeRequest: nil, contextRecipeId: "r1")
        model.viewDidAppear(shakeRequest: nil)
        await waitUntil { model.threadId == "thread-recent" && !model.isBootstrapping }

        XCTAssertTrue(model.attachments.isEmpty)
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

        // Buffered before the teardown (see `testCloseCancelsStream`). A text delta has
        // no message left to land in, a tool status row and the final would.
        backend.continuation?.yield(.toolStart(toolName: "search_recipes", toolCallId: "call-1"))
        backend.continuation?.yield(.final(Self.finalEvent(threadId: "thread-stale")))
        model.teardownForSessionInvalidation()
        await waitUntil { backend.streamTerminated }
        await settle()

        XCTAssertTrue(model.messages.isEmpty)
        XCTAssertNil(model.threadId)
        XCTAssertFalse(model.isSending)
        XCTAssertFalse(backend.persistedThreadIds.contains("thread-stale"))
    }

    /// A teardown also stops the first bootstrap, the history refresh and the shake
    /// intent of the dead session, not only the stream.
    func testTeardownDropsBootstrapShakeAndHistoryRefresh() async {
        let backend = FakeAssistantBackend()
        backend.recentThreadId = "thread-recent"
        backend.holdsListThreads = true
        let model = backend.makeModel()
        let shake = AssistantShakeOpenRequest(
            requestId: 3,
            attachRecipeId: nil,
            forceNewChat: false,
            startVoiceRecording: true
        )
        model.beginPresentation(openRequest: nil, shakeRequest: shake)
        model.viewDidAppear(shakeRequest: shake)
        model.historyDidOpen()
        await waitUntil { backend.listThreadsCalls == 2 }
        XCTAssertTrue(model.isBootstrapping)
        XCTAssertTrue(model.isLoadingThreads)

        model.teardownForSessionInvalidation()
        backend.releaseListThreads()
        await settle()

        XCTAssertFalse(model.autoStartVoice, "the dead session's shake must not start voice input")
        XCTAssertTrue(model.threads.isEmpty)
        XCTAssertNil(model.threadId)
        XCTAssertTrue(backend.getMessagesCalls.isEmpty, "the recent thread must not be restored")
        XCTAssertFalse(model.isBootstrapping)
        XCTAssertFalse(model.isLoadingThreads, "no history spinner left behind")
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

    private static func entry(id: String, name: String) -> CollectionEntry {
        CollectionEntry(
            id: id,
            name: name,
            color: "#FF0000",
            imageUrl: nil,
            updatedAt: "2026-01-01T00:00:00.000Z",
            deleted: false,
            isPinned: false
        )
    }

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

    private static func finalEvent(threadId: String) -> AssistantStreamFinalData {
        AssistantStreamFinalData(
            thread: AssistantStreamFinalData.Thread(id: threadId, title: "Чужой чат"),
            userMessage: nil,
            assistantMessage: AssistantStreamFinalMessage(
                id: "assistant-stale",
                content: "Устаревший ответ",
                metadata: nil,
                createdAt: nil
            )
        )
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
    /// A thread saved and opened just now: the ≤60 s restore picks it.
    var recentThreadId: String?
    var getMessagesCalls: [String] = []
    var entries: [CollectionEntry] = []
    /// `listThreads` waits for `releaseListThreads()`, ignoring cancellation, as a slow
    /// server does: the caller's guards decide what lands.
    var holdsListThreads = false
    private var listThreadsWaiters: [CheckedContinuation<Void, Never>] = []

    func releaseListThreads() {
        holdsListThreads = false
        let waiters = listThreadsWaiters
        listThreadsWaiters = []
        waiters.forEach { $0.resume() }
    }

    func makeModel() -> AssistantSessionModel {
        AssistantSessionModel(
            client: client(),
            isOnline: { true },
            collectionEntries: { [unowned self] in entries }
        )
    }

    private func client() -> AssistantSessionClient {
        AssistantSessionClient(
            listThreads: { [unowned self] in
                listThreadsCalls += 1
                if holdsListThreads {
                    await withCheckedContinuation { listThreadsWaiters.append($0) }
                }
                return recentThreadId.map {
                    [AssistantThreadDTO(
                        id: $0,
                        title: "Соус",
                        createdAt: "2026-10-13T09:00:00.000Z",
                        updatedAt: "2026-10-13T09:00:00.000Z",
                        lastMessageAt: nil
                    )]
                } ?? []
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
            getMessages: { [unowned self] threadId in
                getMessagesCalls.append(threadId)
                return []
            },
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
            savedThreadId: { [unowned self] in recentThreadId },
            lastOpenedAt: { [unowned self] in recentThreadId == nil ? 0 : Date().timeIntervalSince1970 },
            persistThreadId: { [unowned self] threadId in
                persistedThreadIds.append(threadId)
            },
            clearThreadId: {}
        )
    }
}

//
//  AssistantSessionModelTests.swift
//
//  Spec 081 (T032a) — the shared assistant session: a panel ↔ sheet swap keeps
//  the chat, the draft and the stream; close / logout / session epoch drop it.
//  T034 — ✦ on «Покупки» / «Подборки» opens a new chat instead of the recent one.
//  Reply recovery — a broken stream waits for the reply the server saves.
//  No network: every call goes through an in-memory fake client.
//

import XCTest
import RecipeScalerCore
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

        backend.continuation?.yield(.final(Self.finalEvent(threadId: "thread-new")))
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
        backend.continuation?.yield(.final(Self.finalEvent(threadId: "thread-new")))
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

    // MARK: - Stream text coalescing (deltas are applied at most every 33 ms)

    func testBurstOfDeltasArrivesWhole() async {
        let backend = FakeAssistantBackend()
        let model = backend.makeModel()
        await openAndBootstrap(model, backend: backend)

        model.input = "Как спасти соус?"
        model.launchSend()
        await waitUntil { backend.continuation != nil }
        let tokens = (0..<200).map { "слово\($0) " }
        for token in tokens {
            backend.continuation?.yield(.textDelta(token))
        }
        await waitUntil { model.messages.last?.text == tokens.joined() }
        XCTAssertEqual(model.messages.last?.isStreaming, true)

        backend.continuation?.yield(.final(Self.finalEvent(threadId: "thread-new", content: nil)))
        await waitUntil { !model.isSending }
        XCTAssertEqual(model.messages.last?.text, tokens.joined())
    }

    func testFinalWithoutContentKeepsBufferedText() async {
        let backend = FakeAssistantBackend()
        let model = backend.makeModel()
        await openAndBootstrap(model, backend: backend)

        model.input = "Как спасти соус?"
        model.launchSend()
        await waitUntil { backend.continuation != nil }
        // Same burst: the last two deltas are still buffered when the final arrives.
        backend.continuation?.yield(.textDelta("Сни"))
        backend.continuation?.yield(.textDelta("ми"))
        backend.continuation?.yield(.textDelta(" с огня"))
        backend.continuation?.yield(.final(AssistantStreamFinalData(
            thread: AssistantStreamFinalData.Thread(id: "thread-new", title: nil),
            userMessage: nil,
            assistantMessage: AssistantStreamFinalMessage(
                id: "assistant-1",
                content: nil,
                metadata: nil,
                createdAt: nil
            )
        )))
        await waitUntil { !model.isSending }

        XCTAssertEqual(model.messages.last?.id, "assistant-1")
        XCTAssertEqual(model.messages.last?.text, "Сними с огня")
        XCTAssertEqual(model.messages.last?.isStreaming, false)
    }

    func testToolStatusKeepsTextOrder() async {
        let backend = FakeAssistantBackend()
        let model = backend.makeModel()
        await openAndBootstrap(model, backend: backend)

        model.input = "Найди рецепт"
        model.launchSend()
        await waitUntil { backend.continuation != nil }
        backend.continuation?.yield(.textDelta("Ищу"))
        backend.continuation?.yield(.textDelta(" рецепты"))
        backend.continuation?.yield(.toolStart(toolName: "search_recipes", toolCallId: "call-1"))
        backend.continuation?.yield(.textDelta(": нашёл"))
        await waitUntil { model.messages.last?.text == "Ищу рецепты: нашёл" }

        XCTAssertEqual(model.messages.map(\.role), ["user", "assistant", "assistant"])
        XCTAssertTrue(model.messages[1].isToolStatusRow)
        XCTAssertFalse(model.messages[2].isToolStatusRow)

        backend.continuation?.yield(.final(Self.finalEvent(threadId: "thread-new")))
        await waitUntil { !model.isSending }
    }

    func testCloseKeepsTextAlreadyReceived() async {
        let backend = FakeAssistantBackend()
        let model = backend.makeModel()
        await openAndBootstrap(model, backend: backend)

        model.input = "Как спасти соус?"
        model.launchSend()
        await waitUntil { backend.continuation != nil }
        backend.continuation?.yield(.textDelta("Сними"))
        await waitUntil { model.messages.last?.text == "Сними" }
        // Consumed but still inside the 33 ms window when the chat closes.
        backend.continuation?.yield(.textDelta(" с огня"))
        try? await Task.sleep(nanoseconds: 5_000_000)
        model.close()
        await settle()

        XCTAssertEqual(model.messages.last?.text, "Сними с огня")
    }

    func testStreamFlushThrottleTiming() {
        var throttle = AssistantStreamFlushThrottle()
        let start = ContinuousClock.now
        XCTAssertNil(throttle.delayBeforeFlush(now: start), "the first delta shows at once")

        throttle.didFlush(at: start)
        XCTAssertEqual(throttle.delayBeforeFlush(now: start + .milliseconds(10)), .milliseconds(23))
        XCTAssertNil(throttle.delayBeforeFlush(now: start + .milliseconds(33)))
        XCTAssertNil(throttle.delayBeforeFlush(now: start + .milliseconds(500)))

        throttle.reset()
        XCTAssertNil(throttle.delayBeforeFlush(now: start + .milliseconds(1)))
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
        backend.continuation?.yield(.final(Self.finalEvent(threadId: "thread-new")))
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

    // MARK: - Reply recovery (the server keeps generating after a broken stream)

    /// (a) The connection drops after a tool started: the turn stays on screen while
    /// the server finishes, then the saved history replaces it — no error, no resend.
    func testConnectionLostRecoversSavedReply() async {
        let backend = FakeAssistantBackend()
        let model = backend.makeModel()
        await openAndBootstrap(model, backend: backend)
        backend.getMessagesHoldFrom = 1
        backend.historyResponses = [
            .success(Self.history([Self.dto("srv-user-1", "user", "Найди рецепт")], inProgress: true)),
            .success(Self.history([
                Self.dto("srv-user-1", "user", "Найди рецепт"),
                Self.dto("srv-assistant-1", "assistant", "Нашёл борщ"),
            ], inProgress: false)),
        ]

        model.input = "Найди рецепт"
        model.launchSend()
        await waitUntil { backend.continuation != nil }
        backend.continuation?.yield(.toolStart(toolName: "search_recipes", toolCallId: "call-1"))
        await waitUntil { model.messages.contains(where: \.isToolStatusRow) }
        backend.continuation?.finish(throwing: URLError(.networkConnectionLost))

        await waitUntil { backend.heldGetMessages == 1 }
        XCTAssertTrue(model.isSending, "the composer stays locked while the reply is recovered")
        XCTAssertEqual(model.messages.map(\.role), ["user", "assistant", "assistant"])
        XCTAssertTrue(model.messages.first.map { AssistantMessage.isOptimisticID($0.id) } ?? false)
        XCTAssertEqual(model.messages.last?.isProcessingPlaceholder, true)
        XCTAssertEqual(model.input, "")

        backend.releaseGetMessages()
        await waitUntil { backend.heldGetMessages == 1 && backend.getMessagesCalls.count == 2 }
        XCTAssertTrue(model.isSending, "still in progress: keep waiting")
        backend.releaseGetMessages()
        await waitUntil { !model.isSending }

        XCTAssertEqual(model.messages.map(\.id), ["srv-user-1", "srv-assistant-1"])
        XCTAssertEqual(model.messages.last?.text, "Нашёл борщ")
        XCTAssertEqual(model.input, "")
        XCTAssertEqual(backend.streamCalls.count, 1, "nothing is resent")
        XCTAssertEqual(backend.getMessagesCalls, ["thread-new", "thread-new"])
        XCTAssertEqual(backend.backgroundTaskBegins, 1)
        XCTAssertEqual(backend.backgroundTaskEnds, 1)
    }

    /// (b) The stream closes without `final` (server cut-off): same recovery, the
    /// text received so far stays until the saved reply replaces it.
    func testStreamEndedWithoutFinalRecoversSavedReply() async {
        let backend = FakeAssistantBackend()
        let model = backend.makeModel()
        await openAndBootstrap(model, backend: backend)
        backend.getMessagesHoldFrom = 1
        backend.historyResponses = [
            .success(Self.history([
                Self.dto("srv-user-1", "user", "Как спасти соус?"),
                Self.dto("srv-assistant-1", "assistant", "Сними с огня и добавь воды"),
            ], inProgress: false)),
        ]

        model.input = "  Как спасти соус?  "
        model.launchSend()
        await waitUntil { backend.continuation != nil }
        backend.continuation?.yield(.textDelta("Сними"))
        await waitUntil { model.messages.last?.text == "Сними" }
        backend.continuation?.finish()

        await waitUntil { backend.heldGetMessages == 1 }
        XCTAssertTrue(model.isSending)
        XCTAssertEqual(model.messages.last?.text, "Сними")
        XCTAssertFalse(model.messages.contains { $0.id.hasPrefix("error-") })

        backend.releaseGetMessages()
        await waitUntil { !model.isSending }
        XCTAssertEqual(model.messages.map(\.id), ["srv-user-1", "srv-assistant-1"])
        XCTAssertEqual(model.messages.last?.text, "Сними с огня и добавь воды")
    }

    /// (c) The turn never reached the server: the error bubble and the restored draft,
    /// as before. An earlier identical question already in the chat is not our turn.
    func testRequestThatNeverArrivedShowsErrorAndRestoresInput() async {
        let backend = FakeAssistantBackend()
        backend.recentThreadId = "thread-recent"
        let earlier = Self.history([
            Self.dto("srv-user-old", "user", "Найди рецепт", threadId: "thread-recent"),
            Self.dto("srv-assistant-old", "assistant", "Нашёл борщ", threadId: "thread-recent"),
        ], inProgress: false)
        backend.defaultHistory = earlier
        let model = backend.makeModel()
        await openAndBootstrap(model, backend: backend)
        await waitUntil { model.messages.count == 2 }

        model.input = "Найди рецепт"
        model.launchSend()
        await waitUntil { backend.continuation != nil }
        backend.continuation?.finish(throwing: URLError(.notConnectedToInternet))
        await waitUntil { !model.isSending }

        XCTAssertEqual(model.messages.map(\.id).prefix(2), ["srv-user-old", "srv-assistant-old"])
        XCTAssertEqual(model.messages.count, 3)
        XCTAssertTrue(model.messages.last?.id.hasPrefix("error-") ?? false)
        XCTAssertEqual(model.messages.last?.text, UserFacingAPIError.message(for: URLError(.notConnectedToInternet)))
        XCTAssertEqual(model.input, "Найди рецепт")
        XCTAssertEqual(backend.getMessagesCalls.count, 2, "one restore, one recovery poll")
        XCTAssertEqual(backend.backgroundTaskBegins, backend.backgroundTaskEnds)
    }

    /// (d) Closing the chat stops the recovery: no more polls, nothing lands later.
    func testCloseDuringRecoveryStopsPolling() async {
        let backend = FakeAssistantBackend()
        let model = backend.makeModel()
        await openAndBootstrap(model, backend: backend)
        backend.defaultHistory = Self.history([Self.dto("srv-user-1", "user", "Найди рецепт")], inProgress: true)

        model.input = "Найди рецепт"
        model.launchSend()
        await waitUntil { backend.continuation != nil }
        backend.continuation?.finish(throwing: URLError(.networkConnectionLost))
        await waitUntil { backend.getMessagesCalls.count >= 2 }
        let shownAtClose = model.messages.map(\.id)

        model.close()
        let pollsAtClose = backend.getMessagesCalls.count
        backend.defaultHistory = Self.history([
            Self.dto("srv-user-1", "user", "Найди рецепт"),
            Self.dto("srv-assistant-1", "assistant", "Нашёл борщ"),
        ], inProgress: false)
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(backend.getMessagesCalls.count, pollsAtClose)
        XCTAssertEqual(model.messages.map(\.id), shownAtClose)
        XCTAssertFalse(model.messages.contains { $0.id.hasPrefix("error-") })
        XCTAssertEqual(backend.backgroundTaskEnds, backend.backgroundTaskBegins)
    }

    /// (e) A restored thread whose reply is still being generated: a typing
    /// placeholder, then the saved history.
    func testRestoredThreadWithRunningReplyShowsItWhenSaved() async {
        let backend = FakeAssistantBackend()
        backend.recentThreadId = "thread-recent"
        backend.getMessagesHoldFrom = 2
        backend.historyResponses = [
            .success(Self.history([
                Self.dto("srv-user-1", "user", "Найди рецепт", threadId: "thread-recent"),
            ], inProgress: true)),
            .success(Self.history([
                Self.dto("srv-user-1", "user", "Найди рецепт", threadId: "thread-recent"),
                Self.dto("srv-assistant-1", "assistant", "Нашёл борщ", threadId: "thread-recent"),
            ], inProgress: false)),
        ]
        let model = backend.makeModel()
        await openAndBootstrap(model, backend: backend)
        await waitUntil { backend.heldGetMessages == 1 }

        XCTAssertEqual(model.threadId, "thread-recent")
        XCTAssertEqual(model.messages.first?.id, "srv-user-1")
        XCTAssertEqual(model.messages.count, 2)
        XCTAssertEqual(model.messages.last?.isProcessingPlaceholder, true)
        XCTAssertTrue(model.isSending)

        backend.releaseGetMessages()
        await waitUntil { !model.isSending }
        XCTAssertEqual(model.messages.map(\.id), ["srv-user-1", "srv-assistant-1"])
        XCTAssertEqual(backend.getMessagesCalls, ["thread-recent", "thread-recent"])
    }

    /// (f) A turn sent while the previous reply still runs: the localized error and
    /// the restored draft, then the running reply once it is saved.
    func testResponseInProgressErrorWaitsForRunningReply() async {
        let backend = FakeAssistantBackend()
        let model = backend.makeModel()
        await openAndBootstrap(model, backend: backend)
        backend.getMessagesHoldFrom = 1
        backend.historyResponses = [
            .success(Self.history([
                Self.dto("srv-user-prev", "user", "Подбери гарнир"),
                Self.dto("srv-assistant-prev", "assistant", "Рис"),
            ], inProgress: false)),
        ]

        model.input = "А десерт?"
        model.launchSend()
        await waitUntil { backend.continuation != nil }
        backend.continuation?.yield(.error(.assistantResponseInProgress))
        await waitUntil { backend.heldGetMessages == 1 }

        let expected = APIError.serverError(code: .assistantResponseInProgress).userFacingMessage()
        XCTAssertNotEqual(expected, ServerErrorCode.assistantResponseInProgress.rawValue, "the key is localized")
        XCTAssertEqual(model.messages.map(\.role), ["assistant", "assistant"])
        XCTAssertEqual(model.messages.first?.text, expected)
        XCTAssertTrue(model.messages.first?.id.hasPrefix("error-") ?? false)
        XCTAssertEqual(model.messages.last?.isProcessingPlaceholder, true)
        XCTAssertEqual(model.input, "А десерт?")
        XCTAssertTrue(model.isSending)

        backend.releaseGetMessages()
        await waitUntil { !model.isSending }
        XCTAssertEqual(model.messages.map(\.id), ["srv-user-prev", "srv-assistant-prev"])
        XCTAssertEqual(model.input, "А десерт?")
        XCTAssertEqual(backend.streamCalls.count, 1)
        XCTAssertEqual(backend.backgroundTaskBegins, backend.backgroundTaskEnds)
    }

    /// Our turn = the last matching user message after everything shown before the
    /// send, followed by an assistant message.
    func testHistoryContainsReplyDetection() {
        let known: Set<String> = ["u-old", "a-old"]
        let old = [Self.dto("u-old", "user", "Борщ"), Self.dto("a-old", "assistant", "Вот")]

        XCTAssertTrue(AssistantSessionModel.historyContainsReply(
            old + [Self.dto("u-new", "user", " Борщ\n"), Self.dto("a-new", "assistant", "Ещё")],
            sentText: "Борщ",
            knownMessageIds: known
        ))
        XCTAssertFalse(AssistantSessionModel.historyContainsReply(
            old, sentText: "Борщ", knownMessageIds: known
        ), "an earlier identical turn is not ours")
        XCTAssertFalse(AssistantSessionModel.historyContainsReply(
            old + [Self.dto("u-new", "user", "Борщ")], sentText: "Борщ", knownMessageIds: known
        ), "no reply after our turn")
        XCTAssertFalse(AssistantSessionModel.historyContainsReply(
            old + [Self.dto("u-new", "user", "Щи"), Self.dto("a-new", "assistant", "Ещё")],
            sentText: "Борщ",
            knownMessageIds: known
        ))
        XCTAssertTrue(AssistantSessionModel.historyContainsReply(
            [Self.dto("u-new", "user", "Борщ"), Self.dto("a-new", "assistant", "Вот")],
            sentText: "Борщ",
            knownMessageIds: ["optimistic-user-1"]
        ), "a new chat: nothing known yet")
    }

    func testRecoveryTimingBacksOffAfterFailedPolls() {
        let timing = AssistantReplyRecoveryTiming(
            pollInterval: .seconds(2),
            maxRetryInterval: .seconds(30),
            deadline: .seconds(600)
        )
        XCTAssertEqual(timing.delay(afterFailures: 0), .seconds(2))
        XCTAssertEqual(timing.delay(afterFailures: 1), .seconds(4))
        XCTAssertEqual(timing.delay(afterFailures: 3), .seconds(16))
        XCTAssertEqual(timing.delay(afterFailures: 4), .seconds(30))
        XCTAssertEqual(timing.delay(afterFailures: 50), .seconds(30))
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

    private static func finalEvent(
        threadId: String,
        content: String? = "Устаревший ответ"
    ) -> AssistantStreamFinalData {
        AssistantStreamFinalData(
            thread: AssistantStreamFinalData.Thread(id: threadId, title: "Чужой чат"),
            userMessage: nil,
            assistantMessage: AssistantStreamFinalMessage(
                id: "assistant-stale",
                content: content,
                metadata: nil,
                createdAt: nil
            )
        )
    }

    fileprivate static func dto(_ id: String, _ role: String, _ content: String, threadId: String = "thread-new") -> AssistantMessageDTO {
        AssistantMessageDTO(
            id: id,
            threadId: threadId,
            role: role,
            content: content,
            metadata: nil,
            createdAt: "2026-10-13T10:00:00.000Z",
            updatedAt: "2026-10-13T10:00:00.000Z"
        )
    }

    fileprivate static func history(_ messages: [AssistantMessageDTO], inProgress: Bool) -> AssistantThreadHistory {
        AssistantThreadHistory(messages: messages, responseInProgress: inProgress)
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
    /// Answers of `getMessages`, in call order; then `defaultHistory`.
    var historyResponses: [Result<AssistantThreadHistory, Error>] = []
    var defaultHistory = AssistantThreadHistory(messages: [], responseInProgress: false)
    /// Calls with this 1-based number or later wait for `releaseGetMessages()`.
    var getMessagesHoldFrom: Int?
    private var getMessagesWaiters: [CheckedContinuation<Void, Never>] = []
    var heldGetMessages: Int { getMessagesWaiters.count }
    var backgroundTaskBegins = 0
    var backgroundTaskEnds = 0
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

    /// Releases the oldest held `getMessages` call.
    func releaseGetMessages() {
        guard !getMessagesWaiters.isEmpty else { return }
        getMessagesWaiters.removeFirst().resume()
    }

    func makeModel() -> AssistantSessionModel {
        AssistantSessionModel(
            client: client(),
            isOnline: { true },
            collectionEntries: { [unowned self] in entries },
            recoveryTiming: AssistantReplyRecoveryTiming(
                pollInterval: .milliseconds(10),
                maxRetryInterval: .milliseconds(40),
                deadline: .seconds(5)
            )
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
            getMessages: { [weak self] threadId in
                // Weak: a recovery poll may outlive a finished test.
                guard let self else { throw CancellationError() }
                getMessagesCalls.append(threadId)
                if let holdFrom = getMessagesHoldFrom, getMessagesCalls.count >= holdFrom {
                    await withCheckedContinuation { self.getMessagesWaiters.append($0) }
                }
                guard !historyResponses.isEmpty else { return defaultHistory }
                return try historyResponses.removeFirst().get()
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
            clearThreadId: {},
            beginBackgroundTask: { [unowned self] in
                backgroundTaskBegins += 1
                var ended = false
                return { [weak self] in
                    guard !ended else { return }
                    ended = true
                    self?.backgroundTaskEnds += 1
                }
            }
        )
    }
}

/// `GET /api/assistant/threads/:id/messages` envelope: `responseInProgress` is
/// optional on the wire (older servers omit it).
final class AssistantThreadMessagesEnvelopeTests: XCTestCase {
    private static let message = #"{"id":"m1","threadId":"t1","role":"user","content":"Борщ","metadata":null,"createdAt":"2026-10-13T10:00:00.000Z","updatedAt":"2026-10-13T10:00:00.000Z"}"#

    private func decode(_ json: String) throws -> AssistantThreadMessagesEnvelope {
        try JSONDecoder().decode(AssistantThreadMessagesEnvelope.self, from: Data(json.utf8))
    }

    func testResponseInProgressTrue() throws {
        let history = try decode(#"{"success":true,"data":["# + Self.message + #"],"responseInProgress":true}"#)
            .threadHistory()
        XCTAssertTrue(history.responseInProgress)
        XCTAssertEqual(history.messages.map(\.id), ["m1"])
    }

    func testResponseInProgressFalse() throws {
        let history = try decode(#"{"success":true,"data":[],"responseInProgress":false}"#).threadHistory()
        XCTAssertFalse(history.responseInProgress)
        XCTAssertTrue(history.messages.isEmpty)
    }

    func testMissingResponseInProgressMeansFalse() throws {
        let history = try decode(#"{"success":true,"data":["# + Self.message + #"]}"#).threadHistory()
        XCTAssertFalse(history.responseInProgress)
        XCTAssertEqual(history.messages.count, 1)
    }

    func testFailureEnvelopeThrowsServerCode() throws {
        let envelope = try decode(#"{"success":false,"error":"assistant.messages.load.failed"}"#)
        XCTAssertThrowsError(try envelope.threadHistory()) { error in
            guard case APIError.serverError(let code) = error else {
                return XCTFail("unexpected \(error)")
            }
            XCTAssertEqual(code, .assistantMessagesLoadFailed)
        }
    }
}

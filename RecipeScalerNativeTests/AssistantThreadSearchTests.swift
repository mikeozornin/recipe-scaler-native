//
//  AssistantThreadSearchTests.swift
//  RecipeScalerNativeTests
//

import XCTest
@testable import RecipeScalerNative

final class AssistantThreadSearchTests: XCTestCase {
    private func makeThread(id: String, title: String?) -> AssistantThreadDTO {
        AssistantThreadDTO(
            id: id,
            title: title,
            createdAt: "2026-06-14T12:00:00.000Z",
            updatedAt: "2026-06-14T12:00:00.000Z",
            lastMessageAt: "2026-06-14T12:00:00.000Z"
        )
    }

    func testDisplayTitleMapsServerNewChat() {
        let thread = makeThread(id: "1", title: AssistantThreadSearch.serverNewChatTitle)
        XCTAssertEqual(
            AssistantThreadSearch.displayTitle(for: thread),
            Bundle.currentLocalizedString("assistant.new-chat")
        )
    }

    func testFilteredThreadsMatchesTitleTokens() {
        let threads = [
            makeThread(id: "1", title: "Beef stew tips"),
            makeThread(id: "2", title: "Chicken soup"),
        ]
        let filtered = AssistantThreadSearch.filteredThreads(threads, query: "beef stew")
        XCTAssertEqual(filtered.map(\.id), ["1"])
    }

    func testFilteredThreadsMatchesLocalizedNewChatTitle() {
        let threads = [
            makeThread(id: "1", title: AssistantThreadSearch.serverNewChatTitle),
            makeThread(id: "2", title: "Shopping list"),
        ]
        let localizedNewChat = Bundle.currentLocalizedString("assistant.new-chat")
        let prefix = String(localizedNewChat.prefix(3))
        let filtered = AssistantThreadSearch.filteredThreads(threads, query: prefix)
        XCTAssertEqual(filtered.map(\.id), ["1"])
    }

    func testFilteredThreadsReturnsAllWhenQueryEmpty() {
        let threads = [
            makeThread(id: "1", title: "A"),
            makeThread(id: "2", title: "B"),
        ]
        XCTAssertEqual(
            AssistantThreadSearch.filteredThreads(threads, query: "   "),
            threads
        )
    }
}

//
//  AssistantThreadSearch.swift
//  RecipeScalerNative
//
//  Thread list filtering for assistant history (web `assistant-thread-list.tsx`).
//

import Foundation

enum AssistantThreadSearch {
    static let serverNewChatTitle = "New chat"

    static func displayTitle(for thread: AssistantThreadDTO) -> String {
        let raw = thread.title ?? serverNewChatTitle
        if raw == serverNewChatTitle {
            return Bundle.currentLocalizedString("assistant.new-chat")
        }
        return raw
    }

    static func filteredThreads(
        _ threads: [AssistantThreadDTO],
        query: String
    ) -> [AssistantThreadDTO] {
        let tokens = RecipeSearchUtils.tokenizeQuery(query)
        guard !tokens.isEmpty else { return threads }
        return threads.filter { thread in
            RecipeSearchUtils.matchesName(displayTitle(for: thread), tokens: tokens)
        }
    }
}

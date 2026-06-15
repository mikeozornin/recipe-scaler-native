//
//  AssistantThreadListSheet.swift
//  RecipeScalerNative
//
//  Thread history sheet mirroring web `assistant-thread-list.tsx` (DropdownMenu → iOS sheet).
//

import SwiftUI

struct AssistantThreadListSheet: View {
    let threads: [AssistantThreadDTO]
    let activeThreadId: String?
    let deletingThreadId: String?
    let isLoading: Bool
    let onSelect: (String) -> Void
    let onDelete: (String) -> Void

    @State private var searchQuery = ""

    private var filteredThreads: [AssistantThreadDTO] {
        AssistantThreadSearch.filteredThreads(threads, query: searchQuery)
    }

    private var emptyStateKey: LocalizedStringKey {
        threads.isEmpty ? "assistant.no-chats-with-assistant" : "assistant.no-chats-found"
    }

    var body: some View {
        NavigationStack {
            threadList
                .searchable(
                    text: $searchQuery,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("assistant.thread-search-placeholder")
                )
                .accessibilityIdentifier(AccessibilityIdentifiers.assistantThreadPanel)
        }
    }

    @ViewBuilder
    private var threadList: some View {
        List {
            ForEach(filteredThreads) { thread in
                threadRow(thread)
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 40)
            } else if filteredThreads.isEmpty {
                Text(emptyStateKey)
                    .appBody()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 32)
                    .padding(.horizontal, 16)
            }
        }
    }

    private func threadRow(_ thread: AssistantThreadDTO) -> some View {
        let isActive = thread.id == activeThreadId
        let isDeleting = deletingThreadId == thread.id
        let displayTitle = AssistantThreadSearch.displayTitle(for: thread)

        return Button {
            onSelect(thread.id)
        } label: {
            Text(verbatim: displayTitle)
                .appBody()
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .listRowInsets(RecipeRowLayoutMetrics.listRowInsets)
        .listRowBackground(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        .accessibilityLabel(threadAccessibilityLabel(title: displayTitle, lastMessageAt: thread.lastMessageAt))
        .accessibilityIdentifier(AccessibilityIdentifiers.assistantThreadItem(threadId: thread.id))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDelete(thread.id)
            } label: {
                Label("assistant.delete-thread", systemImage: "trash")
            }
            .disabled(isDeleting)
            .accessibilityIdentifier(AccessibilityIdentifiers.assistantThreadDeleteButton(threadId: thread.id))
        }
    }

    private func threadAccessibilityLabel(title: String, lastMessageAt: String?) -> Text {
        guard let lastMessageAt,
              let date = AssistantISO8601.parse(lastMessageAt) else {
            return Text(verbatim: title)
        }
        let formatted = date.formatted(date: .abbreviated, time: .shortened)
        return Text(verbatim: "\(title), \(formatted)")
    }
}

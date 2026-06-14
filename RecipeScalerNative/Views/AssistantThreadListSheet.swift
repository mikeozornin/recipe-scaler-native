//
//  AssistantThreadListSheet.swift
//  RecipeScalerNative
//
//  Thread history sheet mirroring web `assistant-thread-list.tsx` (DropdownMenu → iOS sheet).
//

import SwiftUI

struct AssistantThreadListSheet: View {
    @Environment(\.dismiss) private var dismiss

    let threads: [AssistantThreadDTO]
    let activeThreadId: String?
    let deletingThreadId: String?
    let isLoading: Bool
    let onSelect: (String) -> Void
    let onDelete: (String) -> Void

    @State private var searchQuery = ""
    @FocusState private var isSearchFocused: Bool

    private var filteredThreads: [AssistantThreadDTO] {
        AssistantThreadSearch.filteredThreads(threads, query: searchQuery)
    }

    private var emptyStateKey: LocalizedStringKey {
        threads.isEmpty ? "assistant.no-chats-with-assistant" : "assistant.no-chats-found"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                Divider()

                threadList
            }
            .localizedNavigationTitle("assistant.threads-title")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("assistant.close") { dismiss() }
                        .appToolbarTextButton()
                }
            }
            .onAppear {
                isSearchFocused = true
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.assistantThreadPanel)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            AppSymbol.image("magnifyingglass")
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
            TextField("", text: $searchQuery, prompt: Text("assistant.thread-search-placeholder"))
                .font(AppTypography.body)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .accessibilityIdentifier(AccessibilityIdentifiers.assistantThreadSearchInput)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 44, alignment: .leading)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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

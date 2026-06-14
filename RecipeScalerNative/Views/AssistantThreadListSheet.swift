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
        ScrollView {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if filteredThreads.isEmpty {
                    Text(emptyStateKey)
                        .appBody()
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)
                        .padding(.horizontal, 16)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredThreads) { thread in
                            threadRow(thread)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func threadRow(_ thread: AssistantThreadDTO) -> some View {
        let isActive = thread.id == activeThreadId
        let isDeleting = deletingThreadId == thread.id
        let displayTitle = AssistantThreadSearch.displayTitle(for: thread)

        return HStack(alignment: .top, spacing: 0) {
            Button {
                onSelect(thread.id)
            } label: {
                Text(verbatim: displayTitle)
                    .appBody()
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(threadAccessibilityLabel(title: displayTitle, lastMessageAt: thread.lastMessageAt))
            .accessibilityIdentifier(AccessibilityIdentifiers.assistantThreadItem(threadId: thread.id))

            Button {
                onDelete(thread.id)
            } label: {
                AppSymbol.image("trash")
                    .font(AppTypography.iconSize(AppTypography.bodySize))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
            .opacity(isActive || isDeleting ? 1 : 0.85)
            .accessibilityLabel(Text("assistant.delete-thread"))
            .accessibilityIdentifier(AccessibilityIdentifiers.assistantThreadDeleteButton(threadId: thread.id))
        }
        .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
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

//
//  AssistantSheet.swift
//  RecipeScalerNative
//

import SwiftUI

struct AssistantSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var threadId: String?
    @State private var input = ""
    @State private var messages: [(role: String, text: String)] = []
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            VStack {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages.indices, id: \.self) { index in
                            let msg = messages[index]
                            Text(msg.text)
                                .padding(10)
                                .background(msg.role == "user" ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        if isSending {
                            ProgressView()
                        }
                    }
                    .padding()
                }
                HStack {
                    TextField("Message", text: $input, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    Button("Send") { Task { await send() } }
                        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
                }
                .padding()
            }
            .navigationTitle("Assistant")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await ensureThread() }
            .accessibilityIdentifier(AccessibilityIdentifiers.assistantSheet)
        }
    }

    private func ensureThread() async {
        guard threadId == nil else { return }
        if let thread = try? await AssistantAPI.createThread() {
            threadId = thread.id
        }
    }

    private func send() async {
        guard let threadId else { return }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        messages.append((role: "user", text: text))
        isSending = true
        defer { isSending = false }
        do {
            let reply = try await AssistantAPI.streamResponse(threadId: threadId, message: text)
            messages.append((role: "assistant", text: reply))
        } catch {
            messages.append((role: "assistant", text: error.localizedDescription))
        }
    }
}
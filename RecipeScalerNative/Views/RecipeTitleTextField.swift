//
//  RecipeTitleTextField.swift
//  RecipeScalerNative
//
//  Web parity: uncontrolled multiline field while typing; persist on blur / explicit dismiss (Done).
//

import SwiftUI

/// Native multiline title field that grows with its content instead of scrolling internally.
struct RecipeTitleTextField: View {
    /// Shown when the field is created or when the recipe name changes externally (not while typing).
    let initialText: String
    @Binding var dismissKeyboard: Bool
    /// Focus title once when opening a newly created recipe in edit mode.
    let requestInitialFocus: Bool
    /// Incremented by parent on Done to flush uncommitted title text before `finishEditing`.
    let commitTitleNonce: Int
    let placeholder: String
    let font: Font
    let onBlur: (String) -> Void
    let onEditingActiveChanged: (Bool) -> Void

    @State private var draftText: String
    @FocusState private var isTitleFocused: Bool
    @State private var lastSyncedInitialText: String
    @State private var lastCommittedBlurText: String?
    @State private var appliedCommitNonce = 0
    @State private var didApplyInitialFocus = false
    @State private var isIntentionalFieldDismiss = false
    @State private var isParentDismissalInProgress = false
    @State private var pendingDismissalResetTask: Task<Void, Never>?

    init(
        initialText: String,
        dismissKeyboard: Binding<Bool>,
        requestInitialFocus: Bool = false,
        commitTitleNonce: Int,
        placeholder: String,
        font: Font,
        onBlur: @escaping (String) -> Void,
        onEditingActiveChanged: @escaping (Bool) -> Void
    ) {
        self.initialText = initialText
        _dismissKeyboard = dismissKeyboard
        self.requestInitialFocus = requestInitialFocus
        self.commitTitleNonce = commitTitleNonce
        self.placeholder = placeholder
        self.font = font
        self.onBlur = onBlur
        self.onEditingActiveChanged = onEditingActiveChanged
        _draftText = State(initialValue: initialText)
        _lastSyncedInitialText = State(initialValue: initialText)
    }

    var body: some View {
        TextField(placeholder, text: $draftText, axis: .vertical)
            .textFieldStyle(.plain)
            .font(font)
            .foregroundStyle(.primary)
            .lineLimit(1...)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            .multilineTextAlignment(.leading)
            .textInputAutocapitalization(.sentences)
            .focused($isTitleFocused)
            .accessibilityIdentifier(AccessibilityIdentifiers.recipeTitleField)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if isTitleFocused {
                        Spacer()
                        Button("edit.done") {
                            isIntentionalFieldDismiss = true
                            isTitleFocused = false
                        }
                        .appToolbarTextButton()
                        .accessibilityIdentifier(AccessibilityIdentifiers.recipeTitleKeyboardDone)
                    }
                }
            }
            .onChange(of: isTitleFocused) { _, focused in
                handleFocusChange(focused)
            }
            .onChange(of: dismissKeyboard) { _, shouldDismiss in
                guard shouldDismiss else { return }
                isParentDismissalInProgress = true
                isTitleFocused = false
                resetDismissKeyboardBinding()
            }
            .onChange(of: commitTitleNonce) { _, nonce in
                guard nonce != appliedCommitNonce else { return }
                appliedCommitNonce = nonce
                commitBlur()
            }
            .onChange(of: initialText) { _, newValue in
                applyExternalInitialTextIfNeeded(newValue)
            }
            .task(id: requestInitialFocus) {
                await requestInitialFocusIfNeeded()
            }
            .onDisappear {
                pendingDismissalResetTask?.cancel()
            }
    }

    private func requestInitialFocusIfNeeded() async {
        guard requestInitialFocus, !didApplyInitialFocus else { return }
        await Task.yield()
        guard !dismissKeyboard, !isParentDismissalInProgress else { return }
        didApplyInitialFocus = true
        isTitleFocused = true
    }

    private func handleFocusChange(_ focused: Bool) {
        if focused {
            isParentDismissalInProgress = false
            lastCommittedBlurText = nil
            notifyEditingActive(true)
            return
        }

        let parentDismissed = dismissKeyboard || isParentDismissalInProgress
        let intentionallyDismissed = isIntentionalFieldDismiss
        isIntentionalFieldDismiss = false
        commitBlur()
        notifyEditingActive(false)

        guard !parentDismissed, !intentionallyDismissed else {
            isParentDismissalInProgress = false
            return
        }

        // Web parity: an incidental blur saves the draft but keeps the title editor active.
        Task { @MainActor in
            await Task.yield()
            guard !self.dismissKeyboard,
                  !self.isParentDismissalInProgress,
                  !self.isTitleFocused else { return }
            self.isTitleFocused = true
        }
    }

    private func resetDismissKeyboardBinding() {
        pendingDismissalResetTask?.cancel()
        pendingDismissalResetTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            dismissKeyboard = false
            isParentDismissalInProgress = false
        }
    }

    /// Sync from `recipe.name` only when it is newer than the last blur commit.
    private func applyExternalInitialTextIfNeeded(_ newInitialText: String) {
        guard !isTitleFocused, newInitialText != lastSyncedInitialText else { return }

        let fieldText = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let committed = lastCommittedBlurText,
           fieldText == committed,
           newInitialText != committed {
            return
        }
        guard fieldText != newInitialText else {
            lastSyncedInitialText = newInitialText
            return
        }

        draftText = newInitialText
        lastSyncedInitialText = newInitialText
        lastCommittedBlurText = newInitialText
    }

    private func commitBlur() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != lastCommittedBlurText else { return }

        lastCommittedBlurText = trimmed
        if draftText != trimmed {
            draftText = trimmed
        }
        lastSyncedInitialText = trimmed

        // Keep the callback off the current SwiftUI update pass because it mutates
        // the parent's observed recipe-edit state.
        DispatchQueue.main.async {
            self.onBlur(trimmed)
        }
    }

    private func notifyEditingActive(_ active: Bool) {
        DispatchQueue.main.async {
            self.onEditingActiveChanged(active)
        }
    }
}
//
//  RecipeTitleTextField.swift
//  RecipeScalerNative
//
//  Web parity: uncontrolled UITextView while typing; persist on blur / explicit dismiss (Done).
//

import SwiftUI
import UIKit

/// Grows vertically with content; stable first responder during height changes.
final class GrowingTitleTextView: UITextView {
    var minHeight: CGFloat = 34
    /// While editing, never shrink below the tallest height seen (prevents layout-driven resign on delete).
    var editingHeightFloor: CGFloat = 0
    private var lastLayoutWidth: CGFloat = 0
    private var cachedNaturalHeight: CGFloat = 0
    private var cachedNaturalWidth: CGFloat = 0

    func invalidateNaturalHeightCache() {
        cachedNaturalHeight = 0
        cachedNaturalWidth = 0
    }

    func naturalContentHeight(forWidth width: CGFloat) -> CGFloat {
        guard width > 0 else { return minHeight }
        if cachedNaturalWidth == width, cachedNaturalHeight >= minHeight {
            return cachedNaturalHeight
        }
        let fitted = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let height = max(minHeight, ceil(fitted.height))
        cachedNaturalWidth = width
        cachedNaturalHeight = height
        return height
    }

    override var intrinsicContentSize: CGSize {
        let width = bounds.width > 0 ? bounds.width : (superview?.bounds.width ?? 0)
        guard width > 0 else {
            let floor = editingHeightFloor > 0 ? max(minHeight, editingHeightFloor) : minHeight
            return CGSize(width: UIView.noIntrinsicMetric, height: floor)
        }
        let natural = naturalContentHeight(forWidth: width)
        let height = editingHeightFloor > 0 ? max(editingHeightFloor, natural) : natural
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        guard width > 0, abs(width - lastLayoutWidth) > 0.5 else { return }
        lastLayoutWidth = width
        invalidateNaturalHeightCache()
        invalidateIntrinsicContentSize()
    }

    override var text: String! {
        didSet {
            if text != oldValue {
                invalidateNaturalHeightCache()
            }
        }
    }

    override var font: UIFont? {
        didSet {
            if font != oldValue {
                invalidateNaturalHeightCache()
            }
        }
    }

    func resetEditingHeightFloor() {
        editingHeightFloor = 0
        invalidateIntrinsicContentSize()
    }

    func recordEditingHeightFloor() {
        let width = bounds.width > 0 ? bounds.width : (superview?.bounds.width ?? 0)
        let natural = naturalContentHeight(forWidth: width)
        if natural > editingHeightFloor {
            editingHeightFloor = natural
            invalidateIntrinsicContentSize()
        }
    }
}

/// Multiline recipe title editor (web: `defaultValue` + `onBlur` → Y.Doc).
struct RecipeTitleTextField: UIViewRepresentable {
    /// Shown when the field is created or when the recipe name changes externally (not while typing).
    var initialText: String
    @Binding var dismissKeyboard: Bool
    /// Focus title once when opening a newly created recipe in edit mode.
    var requestInitialFocus: Bool = false
    /// Incremented by parent on Done to flush uncommitted title text before `finishEditing`.
    var commitTitleNonce: Int
    var placeholder: String
    var font: UIFont
    var onBlur: (String) -> Void
    var onEditingActiveChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> GrowingTitleTextView {
        let view = GrowingTitleTextView()
        view.font = font
        view.textColor = .label
        view.backgroundColor = .clear
        view.text = initialText
        view.delegate = context.coordinator
        view.isScrollEnabled = false
        view.isEditable = true
        view.isSelectable = true
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.lineBreakMode = .byWordWrapping
        view.autocapitalizationType = .sentences
        view.adjustsFontForContentSizeCategory = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        context.coordinator.textView = view
        context.coordinator.lastSyncedInitialText = initialText
        context.coordinator.updatePlaceholder(on: view)
        view.inputAccessoryView = context.coordinator.makeKeyboardToolbar()
        context.coordinator.scheduleInitialFocusIfNeeded(on: view)
        return view
    }

    func updateUIView(_ uiView: GrowingTitleTextView, context: Context) {
        context.coordinator.parent = self

        if uiView.font != font {
            uiView.font = font
        }

        if commitTitleNonce != context.coordinator.appliedCommitNonce {
            context.coordinator.appliedCommitNonce = commitTitleNonce
            context.coordinator.commitBlurIfChanged(from: uiView, reason: "done_flush")
        }

        if dismissKeyboard {
            // Blur save runs in `textViewDidEndEditing` after resign — avoid duplicate + state during update.
            if uiView.editingHeightFloor > 0 {
                uiView.resetEditingHeightFloor()
            }
            if uiView.isFirstResponder, !context.coordinator.isResigningFromSwiftUI {
                context.coordinator.isResigningFromSwiftUI = true
                uiView.resignFirstResponder()
                context.coordinator.isResigningFromSwiftUI = false
            }
            context.coordinator.scheduleDismissKeyboardReset()
        } else if !uiView.isFirstResponder {
            context.coordinator.applyExternalInitialTextIfNeeded(initialText, on: uiView)
        }

        if uiView.text.isEmpty || !uiView.isFirstResponder {
            context.coordinator.updatePlaceholder(on: uiView)
        }

        context.coordinator.scheduleInitialFocusIfNeeded(on: uiView)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: RecipeTitleTextField
        weak var textView: GrowingTitleTextView?
        var isResigningFromSwiftUI = false
        /// Keyboard accessory Done — dismiss field only, not recipe edit mode.
        var isIntentionalFieldDismiss = false
        var lastSyncedInitialText = ""
        var lastCommittedBlurText: String?
        var appliedCommitNonce = 0
        private var didApplyInitialFocus = false
        private var lastPlaceholderWidth: CGFloat = -1

        private let placeholderTag = 9_901

        init(parent: RecipeTitleTextField) {
            self.parent = parent
        }

        private func setEditingActive(_ active: Bool) {
            // Always defer to the next runloop tick, even when already on the main thread.
            // `updateUIView` / `textViewDidEndEditing` can run synchronously inside a SwiftUI
            // render pass, and mutating `parent.onEditingActiveChanged` (which writes back
            // into `@Observable`/`@Published` state) during that pass triggers
            // "Publishing changes from within view updates is not allowed".
            DispatchQueue.main.async {
                self.parent.onEditingActiveChanged(active)
            }
        }

        func scheduleInitialFocusIfNeeded(on textView: GrowingTitleTextView) {
            guard parent.requestInitialFocus, !didApplyInitialFocus else { return }
            didApplyInitialFocus = true
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView, !self.parent.dismissKeyboard, !textView.isFirstResponder else { return }
                _ = textView.becomeFirstResponder()
                self.setEditingActive(true)
            }
        }

        func makeKeyboardToolbar() -> UIToolbar {
            let toolbar = UIToolbar()
            let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
            let done = UIBarButtonItem(
                title: String(localized: "edit.done"),
                style: AppChromeAppearance.doneBarButtonItemStyle,
                target: self,
                action: #selector(keyboardDoneTapped)
            )
            done.accessibilityIdentifier = AccessibilityIdentifiers.recipeTitleKeyboardDone
            // Assign items BEFORE sizeToFit; otherwise UIToolbar's content view is laid out
            // with width==0 and UIKit logs "Unable to simultaneously satisfy constraints".
            toolbar.items = [spacer, done]
            toolbar.sizeToFit()
            return toolbar
        }

        @objc func keyboardDoneTapped() {
            guard let textView else { return }
            isIntentionalFieldDismiss = true
            if textView.isFirstResponder {
                isResigningFromSwiftUI = true
                textView.resignFirstResponder()
                isResigningFromSwiftUI = false
            } else {
                isIntentionalFieldDismiss = false
            }
        }

        func scheduleDismissKeyboardReset() {
            DispatchQueue.main.async {
                if self.parent.dismissKeyboard {
                    self.parent.dismissKeyboard = false
                }
            }
        }

        /// Sync from `recipe.name` only when it is newer than the last blur commit (avoids flashing stale text after keyboard Done).
        func applyExternalInitialTextIfNeeded(_ initialText: String, on uiView: GrowingTitleTextView) {
            guard initialText != lastSyncedInitialText else { return }
            let fieldText = (uiView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let committed = lastCommittedBlurText,
               fieldText == committed,
               initialText != committed {
                return
            }
            guard fieldText != initialText else {
                lastSyncedInitialText = initialText
                return
            }
            uiView.text = initialText
            lastSyncedInitialText = initialText
            lastCommittedBlurText = initialText
            updatePlaceholder(on: uiView)
            uiView.invalidateNaturalHeightCache()
            uiView.invalidateIntrinsicContentSize()
        }

        func textViewDidChange(_ textView: UITextView) {
            updatePlaceholder(on: textView)
            if let growing = textView as? GrowingTitleTextView {
                growing.recordEditingHeightFloor()
            } else {
                textView.invalidateIntrinsicContentSize()
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            lastCommittedBlurText = nil
            setEditingActive(true)
            DispatchQueue.main.async { [weak textView] in
                guard let textView, let growing = textView as? GrowingTitleTextView else { return }
                growing.recordEditingHeightFloor()
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            let recipeDoneDismiss = parent.dismissKeyboard
            let fieldDoneDismiss = isIntentionalFieldDismiss
            isIntentionalFieldDismiss = false
            let blurReason: String
            if recipeDoneDismiss {
                blurReason = "dismiss_keyboard"
            } else if fieldDoneDismiss {
                blurReason = "keyboard_done"
            } else {
                blurReason = "end_editing"
            }
            commitBlur(from: textView, reason: blurReason)
            updatePlaceholder(on: textView)
            if let growing = textView as? GrowingTitleTextView {
                growing.resetEditingHeightFloor()
            }
            setEditingActive(false)
            guard !recipeDoneDismiss, !fieldDoneDismiss else { return }
            // Web: stay in edit mode after spurious blur; reclaim keyboard.
            DispatchQueue.main.async { [weak textView] in
                guard let textView, !self.parent.dismissKeyboard, !textView.isFirstResponder else { return }
                _ = textView.becomeFirstResponder()
                self.setEditingActive(true)
            }
        }

        func commitBlurIfChanged(from textView: UITextView, reason: String) {
            let trimmed = (textView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed != lastCommittedBlurText else { return }
            commitBlur(from: textView, reason: reason, trimmed: trimmed)
        }

        func commitBlur(from textView: UITextView, reason: String, trimmed: String? = nil) {
            let trimmed = trimmed ?? (textView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == lastCommittedBlurText { return }
            lastCommittedBlurText = trimmed
            if textView.text != trimmed {
                textView.text = trimmed
            }
            lastSyncedInitialText = trimmed
            // Always hop to the next runloop, even on the main thread: `commitBlur` can be
            // reached synchronously from `updateUIView` -> `resignFirstResponder` ->
            // `textViewDidEndEditing`, and writing `parent.onBlur` (which mutates
            // `@State` / `@Observable` recipe-edit state) during a SwiftUI render pass
            // triggers "Publishing changes from within view updates is not allowed".
            DispatchQueue.main.async {
                self.parent.onBlur(trimmed)
            }
        }

        func updatePlaceholder(on textView: UITextView) {
            updatePlaceholderImpl(on: textView)
        }

        private func updatePlaceholderImpl(on textView: UITextView) {
            let isEmpty = (textView.text ?? "").isEmpty
            let label: UILabel
            if let existing = textView.viewWithTag(placeholderTag) as? UILabel {
                label = existing
            } else {
                label = UILabel()
                label.tag = placeholderTag
                label.numberOfLines = 0
                label.isUserInteractionEnabled = false
                textView.addSubview(label)
            }
            label.font = parent.font
            label.text = parent.placeholder
            label.textColor = .placeholderText
            label.isHidden = !isEmpty
            let width = max(0, textView.bounds.width - textView.textContainer.lineFragmentPadding * 2)
            guard width > 0 else { return }
            if abs(width - lastPlaceholderWidth) > 0.5 || label.frame.height == 0 {
                lastPlaceholderWidth = width
                label.preferredMaxLayoutWidth = width
                label.frame = CGRect(
                    x: textView.textContainerInset.left,
                    y: textView.textContainerInset.top,
                    width: width,
                    height: 0
                )
                label.sizeToFit()
                label.frame.size.width = width
            }
        }
    }
}
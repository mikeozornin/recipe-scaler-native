//
//  AssistantMessageFooter.swift
//  RecipeScalerNative
//
//  Renders the interactive widget (P2.3) and follow-up suggestions (P3.1) attached to
//  the last assistant message. Mirrors:
//    - `recipe-scaler-web/recipe-scaler/src/components/assistant/assistant-widget.tsx`
//    - `recipe-scaler-web/recipe-scaler/src/components/assistant/assistant-follow-ups.tsx`
//    - `recipe-scaler-web/recipe-scaler/src/components/assistant/assistant-message-list.tsx` (timestamp + copy)
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct AssistantMessageFooter: View {
    let message: AssistantMessage
    let isLastMessage: Bool
    let isSending: Bool
    let onWidgetSubmit: (_ value: String, _ recipeAttachment: AssistantRecipeAttachment?) -> Void
    let onFollowUp: (AssistantFollowUpSuggestion) -> Void

    /// Single-shot lock: once any widget option / suggestion is tapped, the footer becomes inert.
    @State private var widgetSubmitted = false
    @State private var followUpSubmitted = false

    private var widget: AssistantInteractiveWidget? {
        guard message.role == "assistant",
              !message.isStreaming,
              isLastMessage,
              !isSending,
              !widgetSubmitted else { return nil }
        return message.metadata?.interactiveWidget
    }

    private var followUps: [AssistantFollowUpSuggestion] {
        guard message.role == "assistant",
              !message.isStreaming,
              isLastMessage,
              !isSending,
              widget == nil,
              !followUpSubmitted else { return [] }
        return (message.metadata?.followUpSuggestions ?? []).prefix(3).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let widget {
                AssistantWidgetView(widget: widget) { value, attachment in
                    widgetSubmitted = true
                    onWidgetSubmit(value, attachment)
                }
            }
            if !followUps.isEmpty {
                AssistantFollowUpsView(suggestions: followUps) { suggestion in
                    followUpSubmitted = true
                    onFollowUp(suggestion)
                }
            }
        }
    }
}

// MARK: - Timestamp + copy row (mirrors web `assistant-message-list.tsx` footer; always visible on mobile)

enum AssistantMessageTimestampFormatter {
    static func format(createdAt: Date, locale: Locale) -> String {
        let calendar = Calendar.current
        let now = Date()

        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none

        if calendar.isDate(createdAt, inSameDayAs: now) {
            return timeFormatter.string(from: createdAt)
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(createdAt, inSameDayAs: yesterday) {
            let yesterdayLabel = Bundle.currentLocalizedString("assistant.timestamp.yesterday")
            return "\(yesterdayLabel), \(timeFormatter.string(from: createdAt))"
        }

        if calendar.component(.year, from: createdAt) == calendar.component(.year, from: now) {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate("MMMdHHmm")
            return formatter.string(from: createdAt)
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMMdyyyy")
        return formatter.string(from: createdAt)
    }
}

enum AssistantMessageCopyText {
    static func text(for message: AssistantMessage) -> String {
        guard message.role == "user" else {
            return message.text
        }

        let attachments = message.metadata?.attachments ?? []
        guard !attachments.isEmpty else {
            return message.text
        }

        let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return attachments
                .map { attachment in
                    let name = attachment.recipeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return name.isEmpty ? attachment.recipeId : name
                }
                .joined(separator: ", ")
        }

        if attachments.count == 1,
           let first = attachments.first,
           trimmed == first.recipeId {
            let name = first.recipeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? first.recipeId : name
        }

        return message.text
    }
}

struct AssistantMessageMetaRow: View {
    let message: AssistantMessage
    let isUser: Bool

    @Environment(\.locale) private var locale
    @State private var isCopied = false

    private static let copyButtonSize: CGFloat = 28
    private static let copyIconFont = Font.system(size: 14)

    private var copyText: String { AssistantMessageCopyText.text(for: message) }
    private var canCopy: Bool {
        !copyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var formattedTimestamp: String {
        AssistantMessageTimestampFormatter.format(createdAt: message.createdAt, locale: locale)
    }

    var body: some View {
        HStack(spacing: 6) {
            if isUser {
                if canCopy {
                    copyButton
                }
                Text(formattedTimestamp)
            } else {
                Text(formattedTimestamp)
                if canCopy {
                    copyButton
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, isUser ? 4 : 0)
        .accessibilityElement(children: .combine)
    }

    private var copyButton: some View {
        Button {
            copyToPasteboard(copyText)
            isCopied = true
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                isCopied = false
            }
        } label: {
            ZStack {
                Image(systemName: "doc.on.doc")
                    .opacity(isCopied ? 0 : 1)
                Image(systemName: "checkmark.circle")
                    .opacity(isCopied ? 1 : 0)
            }
            .font(Self.copyIconFont)
            .frame(width: Self.copyButtonSize, height: Self.copyButtonSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("assistant.copy-message"))
        .accessibilityIdentifier("assistant_message_copy_button")
    }

    private func copyToPasteboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
}

// MARK: - Widget view (P2.3)

struct AssistantWidgetView: View {
    let widget: AssistantInteractiveWidget
    let onSubmit: (_ value: String, _ recipeAttachment: AssistantRecipeAttachment?) -> Void

    var body: some View {
        switch widget {
        case .quickReplies(let options):
            AssistantQuickRepliesWidget(options: options, onSubmit: onSubmit)
        case .select(let options):
            AssistantSelectWidget(options: options, onSubmit: onSubmit)
        case .numberInput(let config):
            AssistantNumberInputWidget(config: config, onSubmit: onSubmit)
        }
    }
}

/// A UUID-shaped value indicates a recipe attachment (mirrors web `assistant-widget.tsx:25-30`).
private let genericUUIDRegex = try? NSRegularExpression(
    pattern: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
)

private func looksLikeUUID(_ value: String) -> Bool {
    guard let regex = genericUUIDRegex else { return false }
    let range = NSRange(value.startIndex..., in: value)
    return regex.firstMatch(in: value, options: [], range: range) != nil
}

private struct AssistantQuickRepliesWidget: View {
    let options: [AssistantWidgetOption]
    let onSubmit: (String, AssistantRecipeAttachment?) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(options) { option in
                Button {
                    let attachment: AssistantRecipeAttachment? = looksLikeUUID(option.value)
                        ? AssistantRecipeAttachment(recipeId: option.value, recipeName: option.label, recipeColor: nil)
                        : nil
                    onSubmit(option.value, attachment)
                } label: {
                    Text(option.label)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("assistant_widget_quick_reply_\(option.id)")
            }
        }
    }
}

private struct AssistantSelectWidget: View {
    let options: [AssistantWidgetOption]
    let onSubmit: (String, AssistantRecipeAttachment?) -> Void

    @State private var selection: AssistantWidgetOption?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(selection: $selection) {
                ForEach(options) { option in
                    Text(option.label).tag(option as AssistantWidgetOption?)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.menu)
            .labelsHidden()

            Button("assistant.send") {
                guard let selected = selection else { return }
                let attachment: AssistantRecipeAttachment? = AssistantRecipeAttachment(
                    recipeId: selected.value,
                    recipeName: selected.label,
                    recipeColor: nil
                )
                onSubmit(selected.value, attachment)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selection == nil)
            .accessibilityIdentifier("assistant_widget_select_submit")
        }
        .onAppear {
            if selection == nil { selection = options.first }
        }
    }
}

private struct AssistantNumberInputWidget: View {
    let config: AssistantInteractiveWidget.NumberInput
    let onSubmit: (String, AssistantRecipeAttachment?) -> Void

    @State private var value: Double = 1

    private var defaultValue: Double {
        config.defaultValue ?? config.min ?? 1
    }

    var body: some View {
        HStack(spacing: 8) {
            Stepper(value: $value, in: stepperRange, step: config.step ?? 1) {
                HStack(spacing: 4) {
                    Text(formattedValue)
                    if let unit = config.unit, !unit.isEmpty {
                        Text(unit).foregroundStyle(.secondary)
                    }
                }
            }
            Button("assistant.send") {
                onSubmit(formattedValue, nil)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("assistant_widget_number_input_submit")
        }
        .onAppear { value = defaultValue }
    }

    private var stepperRange: ClosedRange<Double> {
        let lower = config.min ?? -Double.greatestFiniteMagnitude
        let upper = config.max ?? Double.greatestFiniteMagnitude
        return lower...upper
    }

    private var formattedValue: String {
        // Drop trailing ".0" for integer-valued steps; keep precision for fractional ones.
        if config.step.map { $0.truncatingRemainder(dividingBy: 1) == 0 } ?? true
            && value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return String(value)
    }
}

// MARK: - Follow-ups view (P3.1)

struct AssistantFollowUpsView: View {
    let suggestions: [AssistantFollowUpSuggestion]
    let onTap: (AssistantFollowUpSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(suggestions) { suggestion in
                Button {
                    onTap(suggestion)
                } label: {
                    Text(suggestion.value)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("assistant_follow_up_\(suggestion.id)")
            }
        }
    }
}

// MARK: - FlowLayout (minimal wrap layout for quick replies)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        return arrange(subviews: subviews, maxWidth: maxWidth).bounds
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(subviews: subviews, maxWidth: bounds.width)
        for (subview, frame) in zip(subviews, arrangement.frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private struct Arrangement {
        var frames: [CGRect]
        var bounds: CGSize
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> Arrangement {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var frames: [CGRect] = []
        var totalWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, x)
        }
        return Arrangement(frames: frames, bounds: CGSize(width: totalWidth, height: y + rowHeight))
    }
}

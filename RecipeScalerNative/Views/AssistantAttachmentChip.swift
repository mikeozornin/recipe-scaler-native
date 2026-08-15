//
//  AssistantAttachmentChip.swift
//  RecipeScalerNative
//
//  Shared recipe-attachment chip primitives for the assistant UI.
//  Mirrors `recipe-scaler-web/recipe-scaler/src/components/assistant/assistant-recipe-chip.tsx`.
//  Composer (removable) and message bubbles (read-only) wrap these — do not put input-only
//  or message-only behavior here.
//

import SwiftUI

// MARK: - Title split (web `getRecipeChipDisplay`)

/// Splits a recipe title into the leading emoji (shown instead of the color dot)
/// and the display name without it.
enum AssistantRecipeChipDisplay {
    static func split(_ name: String) -> (emoji: String?, displayName: String) {
        let emoji = RecipeTitleEmoji.leadingEmoji(in: name)
        let stripped = RecipeTitleEmoji.titleWithoutLeadingEmoji(name)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (emoji, stripped.isEmpty ? name : stripped)
    }
}

// MARK: - Leading (web `RecipeChipLeading`)

/// Leading emoji from the recipe title when present, otherwise the recipe color dot.
struct AssistantAttachmentChipLeading: View {
    let emoji: String?
    let colorHex: String?

    var body: some View {
        if let emoji {
            Text(verbatim: emoji)
                .font(.system(size: 14))
                .lineLimit(1)
        } else {
            Circle()
                .fill(Color(hex: colorHex ?? "") ?? .accentColor)
                .frame(width: 8, height: 8)
        }
    }
}

// MARK: - Label (leading + truncated name, no chrome / no remove)

struct AssistantAttachmentChipLabel: View {
    let attachment: AssistantRecipeAttachment

    private var fullTitle: String {
        attachment.recipeName ?? attachment.recipeId
    }

    var body: some View {
        let display = AssistantRecipeChipDisplay.split(fullTitle)
        HStack(spacing: 6) {
            AssistantAttachmentChipLeading(emoji: display.emoji, colorHex: attachment.recipeColor)
            Text(display.displayName)
                .lineLimit(1)
        }
    }
}

// MARK: - Chrome (web `assistantRecipeAttachmentChipClassName`)

extension View {
    /// Secondary badge capsule with footnote typography.
    func assistantAttachmentChipChrome() -> some View {
        font(Font(AppTypography.footnoteUIFont))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.12))
            .clipShape(Capsule())
    }
}

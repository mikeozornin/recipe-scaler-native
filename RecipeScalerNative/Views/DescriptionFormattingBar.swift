//
//  DescriptionFormattingBar.swift
//  RecipeScalerNative
//
//  Native sticky toolbar for inline description editor (019).
//

import SwiftUI

enum DescriptionFormattingBarLayoutMetrics {
    /// Bottom scroll clearance while the bar is shown in `safeAreaInset`.
    static let scrollClearanceHeight: CGFloat = 52
}

struct DescriptionFormattingBar: View {
    @Bindable var bridge: DescriptionEditorBridge
    var accentColor: Color
    var onDone: (() -> Void)?
    var onMarkTimer: (() -> Void)?
    var onMarkIngredient: (() -> Void)?
    var onParseRecipe: (() -> Void)?

    private var selection: DescriptionEditorSelectionState { bridge.selectionState }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                barButton(
                    systemName: "textformat.size.larger",
                    labelKey: "editor.heading",
                    isActive: selection.heading1,
                    isEnabled: selection.canHeading1
                ) {
                    bridge.sendCommand(name: "toggleHeading1")
                }

                barButton(
                    systemName: "bold",
                    labelKey: "editor.bold",
                    isActive: selection.bold,
                    isEnabled: selection.canBold
                ) {
                    bridge.sendCommand(name: "toggleBold")
                }

                barButton(
                    systemName: "highlighter",
                    labelKey: "editor.highlight",
                    isActive: selection.highlight,
                    isEnabled: selection.canHighlight
                ) {
                    bridge.sendCommand(name: "toggleHighlight")
                }

                barButton(
                    systemName: "list.number",
                    labelKey: "editor.ordered-list",
                    isActive: selection.orderedList,
                    isEnabled: selection.canOrderedList
                ) {
                    bridge.sendCommand(name: "toggleOrderedList")
                }

                barButton(
                    systemName: "list.bullet",
                    labelKey: "editor.bullet-list",
                    isActive: selection.bulletList,
                    isEnabled: selection.canBulletList
                ) {
                    bridge.sendCommand(name: "toggleBulletList")
                }

                divider

                barButton(
                    systemName: "alarm",
                    labelKey: selection.canMarkTimer ? "editor.mark-as-timer" : "editor.mark-as-timer-disabled",
                    isActive: false,
                    isEnabled: selection.canMarkTimer
                ) {
                    bridge.sendCommand(name: "prepareMarkupSelection")
                    onMarkTimer?()
                }

                barButton(
                    systemName: "fork.knife",
                    labelKey: selection.canMarkIngredient ? "editor.mark-as-ingredient" : "editor.mark-as-ingredient-disabled",
                    isActive: false,
                    isEnabled: selection.canMarkIngredient
                ) {
                    bridge.sendCommand(name: "prepareMarkupSelection")
                    onMarkIngredient?()
                }

                if onParseRecipe != nil {
                    divider

                    barButton(
                        systemName: "sparkles",
                        labelKey: "llm.parse-recipe",
                        isActive: false,
                        isEnabled: true
                    ) {
                        onParseRecipe?()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            }

            if let onDone {
                divider
                    .padding(.leading, 4)
                Button("edit.done", action: onDone)
                    .appToolbarTextButton()
                    .padding(.leading, 4)
                    .padding(.trailing, 12)
                    .accessibilityIdentifier(AccessibilityIdentifiers.descriptionEditorKeyboardDone)
            }
        }
        .background(.bar)
        .accessibilityIdentifier("description_formatting_bar")
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 1, height: 28)
            .padding(.horizontal, 4)
    }

    private func barButton(
        systemName: String,
        labelKey: LocalizedStringKey,
        isActive: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            AppSymbol.toolbarImage(systemName)
                .resizable()
                .scaledToFit()
                .frame(width: AppToolbarStyle.iconSide, height: AppToolbarStyle.iconSide)
                .frame(width: 40, height: 36)
                .foregroundStyle(isActive ? accentColor : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isActive ? accentColor.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(Text(labelKey))
    }
}

//
//  YDocRecipeDetailEditHeader.swift
//  RecipeScalerNative
//
//  Review 2026.09.04 №20 — extracted from `YDocRecipeDetailView.swift`:
//  the edit-mode header (title field + accent color picker) and the
//  keyboard safe-area policy modifier.
//

import SwiftUI
import RecipeScalerCore

struct RecipeEditHeaderBindable: View {
    @Bindable var viewModel: RecipeEditViewModel
    let initialTitle: String
    @Binding var pickerColor: Color
    @Binding var dismissTitleKeyboard: Bool
    var commitTitleNonce: Int
    var requestInitialFocus: Bool = false
    var onTitleBlur: (String) -> Void
    var onEditingActiveChanged: (Bool) -> Void
    @Environment(\.locale) private var locale

    private var titleFont: Font {
        AppTypography.display(AppTypography.recipeTitleSize)
    }

    private var titlePlaceholder: String {
        _ = locale
        return Bundle.currentLocalizedString("edit.name.placeholder")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                RecipeTitleTextField(
                    initialText: initialTitle,
                    dismissKeyboard: $dismissTitleKeyboard,
                    requestInitialFocus: requestInitialFocus,
                    commitTitleNonce: commitTitleNonce,
                    placeholder: titlePlaceholder,
                    font: titleFont,
                    onBlur: onTitleBlur,
                    onEditingActiveChanged: onEditingActiveChanged
                )
                    .id("recipe-title-editor")
                    .frame(maxWidth: .infinity, alignment: .leading)

                ColorPicker("", selection: $pickerColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 32, height: 32)
            }
            .padding(.horizontal)
            .onAppear {
                // Defer to the next runloop tick: writing `pickerColor` (a @State/@Binding
                // rooted in YDocRecipeDetailView) synchronously from `.onAppear` mutates
                // observed state during the SwiftUI layout pass, which triggers
                // "Publishing changes from within view updates is not allowed".
                let initial = RecipeAccentColor.color(from: viewModel.draftColor)
                DispatchQueue.main.async {
                    pickerColor = initial
                }
            }
            .onChange(of: pickerColor) { _, newColor in
                viewModel.draftColor = RecipeAccentColor.storedValue(from: newColor)
            }
        }
    }
}

struct DescriptionEditorScrollKeyboardPolicy: ViewModifier {
    var ignoresKeyboardSafeArea: Bool

    func body(content: Content) -> some View {
        content.ignoresSafeArea(
            ignoresKeyboardSafeArea ? .keyboard : SafeAreaRegions(),
            edges: .bottom
        )
    }
}

extension View {
    /// Dismisses an overlay on vertical scroll without stealing horizontal List row swipes.
    func dismissPopoverOnVerticalDrag(isActive: Bool, onDismiss: @escaping () -> Void) -> some View {
        modifier(DismissPopoverOnVerticalDragModifier(isActive: isActive, onDismiss: onDismiss))
    }
}

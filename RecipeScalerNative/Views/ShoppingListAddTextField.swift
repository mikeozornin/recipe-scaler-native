//
//  ShoppingListAddTextField.swift
//  RecipeScalerNative
//

import SwiftUI
import UIKit

/// Bottom shopping add field: localized Return key («Добавить») and `shouldReturn` = false
/// so the keyboard stays up while chaining manual items.
struct ShoppingListAddTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var onAdd: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.borderStyle = .none
        field.font = AppTypography.bodyUIFont
        field.autocorrectionType = .default
        field.returnKeyType = .continue
        field.enablesReturnKeyAutomatically = true
        field.delegate = context.coordinator
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textChanged),
            for: .editingChanged
        )
        field.accessibilityIdentifier = AccessibilityIdentifiers.shoppingAddField
        context.coordinator.applyReturnKeyTitle(to: field)
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        if uiView.text != text {
            uiView.text = text
        }
        context.coordinator.applyReturnKeyTitle(to: uiView)

        if isFocused, !uiView.isFirstResponder {
            DispatchQueue.main.async {
                guard uiView.window != nil else { return }
                uiView.becomeFirstResponder()
            }
        } else if !isFocused, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: ShoppingListAddTextField

        init(parent: ShoppingListAddTextField) {
            self.parent = parent
        }

        func applyReturnKeyTitle(to field: UITextField) {
            let title = Bundle.currentLocalizedString("shopping.add")
            let item = UIBarButtonItem(
                title: title,
                style: .plain,
                target: nil,
                action: nil
            )
            item.isEnabled = false
            field.inputAssistantItem.leadingBarButtonGroups = [
                UIBarButtonItemGroup(barButtonItems: [item], representativeItem: nil),
            ]
        }

        @objc func textChanged(_ sender: UITextField) {
            parent.text = sender.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onAdd()
            return false
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            if !parent.isFocused {
                parent.isFocused = true
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            if parent.isFocused {
                parent.isFocused = false
            }
        }
    }
}
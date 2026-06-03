//
//  AccountCheckmarkSelectionView.swift
//  RecipeScalerNative
//

import SwiftUI

/// iOS Settings–style list: one option per row, blue checkmark on the right.
struct AccountCheckmarkSelectionView<Option: Hashable & Identifiable>: View {
    let navigationTitle: LocalizedStringKey
    let options: [Option]
    let selection: Option
    let title: (Option) -> LocalizedStringKey
    let onSelect: (Option) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(options) { option in
                Button {
                    guard option != selection else {
                        dismiss()
                        return
                    }
                    onSelect(option)
                    dismiss()
                } label: {
                    HStack {
                        Text(title(option))
                            .foregroundStyle(.primary)
                        Spacer()
                        if option == selection {
                            Image(systemName: "checkmark")
                                .font(AppTypography.bodySemibold)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .appListBodyTypography()
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Parent row: label + current value (navigates to nested picker).
struct AccountSettingsNavigationRow: View {
    let label: LocalizedStringKey
    let value: LocalizedStringKey

    var body: some View {
        HStack {
            Text(label)
                .font(AppTypography.body)
            Spacer()
            Text(value)
                .font(AppTypography.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
//
//  RemindersListPickerView.swift
//  RecipeScalerNative
//
//  iOS Settings–style list picker for choosing the target Apple Reminders list.
//  Top section: the dedicated «Recipe Scaler» list option.
//  Second section: all existing user Reminders lists.
//

import SwiftUI
import EventKit

struct RemindersListPickerView: View {
    let availableLists: [EKCalendar]
    let currentIdentifier: String
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            // MARK: - Dedicated list option
            Section {
                row(
                    title: "account.reminders.list.create-dedicated",
                    identifier: RemindersSyncPreferences.dedicatedListSentinel
                )
            }

            // MARK: - Existing lists
            if !availableLists.isEmpty {
                Section {
                    ForEach(availableLists, id: \.calendarIdentifier) { calendar in
                        row(title: calendar.title, identifier: calendar.calendarIdentifier)
                    }
                } header: {
                    AppSectionHeader("account.reminders.list.existing-header")
                }
                .appListSectionHeaderStyle()
            }
        }
        .listStyle(.insetGrouped)
        .appListBodyTypography()
        .localizedNavigationTitle("account.reminders.list.label")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func row(title: LocalizedStringKey, identifier: String) -> some View {
        Button {
            guard identifier != currentIdentifier else {
                dismiss()
                return
            }
            onSelect(identifier)
            dismiss()
        } label: {
            HStack {
                Text(title)
                    .appBody()
                    .foregroundStyle(.primary)
                Spacer()
                if identifier == currentIdentifier {
                    Image(systemName: "checkmark")
                        .font(AppTypography.bodySemibold)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    @ViewBuilder
    private func row(title: String, identifier: String) -> some View {
        row(title: LocalizedStringKey(title), identifier: identifier)
    }
}

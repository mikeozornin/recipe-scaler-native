//
//  ReleaseNotesSheet.swift
//  RecipeScalerNative
//
//  Spec 077 — archive of in-app notes. Unread rows stay expanded even after
//  lastViewed is raised on open.
//

import SwiftUI

struct ReleaseNotesSheet: View {
    @Environment(ReleaseNotesStore.self) private var releaseNotes
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            List {
                ForEach(releaseNotes.notesNewestFirst) { note in
                    accordion(note)
                        .accessibilityIdentifier(
                            "\(AccessibilityIdentifiers.releaseNotesSheetRowPrefix)\(note.version)"
                        )
                }
            }
            .appListBodyTypography()
            .contentMargins(
                .top,
                RecipeRowLayoutMetrics.listHorizontalInset,
                for: .scrollContent
            )
            .localizedNavigationTitle("release-notes.sheet.title")
            .accessibilityIdentifier(AccessibilityIdentifiers.releaseNotesSheet)
        }
    }

    private func accordion(_ note: IOSReleaseNote) -> some View {
        let expanded = releaseNotes.isExpanded(note.version)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                releaseNotes.setExpanded(note.version, !expanded)
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: note.title(for: AppLanguagePreference.current.rawValue))
                            .appHeadline()
                            .multilineTextAlignment(.leading)
                        Text(verbatim: formattedDate(note.date))
                            .appFootnote()
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    AppSymbol.image("chevron.down")
                        .font(AppTypography.footnote)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if expanded {
                Text(verbatim: note.body(for: AppLanguagePreference.current.rawValue))
                    .appBody()
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.abbreviated).day().locale(locale))
    }
}

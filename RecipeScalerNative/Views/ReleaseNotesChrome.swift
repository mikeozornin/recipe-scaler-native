//
//  ReleaseNotesChrome.swift
//  RecipeScalerNative
//
//  Spec 077 — places the release-notes banner in the same scroll slots as 061,
//  immediately below the system banner.
//

import SwiftUI

struct ReleaseNotesChrome: View {
    @Environment(ReleaseNotesStore.self) private var releaseNotes

    private var noteToShow: IOSReleaseNote? {
        guard releaseNotes.showsBanner, let note = releaseNotes.latestNote else {
            return nil
        }
        #if DEBUG
        if DebugLaunchOptions.screenshotCapture { return nil }
        #endif
        return note
    }

    var body: some View {
        if let note = noteToShow {
            ReleaseNotesBannerView(
                title: note.title(for: AppLanguagePreference.current.rawValue),
                onOpen: { releaseNotes.presentSheet() },
                onDismiss: { releaseNotes.dismissBanner() }
            )
        }
    }
}

struct ReleaseNotesListRow: View {
    var body: some View {
        ReleaseNotesChrome()
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

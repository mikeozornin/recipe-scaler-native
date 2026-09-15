//
//  ReleaseNotesStore.swift
//  RecipeScalerNative
//
//  Spec 077 — device-local lastViewed + banner/sheet state.
//  No network. Logout must not clear lastViewed.
//

import Foundation

@MainActor
@Observable
final class ReleaseNotesStore {
    static let lastViewedDefaultsKey = "releaseNotes.lastViewedVersion"

    private let defaults: UserDefaults
    private let catalog: [IOSReleaseNote]

    /// Maximum catalog version the user has dismissed or opened. `0` is the
    /// empty-catalog sentinel so the next binary with real notes can show a banner.
    private(set) var lastViewed: Int = 0

    var isSheetPresented = false

    /// Unread versions captured **before** lastViewed is raised on present.
    private(set) var expandedVersions: Set<Int> = []

    init(
        defaults: UserDefaults = .standard,
        catalog: [IOSReleaseNote] = IOSReleaseNotesCatalog.notes
    ) {
        self.defaults = defaults
        self.catalog = catalog
        seedIfNeeded()
    }

    var notesNewestFirst: [IOSReleaseNote] {
        catalog.sorted { $0.version > $1.version }
    }

    var maxVersion: Int {
        catalog.map(\.version).max() ?? 0
    }

    var latestNote: IOSReleaseNote? {
        catalog.max { $0.version < $1.version }
    }

    var hasArchiveRow: Bool {
        !catalog.isEmpty
    }

    var showsBanner: Bool {
        guard let latest = latestNote else { return false }
        return latest.version > lastViewed
    }

    func seedIfNeeded() {
        if let stored = validStoredLastViewed() {
            lastViewed = stored
            return
        }
        let seeded = catalog.map(\.version).max() ?? 0
        defaults.set(seeded, forKey: Self.lastViewedDefaultsKey)
        lastViewed = seeded
    }

    func dismissBanner() {
        markViewedToMax()
    }

    func presentSheet() {
        guard !catalog.isEmpty else { return }
        expandedVersions = Set(catalog.compactMap { note in
            note.version > lastViewed ? note.version : nil
        })
        markViewedToMax()
        isSheetPresented = true
    }

    func isExpanded(_ version: Int) -> Bool {
        expandedVersions.contains(version)
    }

    func setExpanded(_ version: Int, _ expanded: Bool) {
        if expanded {
            expandedVersions.insert(version)
        } else {
            expandedVersions.remove(version)
        }
    }

    private func markViewedToMax() {
        guard let maxV = catalog.map(\.version).max() else { return }
        defaults.set(maxV, forKey: Self.lastViewedDefaultsKey)
        lastViewed = maxV
    }

    private func validStoredLastViewed() -> Int? {
        guard let object = defaults.object(forKey: Self.lastViewedDefaultsKey) else {
            return nil
        }
        if let number = object as? NSNumber {
            return number.intValue
        }
        return nil
    }
}

//
//  RecipeShareModel.swift
//  RecipeScalerNative
//

import Foundation
import RecipeScalerCore

/// Loads sharing settings for the recipe share sheet.
@MainActor
@Observable
final class RecipeShareModel {
    var publicProfileEnabled: Bool
    var shareMode: PublicShareMode
    var username: String
    var isOnline = false

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
        publicProfileEnabled = SharingSettingsCache.publicProfileEnabled
        shareMode = SharingSettingsCache.shareMode
        username = SharingSettingsCache.username
    }

    func loadSettings(syncService: YjsSyncService) async {
        isOnline = syncService.connectionState == .connected
        guard isOnline else { return }
        if let data = try? await AccountAPI.fetchSharingSettings() {
            let ppe = data.publicProfileEnabled ?? false
            let mode = PublicShareMode(apiValue: data.shareMode) ?? .one_by_one
            let uname = data.username ?? ""
            publicProfileEnabled = ppe
            shareMode = mode
            username = uname
            SharingSettingsCache.save(
                publicProfileEnabled: ppe,
                shareMode: mode,
                username: uname
            )
        }
    }
}

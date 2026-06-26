//
//  RecipeScalerNativeWatchApp.swift
//  RecipeScalerNativeWatch Watch App
//
//  Spec 039 — watchOS Timers v1: root entry. Activates WCSession, reads
//  stored userId, sets up APIClient, shows TimerListView or
//  NotAuthorizedStateView based on auth state.
//

import SwiftUI
import WatchConnectivity
import RecipeScalerCore

@main
struct RecipeScalerNativeWatchApp: App {
    @StateObject private var viewModel = TimerListViewModel()

    init() {
        // Configure APIClient from stored credentials if present.
        if let userId = WatchCredentialsStore.userId {
            APIClient.shared.configure(userId: userId)
        }
        // Activate WCSession to receive userId updates from iPhone.
        WatchCredentialsBridge.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            TimerListView(viewModel: viewModel)
        }
    }
}

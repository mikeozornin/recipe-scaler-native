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
import UserNotifications

@main
struct RecipeScalerNativeWatchApp: App {
    @StateObject private var viewModel = TimerListViewModel()
    private static let notificationDelegate = WatchNotificationDelegate()

    init() {
        WatchExpiryNotificationsPrefs.registerDefaults()
        if let userId = WatchCredentialsStore.userId {
            if let token = WatchCredentialsStore.token, !token.isEmpty {
                APIClient.shared.configure(authToken: token)
            }
            APIClient.shared.configure(userId: userId)
        }
        // Activate WCSession to receive userId updates from iPhone.
        WatchCredentialsBridge.shared.activate()
        // Foreground suppression of watch-timer-* UNNotification delivery.
        UNUserNotificationCenter.current().delegate = Self.notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            TimerListView(viewModel: viewModel)
        }
    }
}

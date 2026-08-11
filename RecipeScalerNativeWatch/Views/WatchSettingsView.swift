//
//  WatchSettingsView.swift
//  RecipeScalerNativeWatch Watch App
//
//  Spec 062 — Settings screen with a single toggle:
//  "Haptics on completion" (default ON).
//

import SwiftUI
import UserNotifications

struct WatchSettingsView: View {
    @State private var expiryEnabled = WatchExpiryNotificationsPrefs.isEnabled
    @State private var notificationsDenied = false

    var body: some View {
        List {
            Section {
                Toggle(
                    isOn: Binding(
                        get: { expiryEnabled },
                        set: { newValue in handleToggle(newValue) }
                    )
                ) {
                    Text(LocalizedStringKey("watch.timer.settings.expiry-toggle.label"))
                }
                .accessibilityHint(Text(LocalizedStringKey("watch.timer.settings.expiry-toggle.hint")))
                .listRowBackground(Color.clear)
            }

            if notificationsDenied {
                Section {
                    Text(LocalizedStringKey("watch.timer.settings.notifications-disabled.footnote"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(Text(LocalizedStringKey("watch.timer.settings.title")))
        .onAppear {
            expiryEnabled = WatchExpiryNotificationsPrefs.isEnabled
        }
        .task { await refreshDeniedState() }
    }

    private func handleToggle(_ newValue: Bool) {
        expiryEnabled = newValue
        WatchExpiryNotificationsPrefs.setEnabled(newValue)
        WatchHaptics.click()
    }

    private func refreshDeniedState() async {
        let center = UNUserNotificationCenter.current()
        let settings = await withCheckedContinuation { cont in
            center.getNotificationSettings { cont.resume(returning: $0) }
        }
        notificationsDenied = settings.authorizationStatus == .denied
    }
}

#Preview {
    NavigationStack {
        WatchSettingsView()
    }
}

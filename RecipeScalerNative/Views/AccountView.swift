//
//  AccountView.swift
//  RecipeScalerNative
//

import SwiftUI
import PhotosUI

struct AccountView: View {
    @StateObject private var authService = AuthService.shared
    @State private var displayName = ""
    @State private var showingLogoutConfirmation = false
    @State private var showSeed = false
    @State private var avatarItem: PhotosPickerItem?
    @State private var colorScheme: AppColorScheme = .system
    @State private var showNutrition = true
    @State private var statusMessage: String?

    enum AppColorScheme: String, CaseIterable {
        case system, light, dark
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Profile") {
                    TextField("Display name", text: $displayName)
                    PhotosPicker(selection: $avatarItem, matching: .images) {
                        AppLabel.make("Change avatar", symbol: "person.crop.circle")
                    }
                    if let userId = authService.userId {
                        LabeledContent("User ID", value: UserIdFormatter.format(userId))
                    }
                }

                Section("Security") {
                    Button("Show seed phrase") { showSeed = true }
                }

                Section("Preferences") {
                    Picker("Theme", selection: $colorScheme) {
                        Text("System").tag(AppColorScheme.system)
                        Text("Light").tag(AppColorScheme.light)
                        Text("Dark").tag(AppColorScheme.dark)
                    }
                    Toggle("Show nutrition", isOn: $showNutrition)
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage).font(.footnote)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showingLogoutConfirmation = true
                    } label: {
                        AppLabel.make("Logout", symbol: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Profile")
            .preferredColorScheme(preferredScheme)
            .onChange(of: displayName) { _, new in
                Task { try? await AccountAPI.patchDisplayName(new) }
            }
            .onChange(of: avatarItem) { _, item in
                Task { await uploadAvatar(item) }
            }
            .onChange(of: showNutrition) { _, value in
                UserDefaults.standard.set(value, forKey: NutritionSettings.globalEnabledKey)
            }
            .sheet(isPresented: $showSeed) {
                SeedPhraseSheet()
            }
            .confirmationDialog("Logout?", isPresented: $showingLogoutConfirmation) {
                Button("Logout", role: .destructive) {
                    Task { await logout() }
                }
                Button("Cancel", role: .cancel) { }
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.accountRoot)
        }
        .onAppear {
            showNutrition = NutritionSettings.isGlobalEnabled
        }
    }

    private var preferredScheme: ColorScheme? {
        switch colorScheme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private func uploadAvatar(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self) else { return }
        do {
            try await AccountAPI.uploadAvatar(imageData: data)
            statusMessage = "Avatar updated"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func logout() async {
        do {
            try authService.logout()
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

private struct SeedPhraseSheet: View {
    @StateObject private var authService = AuthService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text((try? authService.getSeedPhrase()) ?? "Seed not available")
                    .font(.custom(AppFonts.mono, size: 15))
                    .padding()
            }
            .navigationTitle("Seed phrase")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
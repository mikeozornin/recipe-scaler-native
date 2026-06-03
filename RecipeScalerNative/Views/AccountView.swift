//
//  AccountView.swift
//  RecipeScalerNative
//

import LocalAuthentication
import PhotosUI
import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var syncService: YjsSyncService
    @StateObject private var authService = AuthService.shared
    @StateObject private var viewModel = AccountSettingsViewModel()

    @State private var showingLogoutConfirmation = false
    @State private var showLoginOnDevice = false
    @State private var avatarItem: PhotosPickerItem?
    @State private var appLanguage: AppLanguagePreference = .current
    @State private var usernameDraft = ""

    var body: some View {
        NavigationStack {
            List {
                if !viewModel.isOnline {
                    Section {
                        Label {
                            Text("account.offline.alert")
                        } icon: {
                            AppSymbol.image("wifi.slash")
                                .foregroundStyle(.secondary)
                        }
                        .font(AppTypography.subheadline)
                    }
                }

                accountSection
                // publicRecipesSection
                preferencesSection
                // dataSection

                if let statusMessage = viewModel.statusMessage {
                    Section {
                        Text(statusMessage)
                            .font(AppTypography.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                footerSection
            }
            .navigationTitle("account.title")
            .navigationBarTitleDisplayMode(.inline)
            .appListBodyTypography()
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemBackground).opacity(0.6))
                }
            }
            .sheet(isPresented: $showLoginOnDevice) {
                AccountSeedPhraseSheet()
            }
            .confirmationDialog(
                String(localized: "account.logout.confirm"),
                isPresented: $showingLogoutConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "account.logout"), role: .destructive) {
                    Task { @MainActor in await viewModel.logout(syncService: syncService) }
                }
                Button(String(localized: "common.cancel"), role: .cancel) { }
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.accountRoot)
            .task {
                await viewModel.refresh(syncService: syncService)
                usernameDraft = viewModel.username ?? ""
                appLanguage = .current
            }
            .onChange(of: syncService.connectionState) { _, _ in
                Task { @MainActor in
                    viewModel.bind(syncService: syncService)
                }
            }
            .onChange(of: avatarItem) { _, item in
                Task { @MainActor in
                    guard let item,
                          let data = try? await item.loadTransferable(type: Data.self) else { return }
                    await viewModel.uploadAvatar(data: data, syncService: syncService)
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var accountSection: some View {
        Section {
            if let userId = authService.userId {
                HStack(spacing: 12) {
                    accountAvatar
                    Text(UserIdFormatter.format(userId))
                        .font(AppTypography.mono(AppTypography.subheadlineSize))
                    Spacer(minLength: 8)
                    Button(role: .destructive) {
                        showingLogoutConfirmation = true
                    } label: {
                        AppSymbol.image("rectangle.portrait.and.arrow.right")
                            .font(AppTypography.body)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(String(localized: "account.logout"))
                }
            }

            Button("auth.login-with-another") {
                showLoginOnDevice = true
            }
        } header: {
            AppSectionHeader("account.section.account")
        }
    }

    @ViewBuilder
    private var publicRecipesSection: some View {
        Section {
            if !viewModel.isOnline {
                Text("account.public-profile.offline")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(.secondary)
            } else if viewModel.isLoading {
                ProgressView()
            } else {
                Toggle("account.public-profile.switch", isOn: Binding(
                    get: { viewModel.publicProfileEnabled },
                    set: { newValue in
                        Task { @MainActor in await viewModel.setPublicProfileEnabled(newValue) }
                    }
                ))
                .disabled(viewModel.isUpdatingSharing)

                if viewModel.publicProfileEnabled {
                    NavigationLink {
                        AccountCheckmarkSelectionView(
                            navigationTitle: "account.share-mode.label",
                            options: PublicShareMode.allCases,
                            selection: viewModel.shareMode,
                            title: { $0.localizedTitleKey },
                            onSelect: { mode in
                                Task { @MainActor in await viewModel.setShareMode(mode) }
                            }
                        )
                    } label: {
                        AccountSettingsNavigationRow(
                            label: "account.share-mode.label",
                            value: viewModel.shareMode.localizedTitleKey
                        )
                    }
                    .disabled(viewModel.isUpdatingSharing)

                    TextField("account.profile.name", text: $viewModel.displayName)
                        .onSubmit { viewModel.scheduleNameSave() }
                    PhotosPicker(selection: $avatarItem, matching: .images) {
                        AppLabel.make("account.profile.change-avatar", symbol: "person.crop.circle")
                    }

                    if viewModel.canChangeUsername {
                        TextField("account.username.label", text: $usernameDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("account.username.save") {
                            Task { @MainActor in await viewModel.saveUsername(usernameDraft) }
                        }
                    } else if let username = viewModel.username {
                        LabeledContent("account.username.label", value: "@\(username)")
                    }

                    Toggle("account.allow-downloads", isOn: Binding(
                        get: { viewModel.allowRecipeDownloads },
                        set: { enabled in
                            Task { @MainActor in await viewModel.setAllowRecipeDownloads(enabled) }
                        }
                    ))
                    .disabled(viewModel.isUpdatingSharing)

                    if let username = viewModel.username,
                       let url = PublicURLBuilder.publicProfileURL(username: username) {
                        Link("account.your-public-recipes", destination: url)
                    }
                }
            }
        } header: {
            AppSectionHeader("account.section.public-recipes")
        }
    }

    @ViewBuilder
    private var preferencesSection: some View {
        Section {
            NavigationLink {
                AccountCheckmarkSelectionView(
                    navigationTitle: "account.language.label",
                    options: AppLanguagePreference.allCases,
                    selection: appLanguage,
                    title: { $0.localizedTitleKey },
                    onSelect: { language in
                        appLanguage = language
                        AppLanguagePreference.save(language)
                    }
                )
            } label: {
                AccountSettingsNavigationRow(
                    label: "account.language.label",
                    value: appLanguage.localizedTitleKey
                )
            }

            NavigationLink {
                AccountCheckmarkSelectionView(
                    navigationTitle: "account.theme.label",
                    options: AppThemePreference.allCases,
                    selection: viewModel.appTheme,
                    title: { $0.localizedTitleKey },
                    onSelect: { viewModel.setAppTheme($0) }
                )
            } label: {
                AccountSettingsNavigationRow(
                    label: "account.theme.label",
                    value: viewModel.appTheme.localizedTitleKey
                )
            }

            Toggle("account.nutrition.show", isOn: Binding(
                get: { viewModel.showNutrition },
                set: { value in
                    Task { @MainActor in await viewModel.setShowNutrition(value) }
                }
            ))
        } header: {
            AppSectionHeader("account.section.preferences")
        }
    }

    @ViewBuilder
    private var dataSection: some View {
        Section {
            Text("account.data.coming-soon")
                .font(AppTypography.subheadline)
                .foregroundStyle(.secondary)
        } header: {
            AppSectionHeader("account.section.data")
        }
    }

    @ViewBuilder
    private var footerSection: some View {
        Section {
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                LabeledContent("account.version", value: version)
            }
        }
    }

    @ViewBuilder
    private var accountAvatar: some View {
        Group {
            if let url = viewModel.avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }
}

// MARK: - Seed phrase (biometrics + QR)

private struct AccountSeedPhraseSheet: View {
    @StateObject private var authService = AuthService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var unlocked = false
    @State private var authError: String?

    var body: some View {
        NavigationStack {
            Group {
                if unlocked {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("account.secret-phrase")
                                .font(AppTypography.headline)
                            if let seed = try? authService.getSeedPhrase() {
                                Text(seed)
                                    .font(AppTypography.mono(AppTypography.subheadlineSize))
                                    .textSelection(.enabled)
                                SeedQRCodeView(text: seed)
                                Button("account.seed.copy") {
                                    UIPasteboard.general.string = seed
                                }
                            } else {
                                Text("account.no-seed")
                                    .font(AppTypography.body)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    }
                } else {
                    ContentUnavailableView {
                        Label("account.seed.locked", systemImage: "lock.fill")
                    } description: {
                        if let authError {
                            Text(authError)
                                .font(AppTypography.body)
                        } else {
                            Text("account.seed.unlock-hint")
                                .font(AppTypography.body)
                        }
                    } actions: {
                        Button("account.seed.unlock") {
                            Task { @MainActor in await authenticate() }
                        }
                    }
                }
            }
            .navigationTitle("account.secret-phrase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                        .appToolbarConfirmButton()
                }
            }
            .appListBodyTypography()
            .task {
                await authenticate()
            }
        }
    }

    @MainActor
    private func authenticate() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            unlocked = true
            return
        }
        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: String(localized: "account.seed.biometric-reason")
            )
            unlocked = ok
            authError = ok ? nil : String(localized: "account.seed.auth-failed")
        } catch {
            authError = error.localizedDescription
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        AccountView()
    }
}
#endif
//
//  RecipeDetailShareButton.swift
//  RecipeScalerNative
//

import SwiftUI
import UIKit

struct RecipeDetailShareButton: View {
    let recipeId: String
    let isPublic: Bool
    let hasImage: Bool
    let hasSteps: Bool

    @State private var showShare = false

    var body: some View {
        Button {
            showShare = true
        } label: {
            AppToolbarStyle.iconOnly(systemName: "square.and.arrow.up")
        }
        .appToolbarIconButton()
        .accessibilityLabel("recipe.share")
        #if DEBUG
        .onAppear {
            if DebugLaunchOptions.showRecipeShare {
                showShare = true
            }
        }
        #endif
        .sheet(isPresented: $showShare) {
            RecipeShareSheet(
                recipeId: recipeId,
                initialIsPublic: isPublic,
                hasImage: hasImage,
                hasSteps: hasSteps
            )
        }
    }
}

// MARK: - Sheet

private struct RecipeShareSheet: View {
    @Environment(YjsSyncService.self) private var syncService
    @Environment(\.dismiss) private var dismiss

    let recipeId: String
    let initialIsPublic: Bool
    let hasImage: Bool
    let hasSteps: Bool

    @State private var model = RecipeShareModel(api: .shared)
    @State private var isPublic: Bool
    @State private var isUpdating = false

    // Spec 057: AirDrop file export state
    @State private var fileExportURL: URL?
    @State private var isPreparingFile = false
    @State private var showFileActivitySheet = false
    @State private var fileErrorMessage: LocalizedStringKey?

    init(recipeId: String, initialIsPublic: Bool, hasImage: Bool, hasSteps: Bool) {
        self.recipeId = recipeId
        self.initialIsPublic = initialIsPublic
        self.hasImage = hasImage
        self.hasSteps = hasSteps
        _isPublic = State(initialValue: initialIsPublic)
    }

    // MARK: Computed

    /// Whether to show the public/private toggle (vs. a read-only mode description).
    private var showToggle: Bool {
        !model.publicProfileEnabled || model.shareMode == .one_by_one
    }

    /// Whether this recipe is effectively accessible via its public link.
    private var isEffectivelyPublic: Bool {
        if !model.publicProfileEnabled { return isPublic }
        switch model.shareMode {
        case .all:                  return true
        case .with_images_and_steps: return hasImage && hasSteps
        case .one_by_one:            return isPublic
        }
    }

    private var shareURL: URL? {
        if model.publicProfileEnabled, !model.username.isEmpty {
            return PublicURLBuilder.profileRecipeURL(username: model.username, recipeId: recipeId)
        }
        return PublicURLBuilder.recipeShareURL(recipeId: recipeId)
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            List {
                if !model.isOnline && showToggle {
                    Section {
                        Text("recipe.share.offline-message")
                            .appBody()
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    if showToggle {
                        Toggle(isOn: toggleBinding) {
                            Text("recipe.detail.public")
                                .appBody()
                        }
                        .disabled(!model.isOnline || isUpdating)
                    } else {
                        shareModeDescription
                    }

                    if isEffectivelyPublic, let url = shareURL {
                        ShareLink(item: url) {
                            Text(url.absoluteString)
                                .appBody()
                                .foregroundStyle(Color.accentColor)
                                .lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .tint(Color.accentColor)

                        Button("shopping.copy-link") {
                            copyLink(url.absoluteString)
                        }
                    }
                }

                // Spec 057: AirDrop file transfer.
                // Independent of the public-link section so the user can send
                // a file regardless of `isPublic` state.
                airdropFileSection
            }
            .appOpaqueGroupedListSurface()
            .localizedNavigationTitle("recipe.share")
            .navigationBarTitleDisplayMode(.inline)
        }
        .appOpaqueSheetPresentation(detents: [.medium, .large])
        .task { await model.loadSettings(syncService: syncService) }
        .sheet(isPresented: $showFileActivitySheet) {
            if let fileURL = fileExportURL {
                ActivityShareSheet(activityItems: [fileURL])
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - AirDrop file section (spec 057)

    @ViewBuilder
    private var airdropFileSection: some View {
        Section {
            if isPreparingFile {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("recipe.share.preparing-file")
                        .appBody()
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    Task { await prepareAndShareFile() }
                } label: {
                    Label("recipe.share.send-file", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(isPreparingFile)
                .accessibilityIdentifier("recipe.share.airdrop-button")
            }

            if let fileErrorMessage {
                Text(fileErrorMessage)
                    .foregroundStyle(.red)
                    .appFootnote()
            }
        } header: {
            // Override the app-wide Martian environment font so this header
            // matches the system insetGrouped section header (SF / system).
            Text("recipe.share.send-file")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textCase(AppSectionHeader.usesUpperCase ? .uppercase : nil)
        }
        .appListSectionHeaderStyle()
    }

    /// Build the `.recipe` file, then immediately present the system share sheet
    /// so the user does not need a second tap after preparation finishes.
    private func prepareAndShareFile() async {
        isPreparingFile = true
        fileErrorMessage = nil
        showFileActivitySheet = false
        let exporter = NativeExportImportService(syncService: syncService)
        do {
            let url = try await exporter.exportRecipe(id: recipeId)
            fileExportURL = url
            isPreparingFile = false
            // Present after the progress row has left the hierarchy so the
            // activity sheet is not fighting a mid-update List layout.
            showFileActivitySheet = true
        } catch {
            fileErrorMessage = "recipe.share.file-failed"
            isPreparingFile = false
        }
    }

    // MARK: Mode description (shown when toggle is hidden)

    @ViewBuilder
    private var shareModeDescription: some View {
        let key: LocalizedStringKey = switch model.shareMode {
        case .all:
            "recipe.share.all-mode"
        case .with_images_and_steps:
            (hasImage && hasSteps)
                ? "recipe.share.with-images-steps-mode"
                : "recipe.share.not-with-images-steps-mode"
        case .one_by_one:
            "recipe.detail.public"  // fallback; shouldn't happen since showToggle covers .one_by_one
        }
        Text(key)
            .appBody()
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Toggle binding

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { isPublic },
            set: { newValue in
                Task { await setPublic(newValue) }
            }
        )
    }

    // MARK: Actions

    private func setPublic(_ enabled: Bool) async {
        guard model.isOnline else { return }
        let previous = isPublic
        isPublic = enabled
        isUpdating = true
        defer { isUpdating = false }
        do {
            try await syncService.updateRecipeIsPublic(enabled)
        } catch {
            isPublic = previous
        }
    }

    private func copyLink(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #endif
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            ShoppingFeedback.postStatus(Bundle.currentLocalizedString("shopping.link-copied"))
        }
    }
}

// MARK: - System share sheet

/// Thin SwiftUI wrapper around `UIActivityViewController` so we can present
/// AirDrop / Files / Messages as soon as the `.recipe` file is ready —
/// without requiring a second tap on a `ShareLink`.
private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

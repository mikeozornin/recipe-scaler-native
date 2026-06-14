//
//  SyncStatusSheet.swift
//  RecipeScalerNative
//

import RecipeScalerCore
import SwiftUI

/// Reusable sync status content used both as a sheet (from RecipeList toolbar)
/// and as a pushed screen (from Account menu). Does not own its own
/// `NavigationStack` so callers can decide how to present it.
struct SyncStatusContent: View {
    let connectionState: ConnectionState
    let connectionTransport: SyncConnectionTransport
    let imageCacheStatus: RecipeImageCacheStatus
    let recipeDocumentCacheStatus: RecipeDocumentCacheStatus
    let onRetryImageDownload: () -> Void
    let onRetryRecipeDocumentsDownload: () -> Void

    var body: some View {
        List {
            Section {
                Label {
                    Text(connectionState.displayLabel)
                        .appBody()
                } icon: {
                    connectionIcon
                }

                #if DEBUG
                HStack {
                    Text("sync.status.transport.label")
                        .appBody()
                    Spacer()
                    Text(connectionTransport.displayLabel)
                        .appBody()
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.syncStatusTransport)
                #endif
            } header: {
                AppSectionHeader("sync.status.section.connection")
            }

            Section {
                cacheRow(
                    titleKey: "sync.status.images.preview",
                    cached: imageCacheStatus.previewCached,
                    total: imageCacheStatus.recipesWithImage
                )
                cacheRow(
                    titleKey: "sync.status.images.full",
                    cached: imageCacheStatus.fullCached,
                    total: imageCacheStatus.recipesWithImage
                )

                if imageCacheStatus.recipesWithImage == 0 {
                    Text("sync.status.images.none")
                        .appFootnote()
                        .foregroundStyle(.secondary)
                } else if imageCacheStatus.isDownloading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(verbatim: imageDownloadingLabel)
                            .appFootnote()
                            .foregroundStyle(.secondary)
                    }
                } else if !imageCacheStatus.isFullyCached {
                    Text(verbatim: imageCacheHint)
                        .appFootnote()
                        .foregroundStyle(.secondary)
                } else {
                    Label {
                        Text("sync.status.images.ready")
                            .appBody()
                    } icon: {
                        AppSymbol.image("checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                if connectionState.isConnected, imageCacheStatus.pendingFullCount > 0 {
                    Button("sync.status.images.retry") {
                        onRetryImageDownload()
                    }
                }
            } header: {
                AppSectionHeader("sync.status.section.images")
            }

            Section {
                cacheRow(
                    titleKey: "sync.status.recipes.cached",
                    cached: recipeDocumentCacheStatus.cachedRecipes,
                    total: recipeDocumentCacheStatus.totalRecipes
                )

                if recipeDocumentCacheStatus.totalRecipes == 0 {
                    Text("sync.status.recipes.none")
                        .appFootnote()
                        .foregroundStyle(.secondary)
                } else if recipeDocumentCacheStatus.isDownloading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(verbatim: recipeDownloadingLabel)
                            .appFootnote()
                            .foregroundStyle(.secondary)
                    }
                } else if !recipeDocumentCacheStatus.isFullyCached {
                    Text(verbatim: recipeDocumentHint)
                        .appFootnote()
                        .foregroundStyle(.secondary)
                } else {
                    Label {
                        Text("sync.status.recipes.ready")
                            .appBody()
                    } icon: {
                        AppSymbol.image("checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                if connectionState.isConnected, recipeDocumentCacheStatus.pendingCount > 0 {
                    Button("sync.status.recipes.retry") {
                        onRetryRecipeDocumentsDownload()
                    }
                }
            } header: {
                AppSectionHeader("sync.status.section.recipes")
            }

            if !recipeDocumentCacheStatus.pendingEntries.isEmpty {
                Section {
                    ForEach(recipeDocumentCacheStatus.pendingEntries.prefix(30)) { entry in
                        HStack {
                            Text(verbatim: displayName(for: entry.name))
                                .appBody()
                                .lineLimit(1)
                            Spacer()
                            badge("sync.status.badge.recipe")
                        }
                    }
                    if recipeDocumentCacheStatus.pendingEntries.count > 30 {
                        Text(verbatim: pendingRecipesMoreLabel)
                            .appFootnote()
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    AppSectionHeader("sync.status.section.recipes.pending")
                }
            }

            if !imageCacheStatus.pendingEntries.isEmpty {
                Section {
                    ForEach(imageCacheStatus.pendingEntries.prefix(30)) { entry in
                        HStack {
                            Text(verbatim: displayName(for: entry.name))
                                .appBody()
                                .lineLimit(1)
                            Spacer()
                            pendingBadges(for: entry)
                        }
                    }
                    if imageCacheStatus.pendingEntries.count > 30 {
                        Text(verbatim: pendingImagesMoreLabel)
                            .appFootnote()
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    AppSectionHeader("sync.status.section.pending")
                }
            }
        }
        .appListBodyTypography()
    }

    @ViewBuilder
    private var connectionIcon: some View {
        switch connectionState {
        case .connected:
            AppSymbol.image("checkmark.circle.fill").foregroundStyle(.green)
        case .connecting, .reconnecting:
            AppSymbol.image("arrow.triangle.2.circlepath").foregroundStyle(.orange)
        case .disconnected:
            AppSymbol.image("wifi.slash").foregroundStyle(.secondary)
        case .error:
            AppSymbol.image("exclamationmark.circle.fill").foregroundStyle(.red)
        }
    }

    /// `Bundle.currentLocalizedString` (not `String(localized:)`) so the runtime
    /// language override is honored when this string is later wrapped in `Text(verbatim:)`.
    private var imageCacheHint: String {
        if connectionState.isConnected {
            return Bundle.currentLocalizedString("sync.status.images.hint.online")
        }
        return String(
            format: Bundle.currentLocalizedString("sync.status.images.hint.offline"),
            locale: AppLanguagePreference.current.locale,
            imageCacheStatus.pendingFullCount
        )
    }

    private var recipeDocumentHint: String {
        if connectionState.isConnected {
            return Bundle.currentLocalizedString("sync.status.recipes.hint.online")
        }
        return Bundle.appPluralizedString(
            key: "sync.status.recipes.hint.offline",
            count: recipeDocumentCacheStatus.pendingCount
        )
    }

    private var imageDownloadingLabel: String {
        String(
            format: Bundle.currentLocalizedString("sync.status.images.downloading"),
            locale: AppLanguagePreference.current.locale,
            imageCacheStatus.downloadCompleted,
            imageCacheStatus.downloadTotal
        )
    }

    private var recipeDownloadingLabel: String {
        String(
            format: Bundle.currentLocalizedString("sync.status.recipes.downloading"),
            locale: AppLanguagePreference.current.locale,
            recipeDocumentCacheStatus.downloadCompleted,
            recipeDocumentCacheStatus.downloadTotal
        )
    }

    private var pendingRecipesMoreLabel: String {
        String(
            format: Bundle.currentLocalizedString("sync.status.pending.more"),
            locale: AppLanguagePreference.current.locale,
            recipeDocumentCacheStatus.pendingEntries.count - 30
        )
    }

    private var pendingImagesMoreLabel: String {
        String(
            format: Bundle.currentLocalizedString("sync.status.pending.more"),
            locale: AppLanguagePreference.current.locale,
            imageCacheStatus.pendingEntries.count - 30
        )
    }

    private func cacheRow(titleKey: LocalizedStringKey, cached: Int, total: Int) -> some View {
        HStack {
            Text(titleKey)
                .appBody()
            Spacer()
            Text("\(cached)/\(total)")
                .appBody()
                .monospacedDigit()
                .foregroundStyle(cached >= total && total > 0 ? .primary : .secondary)
        }
    }

    @ViewBuilder
    private func pendingBadges(for entry: RecipeImageCachePendingEntry) -> some View {
        HStack(spacing: 4) {
            if entry.missingPreview {
                badge("sync.status.badge.preview")
            }
            if entry.missingFull {
                badge("sync.status.badge.full")
            }
        }
    }

    private func badge(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .appFootnote()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
    }

    private func displayName(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return Bundle.currentLocalizedString("recipe.list.no-title")
        }
        return RecipeTitleEmoji.displayName(for: name)
    }
}

/// Sheet wrapper used from the Recipes tab toolbar. Owns its `NavigationStack`
/// and presentation detents; content is shared via `SyncStatusContent`.
struct SyncStatusSheet: View {
    let connectionState: ConnectionState
    let connectionTransport: SyncConnectionTransport
    let imageCacheStatus: RecipeImageCacheStatus
    let recipeDocumentCacheStatus: RecipeDocumentCacheStatus
    let onRetryImageDownload: () -> Void
    let onRetryRecipeDocumentsDownload: () -> Void

    var body: some View {
        NavigationStack {
            SyncStatusContent(
                connectionState: connectionState,
                connectionTransport: connectionTransport,
                imageCacheStatus: imageCacheStatus,
                recipeDocumentCacheStatus: recipeDocumentCacheStatus,
                onRetryImageDownload: onRetryImageDownload,
                onRetryRecipeDocumentsDownload: onRetryRecipeDocumentsDownload
            )
            .localizedNavigationTitle("sync.status.title")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

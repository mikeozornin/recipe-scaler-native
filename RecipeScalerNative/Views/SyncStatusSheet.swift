//
//  SyncStatusSheet.swift
//  RecipeScalerNative
//

import SwiftUI

struct SyncStatusSheet: View {
    let connectionState: ConnectionState
    let connectionTransport: SyncConnectionTransport
    let imageCacheStatus: RecipeImageCacheStatus
    let recipeDocumentCacheStatus: RecipeDocumentCacheStatus
    let onRetryImageDownload: () -> Void
    let onRetryRecipeDocumentsDownload: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        Text(connectionState.displayLabel)
                    } icon: {
                        connectionIcon
                    }

                    #if DEBUG
                    HStack {
                        Text(String(localized: "sync.status.transport.label"))
                        Spacer()
                        Text(connectionTransport.displayLabel)
                            .foregroundStyle(.secondary)
                    }
                    .font(AppTypography.footnote)
                    .accessibilityIdentifier(AccessibilityIdentifiers.syncStatusTransport)
                    #endif
                } header: {
                    AppSectionHeader(String(localized: "sync.status.section.connection"))
                }

                Section {
                    cacheRow(
                        title: String(localized: "sync.status.images.preview"),
                        cached: imageCacheStatus.previewCached,
                        total: imageCacheStatus.recipesWithImage
                    )
                    cacheRow(
                        title: String(localized: "sync.status.images.full"),
                        cached: imageCacheStatus.fullCached,
                        total: imageCacheStatus.recipesWithImage
                    )

                    if imageCacheStatus.recipesWithImage == 0 {
                        Text(String(localized: "sync.status.images.none"))
                            .font(AppTypography.footnote)
                            .foregroundStyle(.secondary)
                    } else if imageCacheStatus.isDownloading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(
                                String(
                                    format: String(localized: "sync.status.images.downloading"),
                                    locale: .current,
                                    imageCacheStatus.downloadCompleted,
                                    imageCacheStatus.downloadTotal
                                )
                            )
                            .font(AppTypography.footnote)
                            .foregroundStyle(.secondary)
                        }
                    } else if !imageCacheStatus.isFullyCached {
                        Text(imageCacheHint)
                            .font(AppTypography.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Label {
                            Text(String(localized: "sync.status.images.ready"))
                        } icon: {
                            AppSymbol.image("checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }

                    if connectionState.isConnected, imageCacheStatus.pendingFullCount > 0 {
                        Button(String(localized: "sync.status.images.retry")) {
                            onRetryImageDownload()
                        }
                    }
                } header: {
                    AppSectionHeader(String(localized: "sync.status.section.images"))
                }

                Section {
                    cacheRow(
                        title: String(localized: "sync.status.recipes.cached"),
                        cached: recipeDocumentCacheStatus.cachedRecipes,
                        total: recipeDocumentCacheStatus.totalRecipes
                    )

                    if recipeDocumentCacheStatus.totalRecipes == 0 {
                        Text(String(localized: "sync.status.recipes.none"))
                            .font(AppTypography.footnote)
                            .foregroundStyle(.secondary)
                    } else if recipeDocumentCacheStatus.isDownloading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(
                                String(
                                    format: String(localized: "sync.status.recipes.downloading"),
                                    locale: .current,
                                    recipeDocumentCacheStatus.downloadCompleted,
                                    recipeDocumentCacheStatus.downloadTotal
                                )
                            )
                            .font(AppTypography.footnote)
                            .foregroundStyle(.secondary)
                        }
                    } else if !recipeDocumentCacheStatus.isFullyCached {
                        Text(recipeDocumentHint)
                            .font(AppTypography.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Label {
                            Text(String(localized: "sync.status.recipes.ready"))
                        } icon: {
                            AppSymbol.image("checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }

                    if connectionState.isConnected, recipeDocumentCacheStatus.pendingCount > 0 {
                        Button(String(localized: "sync.status.recipes.retry")) {
                            onRetryRecipeDocumentsDownload()
                        }
                    }
                } header: {
                    AppSectionHeader(String(localized: "sync.status.section.recipes"))
                }

                if !recipeDocumentCacheStatus.pendingEntries.isEmpty {
                    Section {
                        ForEach(recipeDocumentCacheStatus.pendingEntries.prefix(30)) { entry in
                            HStack {
                                Text(displayName(for: entry.name))
                                    .lineLimit(1)
                                Spacer()
                                badge(String(localized: "sync.status.badge.recipe"))
                            }
                        }
                        if recipeDocumentCacheStatus.pendingEntries.count > 30 {
                            Text(
                                String(
                                    format: String(localized: "sync.status.pending.more"),
                                    locale: .current,
                                    recipeDocumentCacheStatus.pendingEntries.count - 30
                                )
                            )
                            .font(AppTypography.footnote)
                            .foregroundStyle(.secondary)
                        }
                    } header: {
                        AppSectionHeader(String(localized: "sync.status.section.recipes.pending"))
                    }
                }

                if !imageCacheStatus.pendingEntries.isEmpty {
                    Section {
                        ForEach(imageCacheStatus.pendingEntries.prefix(30)) { entry in
                            HStack {
                                Text(displayName(for: entry.name))
                                    .lineLimit(1)
                                Spacer()
                                pendingBadges(for: entry)
                            }
                        }
                        if imageCacheStatus.pendingEntries.count > 30 {
                            Text(
                                String(
                                    format: String(localized: "sync.status.pending.more"),
                                    locale: .current,
                                    imageCacheStatus.pendingEntries.count - 30
                                )
                            )
                            .font(AppTypography.footnote)
                            .foregroundStyle(.secondary)
                        }
                    } header: {
                        AppSectionHeader(String(localized: "sync.status.section.pending"))
                    }
                }
            }
            .navigationTitle(String(localized: "sync.status.title"))
            .navigationBarTitleDisplayMode(.inline)
            .appListBodyTypography()
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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

    private var imageCacheHint: String {
        if connectionState.isConnected {
            return String(localized: "sync.status.images.hint.online")
        }
        return String(
            format: String(localized: "sync.status.images.hint.offline"),
            locale: .current,
            imageCacheStatus.pendingFullCount
        )
    }

    private var recipeDocumentHint: String {
        if connectionState.isConnected {
            return String(localized: "sync.status.recipes.hint.online")
        }
        return String(
            format: String(localized: "sync.status.recipes.hint.offline"),
            locale: .current,
            recipeDocumentCacheStatus.pendingCount
        )
    }

    private func cacheRow(title: String, cached: Int, total: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(cached)/\(total)")
                .monospacedDigit()
                .foregroundStyle(cached >= total && total > 0 ? .primary : .secondary)
        }
    }

    @ViewBuilder
    private func pendingBadges(for entry: RecipeImageCachePendingEntry) -> some View {
        HStack(spacing: 4) {
            if entry.missingPreview {
                badge(String(localized: "sync.status.badge.preview"))
            }
            if entry.missingFull {
                badge(String(localized: "sync.status.badge.full"))
            }
        }
    }

    private func badge(_ label: String) -> some View {
        Text(label)
            .font(AppTypography.footnote)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
    }

    private func displayName(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return String(localized: "recipe.list.no-title")
        }
        return RecipeTitleEmoji.displayName(for: name)
    }
}
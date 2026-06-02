//
//  SyncStatusSheet.swift
//  RecipeScalerNative
//

import SwiftUI

struct SyncStatusSheet: View {
    let connectionState: ConnectionState
    let imageCacheStatus: RecipeImageCacheStatus
    let onRetryImageDownload: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section(String(localized: "sync.status.section.connection")) {
                    Label {
                        Text(connectionState.displayLabel)
                    } icon: {
                        connectionIcon
                    }
                }

                Section(String(localized: "sync.status.section.images")) {
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
                            .font(.footnote)
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
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                    } else if !imageCacheStatus.isFullyCached {
                        Text(imageCacheHint)
                            .font(.footnote)
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
                }

                if !imageCacheStatus.pendingEntries.isEmpty {
                    Section(String(localized: "sync.status.section.pending")) {
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
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "sync.status.title"))
            .navigationBarTitleDisplayMode(.inline)
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
            .font(.caption2)
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
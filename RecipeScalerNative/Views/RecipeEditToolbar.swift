import SwiftUI

struct RecipeEditToolbar: View {
    let syncState: WriteSyncState

    var body: some View {
        if !shouldShow {
            EmptyView()
        } else {
            syncChip
        }
    }

    private var shouldShow: Bool {
        switch syncState {
        case .idle, .synced:
            return false
        case .pendingLocal, .syncing, .queued, .error:
            return true
        }
    }

    private var syncChip: some View {
        HStack(spacing: 6) {
            AppSymbol.image(iconName)
                .font(AppTypography.iconSize(AppTypography.footnoteSize))
            Text(label)
                .font(AppTypography.footnote)
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemFill))
        .clipShape(Capsule())
    }

    private var label: String {
        switch syncState {
        case .idle:
            return String(localized: "edit.sync.idle")
        case .pendingLocal:
            return String(localized: "edit.sync.pending")
        case .syncing:
            return String(localized: "edit.sync.syncing")
        case .synced:
            return String(localized: "edit.sync.synced")
        case .queued:
            return String(localized: "edit.sync.queued")
        case .error:
            return String(localized: "edit.sync.error")
        }
    }

    private var iconName: String {
        switch syncState {
        case .idle, .synced:
            return "checkmark.circle"
        case .pendingLocal, .queued:
            return "clock"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .error:
            return "exclamationmark.triangle"
        }
    }

    private var foregroundColor: Color {
        switch syncState {
        case .error:
            return .red
        case .synced:
            return .green
        default:
            return .secondary
        }
    }
}
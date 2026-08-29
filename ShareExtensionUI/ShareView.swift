//
//  ShareView.swift
//  RecipeScalerCore
//
//  SwiftUI interface shared by Share and Action extensions. Lifecycle:
//    .loading → .preview → .importing → .success / .error
//
//  Localizes through the framework bundle (`Shared.xcstrings`).
//

import SwiftUI
import UniformTypeIdentifiers
import RecipeScalerCore

public struct ShareView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .loading
    @State private var loadedContent: ShareContent = .empty
    @State private var lastResult: ImportRecipesResultDTO?
    @State private var errorMessage: String?

    private weak var extensionContext: NSExtensionContext?
    /// Weak host for iOS 18 Share `UIApplication.open` via responder chain.
    private let hostBox: HostViewControllerBox
    private let preloaded: ShareContent?

    public init(
        extensionContext: NSExtensionContext?,
        hostViewController: UIViewController? = nil,
        preloaded: ShareContent? = nil
    ) {
        self.extensionContext = extensionContext
        self.hostBox = HostViewControllerBox(hostViewController)
        self.preloaded = preloaded
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text(verbatim: Self.localized("share-extension.title")))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            cancel()
                        } label: {
                            Text(verbatim: Self.localized("share-extension.button-cancel"))
                        }
                    }
                }
        }
        .task {
            if case .loading = phase {
                await discoverContent()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .preview:
            PreviewPhase(
                content: loadedContent,
                onImport: { Task { await submit() } }
            )

        case .importing:
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text(verbatim: Self.localized("share-extension.importing"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .success:
            SuccessPhase(
                result: lastResult,
                onOpenRecipe: { openRecipeInHostApp() },
                onDone: { completeRequest() }
            )

        case .error:
            ErrorPhase(
                message: errorMessage ?? Self.localized("share-extension.error-network"),
                onRetry: { Task { await submit() } },
                onCancel: { cancel() }
            )

        case .notSignedIn:
            NotSignedInPhase(onDismiss: { cancel() })
        }
    }

    // MARK: - Phase transitions

    private func discoverContent() async {
        if let preloaded {
            loadedContent = preloaded
            if case .empty = preloaded {
                phase = .error
                errorMessage = Self.localized("share-extension.error-no-content")
            } else {
                phase = .preview
            }
            return
        }

        guard SharedAuthStore.token != nil else {
            phase = .notSignedIn
            return
        }

        guard let context = extensionContext else {
            phase = .error
            errorMessage = Self.localized("share-extension.error-no-content")
            return
        }

        let content = await ShareContentLoader.load(from: context)
        loadedContent = content
        switch content {
        case .empty:
            phase = .error
            errorMessage = Self.localized("share-extension.error-no-content")
        default:
            phase = .preview
        }
    }

    private func submit() async {
        guard let token = SharedAuthStore.token else {
            phase = .notSignedIn
            return
        }
        APIClient.shared.configure(authToken: token)
        if let userId = SharedAuthStore.userId {
            APIClient.shared.configure(userId: userId)
        }

        phase = .importing

        do {
            let dto: ImportRecipesResultDTO
            switch loadedContent {
            case .urls(let urls):
                dto = try await RecipeImportAPI.importURLs(urls.map { $0.absoluteString })
            case .text(let text):
                dto = try await RecipeImportAPI.importText(text)
            case .images(let items):
                if let validationError = ImportPhotoValidator.validate(items: items) {
                    throw validationError
                }
                dto = try await RecipeImportAPI.importImages(items)
            case .mixed(let urls, _):
                dto = try await RecipeImportAPI.importURLs(urls.map { $0.absoluteString })
            case .empty:
                phase = .error
                errorMessage = Self.localized("share-extension.error-no-content")
                return
            }
            lastResult = dto
            phase = .success
        } catch {
            errorMessage = ImportErrorLocalizer.localize(error, bundle: Self.resourceBundle)
            phase = .error
        }
    }

    private func openRecipeInHostApp() {
        let id: String?
        if let primary = lastResult?.recipeId {
            id = primary
        } else {
            id = lastResult?.recipeIds.first
        }
        guard let id,
              let url = URL(string: "\(DeepLinkURL.baseScheme)://recipe/\(id)") else {
            completeRequest()
            return
        }

        // App Group backup when URL delivery races cold start / open fails.
        AppGroup.userDefaults?.set(id, forKey: AppGroup.pendingRecipeIdKey)

        ExtensionHostURLOpener.open(
            url,
            extensionContext: extensionContext,
            from: hostBox.viewController
        ) { _ in
            self.completeRequest()
        }
    }

    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func cancel() {
        let error = NSError(domain: "ShareExtension", code: 0, userInfo: [
            NSLocalizedDescriptionKey: "User cancelled"
        ])
        extensionContext?.cancelRequest(withError: error)
    }

    // MARK: - Localization

    fileprivate static var resourceBundle: Bundle {
        Bundle(for: APIClient.self)
    }

    public static func localized(_ key: String) -> String {
        resourceBundle.localizedString(forKey: key, value: nil, table: "Shared")
    }

    fileprivate static func pluralized(_ key: String, count: Int) -> String {
        Bundle.pluralizedString(
            key: key,
            count: count,
            table: "Shared",
            locale: Locale.current,
            localizedString: { resourceBundle.localizedString(forKey: $0, value: nil, table: $1 ?? "Shared") }
        )
    }
}

// MARK: - Host VC box (weak ref from a SwiftUI value type)

private final class HostViewControllerBox {
    weak var viewController: UIViewController?

    init(_ viewController: UIViewController?) {
        self.viewController = viewController
    }
}

// MARK: - Phases

private struct PreviewPhase: View {
    let content: ShareContent
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    contentPreview
                }
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(action: onImport) {
                Text(verbatim: ShareView.localized("share-extension.button-import"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch content {
        case .urls(let urls):
            ForEach(urls, id: \.self) { url in
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)
                    Text(url.absoluteString)
                        .font(.body)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .text(let text):
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.body)
                .lineLimit(8)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .images(let items):
            Text(verbatim: ShareView.pluralized("share.photos-count", count: items.count))
                .font(.headline)
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
        case .mixed(let urls, let text):
            ForEach(urls, id: \.self) { url in
                Text(url.absoluteString)
                    .font(.body)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !text.isEmpty {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .empty:
            EmptyView()
        }
    }
}

private struct SuccessPhase: View {
    let result: ImportRecipesResultDTO?
    let onOpenRecipe: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            if let result, result.importedCount > 0 {
                Text(verbatim: ShareView.pluralized("share-extension.success", count: result.importedCount))
                    .font(.headline)
            } else {
                Text(verbatim: ShareView.localized("share-extension.success"))
                    .font(.headline)
            }
            Button(action: onOpenRecipe) {
                Text(verbatim: ShareView.localized("share-extension.button-open"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            Button(action: onDone) {
                Text(verbatim: ShareView.localized("share-extension.button-cancel"))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ErrorPhase: View {
    let message: String
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text(verbatim: message)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text(verbatim: ShareView.localized("share-extension.button-cancel"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button(action: onRetry) {
                    Text(verbatim: ShareView.localized("share-extension.button-retry"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NotSignedInPhase: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(verbatim: ShareView.localized("share-extension.error-not-signed-in"))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button(action: onDismiss) {
                Text(verbatim: ShareView.localized("share-extension.button-cancel"))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - State

private enum Phase: Equatable {
    case loading
    case preview
    case importing
    case success
    case error
    case notSignedIn
}

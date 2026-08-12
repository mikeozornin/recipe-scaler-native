import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import RecipeScalerCore

struct AccountFeedbackView: View {
    @Environment(YjsSyncService.self) private var syncService
    @Environment(AuthService.self) private var auth
    @State private var model = AccountFeedbackModel()
    @State private var showAttachDialog = false
    @State private var showPhotosPicker = false
    @State private var showFileImporter = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var submitTask: Task<Void, Never>?

    private var isOnline: Bool {
        syncService.connectionState == .connected
    }

    var body: some View {
        List {
            messageSection
            attachmentsSection
            if let errorMessage = model.errorMessage, !errorMessage.isEmpty {
                Section {
                    Text(verbatim: errorMessage)
                        .appFootnote()
                        .foregroundStyle(.red)
                        .accessibilityIdentifier(AccessibilityIdentifiers.accountFeedbackError)
                }
            }
        }
        .listStyle(.insetGrouped)
        .appListBodyTypography()
        .localizedNavigationTitle("account.feedback.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if model.isSubmitting {
                    ProgressView()
                } else {
                    Button {
                        submit()
                    } label: {
                        Text("account.feedback.send")
                    }
                    .disabled(!model.canSend || !isOnline || !auth.isAuthenticated)
                    .accessibilityIdentifier(AccessibilityIdentifiers.accountFeedbackSend)
                }
            }
        }
        .confirmationDialog(
            String(localized: "account.feedback.attach"),
            isPresented: $showAttachDialog,
            titleVisibility: .visible
        ) {
            Button("account.feedback.attach-photos") {
                showPhotosPicker = true
            }
            Button("account.feedback.attach-files") {
                showFileImporter = true
            }
            Button("common.cancel", role: .cancel) {}
        }
        .photosPicker(
            isPresented: $showPhotosPicker,
            selection: $photoItems,
            maxSelectionCount: max(model.remainingSlots, 1),
            matching: .images
        )
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await consumePhotos(items) }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            Task { await consumeFiles(result) }
        }
        .onDisappear {
            model.bumpGeneration()
            submitTask?.cancel()
        }
    }

    private var messageSection: some View {
        Section {
            ZStack(alignment: .topLeading) {
                if model.message.isEmpty {
                    Text("account.feedback.placeholder")
                        .font(AppTypography.body)
                        .lineSpacing(AppTypography.bodyLineSpacing)
                        .foregroundStyle(Color.primary.opacity(0.3))
                        .allowsHitTesting(false)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                }
                TextEditor(text: $model.message)
                    .font(AppTypography.body)
                    .lineSpacing(AppTypography.bodyLineSpacing)
                    .frame(minHeight: 160)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .accessibilityIdentifier(AccessibilityIdentifiers.accountFeedbackEditor)
            }
        }
    }

    private var attachmentsSection: some View {
        Section {
            Button {
                showAttachDialog = true
            } label: {
                AppLabel.make(LocalizedStringKey("account.feedback.attach"), symbol: "paperclip")
            }
            .disabled(model.remainingSlots == 0)
            .accessibilityIdentifier(AccessibilityIdentifiers.accountFeedbackAttach)

            ForEach(Array(model.attachments.enumerated()), id: \.element.id) { index, item in
                HStack {
                    Text(verbatim: item.fileName)
                        .appBody()
                        .lineLimit(1)
                    Spacer()
                    Button {
                        model.removeAttachment(id: item.id)
                    } label: {
                        AppSymbol.image("xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("account.feedback.remove-file"))
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.accountFeedbackAttachment(index: index))
            }
        }
    }

    private func submit() {
        submitTask?.cancel()
        submitTask = Task { @MainActor in
            let ok = await model.submit(
                isOnline: isOnline,
                isAuthenticated: auth.isAuthenticated
            )
            guard !Task.isCancelled else { return }
            if ok {
                ShoppingFeedback.postStatus(
                    Bundle.currentLocalizedString("account.feedback.sent"),
                    symbolName: "checkmark.circle.fill"
                )
            }
        }
    }

    private func consumePhotos(_ items: [PhotosPickerItem]) async {
        var incoming: [FeedbackAttachment] = []
        for (offset, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let utType = item.supportedContentTypes.first ?? .jpeg
            incoming.append(
                FeedbackAttachment(
                    fileName: "image-\(offset + 1).\(utType.preferredFilenameExtension ?? "jpg")",
                    mimeType: utType.preferredMIMEType ?? "image/jpeg",
                    data: data
                )
            )
        }
        photoItems = []
        if let key = model.addAttachments(incoming) {
            model.errorMessage = Bundle.currentLocalizedString(key)
        }
    }

    private func consumeFiles(_ result: Result<[URL], Error>) async {
        switch result {
        case .failure(let error):
            let nsError = error as NSError
            let cancelled = nsError.domain == NSCocoaErrorDomain
                && nsError.code == NSUserCancelledError
            guard !cancelled else { return }
            model.errorMessage = Bundle.currentLocalizedString("account.feedback.send-failed")
        case .success(let urls):
            let incoming = await Self.loadFileAttachments(urls)
            if let key = model.addAttachments(incoming) {
                model.errorMessage = Bundle.currentLocalizedString(key)
            }
        }
    }

    private static func loadFileAttachments(_ urls: [URL]) async -> [FeedbackAttachment] {
        await Task.detached(priority: .userInitiated) {
            var incoming: [FeedbackAttachment] = []
            for url in urls {
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }
                guard let data = try? Data(contentsOf: url) else { continue }
                let utType = UTType(filenameExtension: url.pathExtension) ?? .data
                incoming.append(
                    FeedbackAttachment(
                        fileName: url.lastPathComponent,
                        mimeType: utType.preferredMIMEType ?? "application/octet-stream",
                        data: data
                    )
                )
            }
            return incoming
        }.value
    }
}

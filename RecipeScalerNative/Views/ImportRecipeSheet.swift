//
//  ImportRecipeSheet.swift
//  RecipeScalerNative
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import RecipeScalerCore

struct ImportRecipesResult {
    let recipeIds: [String]
    let importedCount: Int

    init(recipeIds: [String], importedCount: Int? = nil) {
        self.recipeIds = recipeIds
        self.importedCount = importedCount ?? recipeIds.count
    }

    var primaryRecipeId: String? {
        recipeIds.count == 1 ? recipeIds.first : nil
    }
}

struct ImportRecipeSheet: View {
    let onImport: (ImportRecipesResult) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var syncService: YjsSyncService

    @State private var mode: ImportMode = .text
    @State private var bodyText = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var photoPreviews: [ImportPhotoItem] = []
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var selectedFileURL: URL?
    @State private var selectedFileName = ""
    @State private var showFileImporter = false
    @State private var progressMessage: String?
    @State private var importTask: Task<Void, Never>?

    enum ImportMode: String, CaseIterable {
        case text, photo, file
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("import.mode-accessibility", selection: $mode) {
                        Text("import.tab-text").tag(ImportMode.text)
                        Text("import.tab-photo").tag(ImportMode.photo)
                        Text("import.tab-file").tag(ImportMode.file)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel(Text("import.mode-accessibility"))
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                switch mode {
                case .text:
                    textSection
                case .photo:
                    photoSection
                case .file:
                    fileSection
                }

                if let progressMessage {
                    Section {
                        Text(progressMessage)
                            .appFootnote()
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .appFootnote()
                    }
                }
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.importSheet)
            .localizedNavigationTitle("import.title")
            .appListBodyTypography()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if isProcessing, mode == .file {
                        Button("import.third-party-cancel") {
                            importTask?.cancel()
                        }
                        .appToolbarTextButton()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if canShowSubmit {
                        Button {
                            importTask = Task { await submit() }
                        } label: {
                            if isProcessing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("import.lets-go")
                            }
                        }
                        .appToolbarConfirmButton()
                        .disabled(isProcessing || !canSubmit)
                    } else if mode != .file {
                        Button("import.try-later") { dismiss() }
                            .appToolbarTextButton()
                    }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: Self.importFileTypes,
                allowsMultipleSelection: false
            ) { result in
                handleFileImportSelection(result)
            }
            .onAppear { resetState() }
            .onChange(of: mode) { _, _ in
                errorMessage = nil
                progressMessage = nil
            }
            .onDisappear {
                importTask?.cancel()
            }
        }
    }

    // MARK: - Text mode

    private var textSection: some View {
        Section {
            ZStack(alignment: .topLeading) {
                if bodyText.isEmpty {
                    Text("import.text-placeholder")
                        .font(AppTypography.body)
                        .lineSpacing(AppTypography.bodyLineSpacing)
                        .foregroundStyle(Color.primary.opacity(0.3))
                        .allowsHitTesting(false)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                }
                TextEditor(text: $bodyText)
                    .font(AppTypography.body)
                    .lineSpacing(AppTypography.bodyLineSpacing)
                    .frame(minHeight: 160)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }
        } footer: {
            Text("import.text-file-hint")
                .appFootnote()
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Photo mode

    private var photoSection: some View {
        Section {
            PhotosPicker(
                selection: $photoItems,
                maxSelectionCount: ImportPhotoValidator.maxImages,
                matching: .images
            ) {
                AppLabel.make(LocalizedStringKey("import.choose-photos"), symbol: "photo")
            }
            .onChange(of: photoItems) { _, newItems in
                Task { await reloadPhotoPreviews(from: newItems) }
            }

            if !photoPreviews.isEmpty {
                photoPreviewStrip
            }

            Text(photoCountLabel)
                .appFootnote()
                .foregroundStyle(.secondary)
        } footer: {
            Text("import.photo-helper")
                .appFootnote()
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - File mode

    private var fileSection: some View {
        Section {
            Button {
                showFileImporter = true
            } label: {
                AppLabel.make(LocalizedStringKey("import.file-pick"), symbol: "doc.zipper")
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.importFilePickButton)

            if !selectedFileName.isEmpty {
                Text(selectedFileName)
                    .appFootnote()
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("import.file-hint")
                .appFootnote()
                .foregroundStyle(.secondary)
        }
    }

    private var photoPreviewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(photoPreviews.enumerated()), id: \.offset) { index, item in
                    photoThumbnail(for: item, index: index)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func photoThumbnail(for item: ImportPhotoItem, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let uiImage = UIImage(data: item.data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.tertiarySystemFill))
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button {
                removePhoto(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, .black.opacity(0.6))
                    .font(.system(size: 20))
            }
            .offset(x: 6, y: -6)
            .accessibilityLabel(Text("common.delete-image"))
        }
    }

    private var photoCountLabel: String {
        let template = Bundle.currentLocalizedString("import.photo-count")
        return String(
            format: template,
            locale: AppLanguagePreference.current.locale,
            photoPreviews.count,
            ImportPhotoValidator.maxImages
        )
    }

    private func removePhoto(at index: Int) {
        guard photoPreviews.indices.contains(index) else { return }
        photoPreviews.remove(at: index)
        if photoItems.indices.contains(index) {
            photoItems.remove(at: index)
        }
        errorMessage = nil
    }

    @MainActor
    private func reloadPhotoPreviews(from items: [PhotosPickerItem]) async {
        var previews: [ImportPhotoItem] = []
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let supported = item.supportedContentTypes.first ?? .jpeg
                previews.append(ImportPhotoItem(data: data, fileName: imageName(for: supported), utType: supported))
            } catch {
                continue
            }
        }
        photoPreviews = previews
        errorMessage = nil
    }

    private func imageName(for utType: UTType) -> String {
        if utType.conforms(to: .png) { return "image.png" }
        if utType.conforms(to: .webP) { return "image.webp" }
        if utType.conforms(to: .heic) { return "image.heic" }
        return "image.jpg"
    }

    private static var importFileTypes: [UTType] {
        var types: [UTType] = [.zip, .data, .plainText, .json]
        // Markdown: `.md` — falls under public.text but `.plainText` already
        // covers it; we register the explicit extension as a fallback in case
        // the system does not have a `net.daringfireball.markdown` UTType.
        if let markdown = UTType(filenameExtension: "md") {
            types.append(markdown)
        }
        if let paprikaArchive = UTType(filenameExtension: "paprikarecipes") {
            types.append(paprikaArchive)
        }
        if let paprikaSingle = UTType(filenameExtension: "paprikarecipe") {
            types.append(paprikaSingle)
        }
        if let crumb = UTType(filenameExtension: "crumb") {
            types.append(crumb)
        }
        return types
    }

    private func handleFileImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            selectedFileURL = url
            selectedFileName = url.lastPathComponent
            errorMessage = nil
        case let .failure(error):
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Submit

    private var canSubmit: Bool {
        switch mode {
        case .text:
            !bodyText.trimmingCharacters(in: .whitespaces).isEmpty
        case .photo:
            !photoPreviews.isEmpty
        case .file:
            selectedFileURL != nil
        }
    }

    private var canShowSubmit: Bool {
        switch mode {
        case .file:
            true
        default:
            isOnline
        }
    }

    private var isOnline: Bool {
        syncService.connectionState == .connected
    }

    @MainActor
    private func submit() async {
        if mode != .file {
            guard isOnline else {
                errorMessage = Bundle.currentLocalizedString("import.offline-unavailable")
                return
            }
        }

        isProcessing = true
        errorMessage = nil
        progressMessage = nil
        defer {
            isProcessing = false
            progressMessage = nil
        }

        do {
            switch mode {
            case .text, .photo:
                let dto = try await submitServerImport()
                let result = ImportRecipesResult(
                    recipeIds: dto.recipeIds.isEmpty && dto.recipeId != nil ? [dto.recipeId!] : dto.recipeIds,
                    importedCount: dto.importedCount
                )
                onImport(result)
                dismiss()

            case .file:
                guard let fileURL = selectedFileURL else { return }

                // Plain-text files (.txt / .md / .json) — reuse the existing
                // server text-import pipeline instead of third-party archive
                // parser. Spec 010 US7.
                if Self.isPlainTextFile(fileURL) {
                    do {
                        let text = try Self.readPlainText(from: fileURL)
                        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            errorMessage = Bundle.currentLocalizedString("import.text-placeholder")
                            return
                        }
                        let dto = try await RecipeImportAPI.importText(text)
                        let result = ImportRecipesResult(
                            recipeIds: dto.recipeIds.isEmpty && dto.recipeId != nil
                                ? [dto.recipeId!]
                                : dto.recipeIds,
                            importedCount: dto.importedCount
                        )
                        onImport(result)
                        dismiss()
                    } catch {
                        errorMessage = ImportErrorLocalizer.localize(error)
                    }
                    return
                }

                let service = ThirdPartyRecipeImportService(syncService: syncService)
                let importResult = try await service.importFile(
                    url: fileURL,
                    isOnline: isOnline
                ) { completed, total in
                    Task { @MainActor in
                        progressMessage = ThirdPartyImportErrorLocalizer.progressMessage(
                            completed: completed,
                            total: total
                        )
                    }
                }

                guard !importResult.importedRecipeIds.isEmpty else {
                    if let firstFailure = importResult.failed.first {
                        errorMessage = ThirdPartyImportErrorLocalizer.localize(firstFailure.error)
                    } else {
                        errorMessage = Bundle.currentLocalizedString("import.third-party-empty")
                    }
                    return
                }

                let result = ImportRecipesResult(recipeIds: importResult.importedRecipeIds)
                onImport(result)
                dismiss()
            }
        } catch let error as ThirdPartyImportError {
            errorMessage = ThirdPartyImportErrorLocalizer.localize(error)
        } catch {
            if mode == .file {
                errorMessage = ThirdPartyImportErrorLocalizer.localize(.unsupportedFormat)
            } else {
                errorMessage = ImportErrorLocalizer.localize(error)
            }
        }
    }

    private func submitServerImport() async throws -> ImportRecipesResultDTO {
        switch mode {
        case .text:
            let trimmed = bodyText.trimmingCharacters(in: .whitespaces)
            let classification = ImportContentClassifier.classify(trimmed)

            if classification.isUrlOnly {
                if classification.urls.count > 25 {
                    throw NSError(
                        domain: "ImportRecipeSheet",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "import.error-too-many-recipes"]
                    )
                }
                return try await RecipeImportAPI.importURLs(classification.urls)
            }
            return try await RecipeImportAPI.importText(trimmed)

        case .photo:
            if let validationError = ImportPhotoValidator.validate(items: photoPreviews) {
                throw validationError
            }
            return try await RecipeImportAPI.importImages(photoPreviews)

        case .file:
            throw ThirdPartyImportError.unsupportedFormat
        }
    }

    private func resetState() {
        mode = .text
        bodyText = ""
        photoItems = []
        photoPreviews = []
        selectedFileURL = nil
        selectedFileName = ""
        errorMessage = nil
        progressMessage = nil
    }

    // MARK: - Plain-text file detection (US7)

    /// Returns `true` for files that should be uploaded as text content rather
    /// than parsed as third-party archives: `.txt`, `.md`, `.json`, and any
    /// file whose UTType conforms to `public.plain-text`.
    static func isPlainTextFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ["txt", "md", "markdown", "json"].contains(ext) {
            return true
        }
        if let type = UTType(filenameExtension: ext),
           type.conforms(to: .plainText) {
            return true
        }
        return false
    }

    /// Read the file contents as UTF-8 text, scoped to the security URL.
    static func readPlainText(from url: URL) throws -> String {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

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
    @Environment(YjsSyncService.self) private var syncService

    @State private var mode: ImportMode = .text
    @State private var bodyText = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var photoPreviews: [ImportPhotoItem] = []
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var photoWarning: String?
    @State private var selectedFileURL: URL?
    @State private var selectedFileName = ""
    @State private var showFileImporter = false
    @State private var fileImportProgress: (completed: Int, total: Int, messageKey: String)?
    @State private var importTask: Task<Void, Never>?
    /// Guards `onChange(of: mode)` against wiping `errorMessage`/`photoWarning`/
    /// `fileImportProgress` on system-driven mode changes (offline auto-fallback).
    /// The wipe is intended only for user-initiated tab switches, where stale
    /// errors from a different mode would be misleading. Set to `true` before a
    /// system-driven `mode =` assignment, reset on the next runloop pass.
    @State private var isSystemModeChange = false

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
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                if showsOfflineBanner {
                    Section {
                        Label {
                            Text("import.offline-banner")
                                .appBody()
                                .foregroundStyle(.secondary)
                        } icon: {
                            AppSymbol.image("wifi.slash")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                switch mode {
                case .text:
                    textSection
                case .photo:
                    photoSection
                case .file:
                    fileSection
                }

                if let fileImportProgress, isProcessing, mode == .file {
                    Section {
                        FractionProgressView(
                            completed: fileImportProgress.completed,
                            total: fileImportProgress.total,
                            messageKey: fileImportProgress.messageKey
                        )
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .appFootnote()
                    }
                }

                if let photoWarning {
                    Section {
                        Text(photoWarning)
                            .foregroundStyle(.orange)
                            .appFootnote()
                    }
                }
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.importSheet)
            .localizedNavigationTitle("import.title")
            .appListBodyTypography()
            .appOpaqueGroupedListSurface()
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
                        .accessibilityIdentifier(AccessibilityIdentifiers.importSubmitButton)
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
                // Only wipe transient state on user-initiated tab switches.
                // System-driven fallback (offline auto-switch in
                // `applySystemMode`) sets `isSystemModeChange` to skip this,
                // so connectivity flaps don't wipe errors the user is reading.
                guard !isSystemModeChange else { return }
                errorMessage = nil
                photoWarning = nil
                fileImportProgress = nil
            }
            .onChange(of: isOnline) { _, online in
                // Auto-fall-back to `.file` if the selected text/photo segment
                // became disabled while offline (can't leave a disabled segment
                // selected). Online, leave the user's current mode alone — we
                // do NOT auto-restore the previous mode, by design: once the
                // user has been moved to `.file`, switching back automatically
                // would be surprising.
                if !online, mode != .file {
                    applySystemMode(.file)
                }
            }
            .onDisappear {
                importTask?.cancel()
            }
        }
        .appOpaqueSheetPresentationPlain(detents: [.large])
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
        var types = RecipeImportContentTypes.supported
        // Plain text and markdown drive the server-side text-import pipeline
        // (Spec 010 US7) and are intentionally absent from the shared helper
        // because Profile import does not support text mode.
        types.append(.plainText)
        if let markdown = UTType(filenameExtension: "md") {
            types.append(markdown)
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
            errorMessage = UserFacingAPIError.message(for: error)
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

    /// UI-gating: optimistic. A device that is connecting/reconnecting is
    /// shown as online (segments enabled, no banner) because that's the
    /// visually honest state during the normal 1–3s cold-launch window —
    /// `SyncStatusSheet` shows a spinner, not `wifi.slash`, in these states.
    /// Matches the contract used for `submit()`'s pre-check below.
    private var isOnline: Bool {
        switch syncService.connectionState {
        case .connected, .connecting, .reconnecting:
            return true
        case .disconnected, .error:
            return false
        }
    }

    /// Service-gating: strict. Used only where we actually need a live socket
    /// to push recipes to the server (NativeExportImportService /
    /// ThirdPartyRecipeImportService). Those services already have a
    /// `waitForConnection(timeout:)` grace window when passed `false`, so being
    /// strict here lets them decide whether to wait or fall back to offline-skip.
    private var isConnectedStrict: Bool {
        syncService.connectionState.isConnected
    }

    /// Instant offline banner under the segmented control. Shown whenever the
    /// device is offline regardless of selected mode — text/photo segments are
    /// already disabled, file import still works. Auto-fallback to `.file`
    /// (see `onChange(of: isOnline)` / `resetState()`) must NOT hide the
    /// banner, otherwise the user loses the offline signal.
    /// Spec 066 intentionally excludes ImportRecipeSheet from the debounced
    /// `OfflineBannerGate` — feature-gating here stays instant.
    private var showsOfflineBanner: Bool {
        !isOnline
    }

    /// Set `mode` from a system-driven path (offline auto-fallback,
    /// cold-open default). Sets `isSystemModeChange` so `onChange(of: mode)`
    /// skips its wipe of `errorMessage` / `photoWarning` / `fileImportProgress`
    /// — those are user-visible state and must survive connectivity flaps.
    /// The flag resets on the next runloop pass so a subsequent user-initiated
    /// tap on a segment still wipes as expected.
    private func applySystemMode(_ newMode: ImportMode) {
        guard mode != newMode else { return }
        isSystemModeChange = true
        mode = newMode
        Task { @MainActor in
            isSystemModeChange = false
        }
    }

    @MainActor
    private func submit() async {
        if mode != .file {
            // Use strict connectivity here, not the optimistic `isOnline`:
            // pressing Submit is an explicit user action, and the safety net
            // should catch a not-yet-established connection before we attempt
            // a network call that will fail with a less specific error.
            guard isConnectedStrict else {
                errorMessage = Bundle.currentLocalizedString("import.offline-unavailable")
                return
            }
        }

        isProcessing = true
        errorMessage = nil
        photoWarning = nil
        fileImportProgress = nil
        defer {
            isProcessing = false
            fileImportProgress = nil
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
                        errorMessage = ImportErrorLocalizer.localize(error, locale: AppLanguagePreference.current.locale)
                    }
                    return
                }

                // Check for native Recipe Scaler format (v1.0–v1.4)
                if NativeExportImportService.isNativeFormat(url: fileURL) {
                    let nativeService = NativeExportImportService(syncService: syncService)
                    let nativeResult = try await nativeService.importFile(
                        url: fileURL,
                        isOnline: isConnectedStrict
                    ) { completed, total in
                        Task { @MainActor in
                            fileImportProgress = (
                                completed,
                                total,
                                "account.data.import.progress %d %d"
                            )
                        }
                    }

                    let result = ImportRecipesResult(
                        recipeIds: nativeResult.importedRecipeIds,
                        importedCount: nativeResult.importedCount
                    )
                    onImport(result)

                    if !nativeResult.errors.isEmpty {
                        errorMessage = nativeResult.errors.joined(separator: "\n")
                    } else if !nativeResult.warnings.isEmpty {
                        errorMessage = nativeResult.warnings.joined(separator: "\n")
                    } else if nativeResult.importedCount > 0 {
                        dismiss()
                    } else {
                        errorMessage = Bundle.currentLocalizedString("import.third-party-empty")
                    }
                    return
                }

                let service = ThirdPartyRecipeImportService(syncService: syncService)
                let importResult = try await service.importFile(
                    url: fileURL,
                    isOnline: isConnectedStrict
                ) { completed, total in
                    Task { @MainActor in
                        fileImportProgress = (
                            completed,
                            total,
                            "import.third-party-progress"
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

                photoWarning = ThirdPartyImportErrorLocalizer.photoWarningMessage(for: importResult)

                let result = ImportRecipesResult(recipeIds: importResult.importedRecipeIds)
                onImport(result)
                if errorMessage == nil {
                    dismiss()
                }
            }
        } catch let error as ThirdPartyImportError {
            errorMessage = ThirdPartyImportErrorLocalizer.localize(error)
        } catch {
            if mode == .file {
                errorMessage = ThirdPartyImportErrorLocalizer.localize(.unsupportedFormat)
            } else {
                errorMessage = ImportErrorLocalizer.localize(error, locale: AppLanguagePreference.current.locale)
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
        // Offline cold-open: text/photo segments are disabled, start on `.file`
        // so the user lands on an enabled segment (can't leave `.text` selected
        // when its segment is disabled — UI would show a dimmed, unselectable tab).
        // Route through `applySystemMode` to skip the `onChange(of: mode)` wipe
        // (irrelevant here since we wipe everything below, but keeps the
        // no-wipe-on-system-change invariant uniform).
        let targetMode: ImportMode = isOnline ? .text : .file
        if mode != targetMode {
            applySystemMode(targetMode)
        }
        bodyText = ""
        photoItems = []
        photoPreviews = []
        selectedFileURL = nil
        selectedFileName = ""
        errorMessage = nil
        photoWarning = nil
        fileImportProgress = nil
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

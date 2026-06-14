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

    enum ImportMode: String, CaseIterable {
        case text, photo
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("import.mode-accessibility", selection: $mode) {
                        Text("import.tab-text").tag(ImportMode.text)
                        Text("import.tab-photo").tag(ImportMode.photo)
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
                ToolbarItem(placement: .confirmationAction) {
                    if isOnline {
                        Button {
                            Task { await submit() }
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
                    } else {
                        Button("import.try-later") { dismiss() }
                            .appToolbarTextButton()
                    }
                }
            }
            .onAppear { resetState() }
            .onChange(of: mode) { _, _ in errorMessage = nil }
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

    // MARK: - Submit

    private var canSubmit: Bool {
        switch mode {
        case .text: !bodyText.trimmingCharacters(in: .whitespaces).isEmpty
        case .photo: !photoPreviews.isEmpty
        }
    }

    private var isOnline: Bool {
        syncService.connectionState == .connected
    }

    @MainActor
    private func submit() async {
        guard isOnline else {
            errorMessage = Bundle.currentLocalizedString("import.offline-unavailable")
            return
        }

        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }

        do {
            let dto: ImportRecipesResultDTO

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
                    dto = try await RecipeImportAPI.importURLs(classification.urls)
                } else {
                    dto = try await RecipeImportAPI.importText(trimmed)
                }

            case .photo:
                if let validationError = ImportPhotoValidator.validate(items: photoPreviews) {
                    throw validationError
                }
                dto = try await RecipeImportAPI.importImages(photoPreviews)
            }

            let result = ImportRecipesResult(
                recipeIds: dto.recipeIds.isEmpty && dto.recipeId != nil ? [dto.recipeId!] : dto.recipeIds,
                importedCount: dto.importedCount
            )
            onImport(result)
            dismiss()
        } catch {
            errorMessage = ImportErrorLocalizer.localize(error)
        }
    }

    private func resetState() {
        mode = .text
        bodyText = ""
        photoItems = []
        photoPreviews = []
        errorMessage = nil
    }
}

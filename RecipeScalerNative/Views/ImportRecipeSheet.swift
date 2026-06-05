//
//  ImportRecipeSheet.swift
//  RecipeScalerNative
//

import SwiftUI
import PhotosUI

struct ImportRecipesResult {
    let recipeIds: [String]
    var primaryRecipeId: String? {
        recipeIds.count == 1 ? recipeIds.first : recipeIds.first
    }
}

struct ImportRecipeSheet: View {
    let onImport: (ImportRecipesResult) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var syncService: YjsSyncService

    @State private var urlText = ""
    @State private var bodyText = ""
    @State private var mode: ImportMode = .url
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var photoItems: [PhotosPickerItem] = []

    enum ImportMode: String, CaseIterable {
        case url, text, photo
    }

    var body: some View {
        NavigationStack {
            Form {
                AppSegmentedControl(
                    segments: [
                        .init(value: ImportMode.url, title: "URL"),
                        .init(value: ImportMode.text, title: "Text"),
                        .init(value: ImportMode.photo, title: "Photo"),
                    ],
                    selection: $mode
                )
                .accessibilityLabel("Mode")

                switch mode {
                case .url:
                    TextField("https://…", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                case .text:
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 160)
                case .photo:
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 8, matching: .images) {
                        AppLabel.make("Choose photos", symbol: "photo")
                    }
                    Text("\(photoItems.count) selected (max 8)")
                        .appFootnote()
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .appFootnote()
                }
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.importSheet)
            .navigationTitle("Import recipe")
            .appListBodyTypography()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .appToolbarTextButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { Task { await submit() } }
                        .appToolbarConfirmButton()
                        .disabled(isProcessing || !canSubmit)
                }
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.importSheet)
        }
    }

    private var canSubmit: Bool {
        switch mode {
        case .url: !urlText.trimmingCharacters(in: .whitespaces).isEmpty
        case .text: !bodyText.trimmingCharacters(in: .whitespaces).isEmpty
        case .photo: !photoItems.isEmpty
        }
    }

    private var isOnline: Bool {
        syncService.connectionState == .connected
    }

    @MainActor
    private func submit() async {
        guard isOnline else {
            errorMessage = String(localized: "Offline — import unavailable")
            return
        }
        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }
        do {
            let dto: ImportRecipesResultDTO
            switch mode {
            case .url:
                dto = try await RecipeImportAPI.importURL(urlText.trimmingCharacters(in: .whitespaces))
            case .text:
                dto = try await RecipeImportAPI.importText(bodyText)
            case .photo:
                var datas: [Data] = []
                for item in photoItems {
                    if let data = try await item.loadTransferable(type: Data.self) {
                        datas.append(data)
                    }
                }
                dto = try await RecipeImportAPI.importImages(datas, fileNames: datas.indices.map { "image\($0).jpg" })
            }
            let result = ImportRecipesResult(recipeIds: dto.recipeIds)
            onImport(result)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
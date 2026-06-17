//
//  RecipeDetailImageSection.swift
//  RecipeScalerNative
//

import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import RecipeScalerCore

/// Recipe hero image with web-style delete overlay (edit) and upload dropzone when empty.
struct RecipeDetailImageSection: View {
    let recipeId: String
    let imageUrl: String?
    let imageAspectRatio: CGFloat?
    let isEditing: Bool
    let allowsNetworkRefresh: Bool

    @EnvironmentObject private var syncService: YjsSyncService
    @State private var photoItem: PhotosPickerItem?
    @State private var isPhotoPickerPresented = false
    @State private var isUploading = false
    @State private var isDeleting = false

    private var hasImage: Bool {
        guard let imageUrl, !imageUrl.isEmpty else { return false }
        return true
    }

    var body: some View {
        Group {
            if hasImage {
                imageWithOverlay
            } else if isEditing {
                uploadDropzone
            }
        }
        .onChange(of: photoItem) { _, item in
            Task { await uploadPhoto(item) }
        }
    }

    @ViewBuilder
    private var imageWithOverlay: some View {
        ZStack(alignment: .bottomTrailing) {
            RecipeCachedImageView(
                recipeId: recipeId,
                imageUrl: imageUrl,
                variant: .full,
                allowsNetworkRefresh: allowsNetworkRefresh,
                layoutAspectRatio: imageAspectRatio,
                fullWidthHero: true,
                maxHeight: 400
            )

            if isEditing, allowsNetworkRefresh {
                Button {
                    Task { await deleteImage() }
                } label: {
                    AppSymbol.image("xmark")
                        .font(AppTypography.bodySemibold)
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(12)
                .disabled(isDeleting || isUploading)
                .accessibilityLabel("recipe.image.delete")
            }

            if isDeleting || isUploading {
                Color.black.opacity(0.25)
                    .frame(maxWidth: .infinity, maxHeight: 400)
                ProgressView()
            }
        }
    }

    private var uploadDropzone: some View {
        VStack(spacing: 8) {
            Button {
                guard !isUploading, allowsNetworkRefresh else { return }
                isPhotoPickerPresented = true
            } label: {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 52))
                        .foregroundStyle(Color(.secondaryLabel))

                    Text("recipe.image.upload.title")
                        .appBody()
                        .foregroundStyle(Color(.secondaryLabel))

                    if !allowsNetworkRefresh {
                        Text("recipe.image.upload.offline")
                            .appFootnote()
                            .foregroundStyle(Color(.secondaryLabel))
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemGray6))
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .photosPicker(
                isPresented: $isPhotoPickerPresented,
                selection: $photoItem,
                matching: .images
            )
            .disabled(isUploading || !allowsNetworkRefresh)
            .accessibilityIdentifier(AccessibilityIdentifiers.recipeImageUpload)
        }
        .padding(.horizontal, RecipeRowLayoutMetrics.listHorizontalInset)
        .padding(.top, RecipeRowLayoutMetrics.listHorizontalInset)
        .overlay {
            if isUploading {
                ProgressView()
            }
        }
    }

    private func uploadPhoto(_ item: PhotosPickerItem?) async {
        guard allowsNetworkRefresh, let item else { return }

        isUploading = true
        defer {
            isUploading = false
            photoItem = nil
        }

        guard let rawData = await loadImageData(from: item) else {
            await MainActor.run {
                syncService.syncErrorMessage = Bundle.currentLocalizedString("recipe.image.upload.failed")
            }
            return
        }

        guard let payload = await RecipeImageUploadPreprocessor.payloadForUpload(from: rawData) else {
            await MainActor.run {
                syncService.syncErrorMessage = Bundle.currentLocalizedString("recipe.image.upload.failed")
            }
            return
        }

        do {
            let result = try await RecipeImageUploadAPI.upload(recipeId: recipeId, payload: payload)
            try await syncService.applyRecipeImageUpload(recipeId: recipeId, result: result)
        } catch {
            await MainActor.run {
                syncService.syncErrorMessage = Self.uploadErrorMessage(for: error)
            }
        }
    }

    private static func uploadErrorMessage(for error: Error) -> String {
        if case APIError.httpError(let code) = error, code == 413 {
            return Bundle.currentLocalizedString("recipe.image.upload.limit")
        }
        return Bundle.currentLocalizedString("recipe.image.upload.failed")
    }

    private func deleteImage() async {
        guard allowsNetworkRefresh else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await RecipeImageUploadAPI.delete(recipeId: recipeId)
            try await syncService.applyRecipeImageDeletion(recipeId: recipeId)
        } catch {
            await MainActor.run {
                syncService.syncErrorMessage = UserFacingAPIError.message(for: error)
            }
        }
    }

    private func loadImageData(from item: PhotosPickerItem) async -> Data? {
        if let picked = try? await item.loadTransferable(type: PickedImageData.self) {
            return picked.data
        }
        return try? await item.loadTransferable(type: Data.self)
    }
}

private struct PickedImageData: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .heic) { data in PickedImageData(data: data) }
        DataRepresentation(importedContentType: .heif) { data in PickedImageData(data: data) }
        DataRepresentation(importedContentType: .webP) { data in PickedImageData(data: data) }
        DataRepresentation(importedContentType: .jpeg) { data in PickedImageData(data: data) }
        DataRepresentation(importedContentType: .image) { data in PickedImageData(data: data) }
    }
}
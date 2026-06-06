//
//  ShareContentLoader.swift
//  RecipeScalerCore
//
//  Async helpers to extract URLs / text / images from NSExtensionContext attachments.
//  Shared between Share Extension and Action Extension.
//

import Foundation
import UIKit
import UniformTypeIdentifiers

/// Classified payload that an extension can import.
public enum ShareContent {
    /// One or more URLs only.
    case urls([URL])
    /// Free-form text — may still contain URLs that the classifier will route to URL import.
    case text(String)
    /// 1..8 images.
    case images([ImportPhotoItem])
    /// URL + accompanying text (e.g. a message with link and a comment).
    case mixed(urls: [URL], text: String)
    /// Nothing recognizable.
    case empty
}

public enum ShareContentLoader {

    /// Walk every attachment of every input item and aggregate providers by type.
    /// Priority on classification is applied by `classify(_:)` below.
    public static func load(from context: NSExtensionContext) async -> ShareContent {
        var urls: [URL] = []
        var texts: [String] = []
        var images: [ImportPhotoItem] = []

        for item in context.inputItems.compactMap({ $0 as? NSExtensionItem }) {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = await loadURL(from: provider) {
                        urls.append(url)
                    }
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                    if let text = await loadText(from: provider) {
                        texts.append(text)
                    }
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let item = await loadImageItem(from: provider) {
                        images.append(item)
                    }
                }
            }
        }

        return classify(urls: urls, texts: texts, images: images)
    }

    // MARK: - Type-specific loaders

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { result, _ in
                if let url = result as? URL {
                    continuation.resume(returning: url)
                } else if let data = result as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else if let string = result as? String,
                          let url = URL(string: string) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { result, _ in
                if let string = result as? String {
                    continuation.resume(returning: string)
                } else if let data = result as? Data,
                          let s = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: s)
                } else if let attr = result as? NSAttributedString {
                    continuation.resume(returning: attr.string)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func loadImageItem(from provider: NSItemProvider) async -> ImportPhotoItem? {
        await withCheckedContinuation { (continuation: CheckedContinuation<ImportPhotoItem?, Never>) in
            let typeIdentifier: String = {
                if provider.hasItemConformingToTypeIdentifier(UTType.jpeg.identifier) {
                    return UTType.jpeg.identifier
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.png.identifier) {
                    return UTType.png.identifier
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.heic.identifier) {
                    return UTType.heic.identifier
                }
                return UTType.image.identifier
            }()

            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { result, _ in
                if let url = result as? URL,
                   let data = try? Data(contentsOf: url) {
                    let utType = UTType(typeIdentifier)
                    let fileName = url.lastPathComponent.isEmpty ? "image.jpg" : url.lastPathComponent
                    continuation.resume(
                        returning: ImportPhotoItem(data: data, fileName: fileName, utType: utType)
                    )
                } else if let data = result as? Data {
                    let utType = UTType(typeIdentifier)
                    continuation.resume(
                        returning: ImportPhotoItem(data: data, fileName: "image.jpg", utType: utType)
                    )
                } else if let image = result as? UIImage,
                          let data = image.jpegData(compressionQuality: 0.92) {
                    continuation.resume(
                        returning: ImportPhotoItem(data: data, fileName: "image.jpg", utType: .jpeg)
                    )
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Classification

    /// Apply priority: URL → Images → Text. URLs+text become `.mixed`.
    private static func classify(
        urls: [URL],
        texts: [String],
        images: [ImportPhotoItem]
    ) -> ShareContent {
        if !urls.isEmpty {
            let combined = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if combined.isEmpty {
                return .urls(urls)
            }
            return .mixed(urls: urls, text: combined)
        }
        if !images.isEmpty {
            return .images(images)
        }
        let combined = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !combined.isEmpty else { return .empty }

        let cls = ImportContentClassifier.classify(combined)
        if cls.isUrlOnly, let first = cls.urls.first, let url = URL(string: first) {
            return .urls([url])
        }
        return .text(combined)
    }
}

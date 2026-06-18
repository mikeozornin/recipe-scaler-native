//
//  ShareContentClassifier.swift
//  RecipeScalerCore
//
//  Spec 025 T033 — pure-logic classifier for Share attachments.
//
//  Priority order (per spec US2/US3/US4): URL > Images > Text.
//  - 1+ URL → `.urls([URL])` (or `.mixed` if text also present).
//  - 0 URLs and 1+ images → `.images`.
//  - 0 URLs and 0 images and non-empty text → `.text` (or `.urls` if text
//    contains exactly one URL, via `ImportContentClassifier`).
//  - Otherwise → `.empty`.
//
//  `ShareContentLoader.classify` delegates here so the priority logic is
//  unit-testable without `NSItemProvider`.
//

import Foundation
import RecipeScalerCore

public enum ShareContentClassifier {

    /// Apply URL > Images > Text priority to the raw attachment collections
    /// that `ShareContentLoader` gathered from `NSExtensionContext`.
    public static func classify(
        urls: [URL],
        texts: [String],
        images: [ImportPhotoItem]
    ) -> ShareContent {
        let combinedText = texts
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !urls.isEmpty {
            if combinedText.isEmpty {
                return .urls(urls)
            }
            return .mixed(urls: urls, text: combinedText)
        }

        if !images.isEmpty {
            return .images(images)
        }

        guard !combinedText.isEmpty else { return .empty }

        let cls = ImportContentClassifier.classify(combinedText)
        if cls.isUrlOnly, let first = cls.urls.first, let url = URL(string: first) {
            return .urls([url])
        }
        return .text(combinedText)
    }
}

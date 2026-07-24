//
//  TimerLiveActivityMetadataProvider.swift
//  RecipeScalerNative
//

import Foundation
import UIKit
import RecipeScalerCore

struct TimerLiveActivityRecipeMetadata: Sendable {
    var recipeName: String?
    var thumbnailName: String?
}

@MainActor
enum TimerLiveActivityMetadataProvider {
    /// Installed from `ContentView` where `YjsSyncService` is available.
    static var recipeNameLookup: ((String) -> String?)?

    private static let appGroupIdentifier = AppGroup.id

    static func metadata(for recipeId: String?) async -> TimerLiveActivityRecipeMetadata {
        guard let recipeId, !recipeId.isEmpty else {
            return TimerLiveActivityRecipeMetadata()
        }

        let name = recipeNameLookup?(recipeId)
        let thumbnailName = saveThumbnailToAppGroup(recipeId: recipeId)
        return TimerLiveActivityRecipeMetadata(recipeName: name, thumbnailName: thumbnailName)
    }

    private static func saveThumbnailToAppGroup(recipeId: String) -> String? {
        guard let fileURL = RecipeImageDiskCache.existingFileURL(recipeId: recipeId, variant: .preview)
            ?? RecipeImageDiskCache.existingFileURL(recipeId: recipeId, variant: .full),
              let image = UIImage(contentsOfFile: fileURL.path) else {
            return nil
        }

        let side: CGFloat = 24
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        guard let jpegData = scaled.jpegData(compressionQuality: 0.6) else { return nil }

        let fileName = "la-thumb-\(recipeId).jpg"
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { return nil }

        let thumbDir = container.appendingPathComponent("la-thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: thumbDir, withIntermediateDirectories: true)
        let thumbURL = thumbDir.appendingPathComponent(fileName)
        do {
            try jpegData.write(to: thumbURL, options: .atomic)
            return fileName
        } catch {
            return nil
        }
    }

    static func thumbnailImage(name: String?) -> UIImage? {
        guard let name, !name.isEmpty else { return nil }
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { return nil }
        let url = container.appendingPathComponent("la-thumbs/\(name)")
        return UIImage(contentsOfFile: url.path)
    }
}

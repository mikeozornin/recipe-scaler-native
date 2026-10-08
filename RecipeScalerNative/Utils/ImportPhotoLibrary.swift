//
//  ImportPhotoLibrary.swift
//  RecipeScalerNative
//
//  Spec 080 — albums and photos for the Photo tab grid of `ImportRecipeSheet`.
//  Ported from scrapp's `AddSheet` (PhotoLibrary / PhotoAssets).
//

import Photos
import PhotosUI
import RecipeScalerCore
import SwiftUI
import UniformTypeIdentifiers

/// Albums and their photos, newest first. Needs Photos access, unlike the system picker.
@MainActor
@Observable
final class ImportPhotoLibrary {
    struct Album: Identifiable {
        let id: String
        let title: String

        init(_ collection: PHAssetCollection) {
            id = collection.localIdentifier
            title = collection.localizedTitle ?? ""
        }
    }

    private(set) var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    private(set) var albums: [Album] = []
    private(set) var assets: PHFetchResult<PHAsset>?
    var albumID: String? {
        didSet { if albumID != oldValue { fetchAssets() } }
    }
    @ObservationIgnored private var collections: [String: PHAssetCollection] = [:]
    @ObservationIgnored private var observer: ChangeObserver?

    var title: String {
        albums.first { $0.id == albumID }?.title ?? ""
    }

    var hasAccess: Bool {
        status == .authorized || status == .limited
    }

    func load() async {
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard hasAccess else { return }
        if observer == nil {
            // Limited access: photos added via "Manage" arrive as a library change.
            observer = ChangeObserver { [weak self] in Task { await self?.reload() } }
        }
        await reload(refetch: false)
    }

    /// PhotoKit fetches block for long on a big library, so they run off the main thread:
    /// first the current album's photos, then the album list (which counts every album).
    private func reload(refetch: Bool = true) async {
        if albumID == nil, let recents = await ImportPhotoAssets.recents() {
            collections[recents.localIdentifier] = recents
            albums = [Album(recents)]
            albumID = recents.localIdentifier
        } else if refetch {
            fetchAssets()
        }
        let found = await ImportPhotoAssets.albums()
        collections = Dictionary(found.map { ($0.localIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        albums = found.map(Album.init)
        if albumID.flatMap({ collections[$0] }) == nil {
            albumID = albums.first?.id
        }
    }

    private func fetchAssets() {
        guard let id = albumID, let album = collections[id] else { return }
        Task {
            let fetched = await ImportPhotoAssets.images(in: album)
            if albumID == id { assets = fetched }
        }
    }

    static func manageLimitedAccess() {
        guard let top = UIApplication.topViewController() else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
    }

    private final class ChangeObserver: NSObject, PHPhotoLibraryChangeObserver {
        private let onChange: @MainActor () -> Void

        init(onChange: @escaping @MainActor () -> Void) {
            self.onChange = onChange
            super.init()
            PHPhotoLibrary.shared().register(self)
        }

        deinit {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }

        func photoLibraryDidChange(_ changeInstance: PHChange) {
            Task { @MainActor in onChange() }
        }
    }
}

enum ImportPhotoAssets {
    private static let imageManager = PHCachingImageManager()

    static func recents() async -> PHAssetCollection? {
        await Task.detached(priority: .userInitiated) {
            PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumUserLibrary, options: nil).firstObject
        }.value
    }

    /// Recents, Favorites, Screenshots, then the user's albums; empty ones skipped, except Recents.
    static func albums() async -> [PHAssetCollection] {
        await Task.detached(priority: .utility) {
            var found: [PHAssetCollection] = []
            for subtype in [PHAssetCollectionSubtype.smartAlbumUserLibrary, .smartAlbumFavorites, .smartAlbumScreenshots] {
                if let album = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil).firstObject {
                    found.append(album)
                }
            }
            PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
                .enumerateObjects { album, _, _ in found.append(album) }
            let imagesOnly = PHFetchOptions()
            imagesOnly.predicate = imagesPredicate
            return found.enumerated()
                .filter { $0.offset == 0 || PHAsset.fetchAssets(in: $0.element, options: imagesOnly).count > 0 }
                .map(\.element)
        }.value
    }

    static func images(in album: PHAssetCollection) async -> PHFetchResult<PHAsset> {
        await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.predicate = imagesPredicate
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            return PHAsset.fetchAssets(in: album, options: options)
        }.value
    }

    private static var imagesPredicate: NSPredicate {
        NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
    }

    /// A fast low-res image first, then the sharp one.
    static func thumbnails(for asset: PHAsset, scale: CGFloat) -> AsyncStream<UIImage> {
        AsyncStream { continuation in
            let request = imageManager.requestImage(
                for: asset,
                targetSize: thumbnailSize(scale),
                contentMode: .aspectFill,
                options: thumbnailOptions
            ) { image, info in
                if let image { continuation.yield(image) }
                let degraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
                if !degraded { continuation.finish() }
            }
            continuation.onTermination = { _ in imageManager.cancelImageRequest(request) }
        }
    }

    static func stopCachingThumbnails() {
        imageManager.stopCachingImagesForAllAssets()
    }

    /// The cache only serves requests with the same size and options.
    private static func thumbnailSize(_ scale: CGFloat) -> CGSize {
        CGSize(width: 160 * scale, height: 160 * scale)
    }

    private static var thumbnailOptions: PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return options
    }

    /// The original file with edits applied, downloaded from iCloud if needed, ready for
    /// `RecipeImportAPI.importImages`.
    static func importItem(for asset: PHAsset) async -> ImportPhotoItem? {
        let (data, uti): (Data?, String?) = await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.version = .current
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, _ in
                continuation.resume(returning: (data, uti))
            }
        }
        guard let data else { return nil }
        return await ImportPhotoEncoding.item(data: data, utType: uti.flatMap(UTType.init))
    }
}

/// Server-ready photos: formats the import accepts go as they are, the rest (and oversize
/// files) are re-encoded as JPEG.
enum ImportPhotoEncoding {
    static func item(data: Data, utType: UTType?) async -> ImportPhotoItem? {
        let type = utType ?? .jpeg
        let supported = ImportPhotoValidator.supportedUTTypes.contains { type.conforms(to: $0) }
        if supported, data.count <= ImportPhotoValidator.maxImageBytes {
            return ImportPhotoItem(data: data, fileName: fileName(for: type), utType: type)
        }
        let jpeg = await Task.detached(priority: .userInitiated) {
            UIImage(data: data)?.jpegData(compressionQuality: 0.85)
        }.value
        guard let jpeg else { return nil }
        return ImportPhotoItem(data: jpeg, fileName: fileName(for: .jpeg), utType: .jpeg)
    }

    static func fileName(for utType: UTType) -> String {
        if utType.conforms(to: .png) { return "image.png" }
        if utType.conforms(to: .webP) { return "image.webp" }
        if utType.conforms(to: .heic) { return "image.heic" }
        return "image.jpg"
    }
}

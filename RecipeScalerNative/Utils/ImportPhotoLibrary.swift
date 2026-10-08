//
//  ImportPhotoLibrary.swift
//  RecipeScalerNative
//
//  Spec 080 — albums and photos for the Photo tab grid of `ImportRecipeSheet`.
//  Ported from scrapp's `AddSheet` (PhotoLibrary / PhotoAssets).
//

import ImageIO
import Photos
import PhotosUI
import RecipeScalerCore
import SwiftUI
import UniformTypeIdentifiers

/// Albums and their photos, newest first. Needs Photos access, unlike the system picker.
@MainActor
@Observable
final class ImportPhotoLibrary {
    struct Album: Identifiable, Equatable {
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
    /// Only the newest fetch may land: an older one finishing last would bring back a stale album.
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

    var title: String {
        albums.first { $0.id == albumID }?.title ?? ""
    }

    var hasAccess: Bool {
        status == .authorized || status == .limited
    }

    func load() async {
        let previous = status
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard hasAccess else { return }
        if observer == nil {
            // Limited access: photos added via "Manage" arrive as a library change.
            observer = ChangeObserver { [weak self] change in self?.libraryDidChange(change) }
        }
        // Re-entering the tab keeps the album; the observer has kept it current.
        await reload(refetch: status != previous)
    }

    /// Access can change in Settings while the sheet is open; the grid follows on return.
    /// Skipped while the first request is still on screen: `load()` is handling it.
    func refreshAccess() async {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status != .notDetermined, current != status else { return }
        await load()
    }

    /// iCloud sync and new screenshots fire this often: the open album is patched from the
    /// change itself, and the album list (which counts every album) is rebuilt once things settle.
    private func libraryDidChange(_ change: PHChange) {
        if fetchTask != nil {
            // A fetch still in flight may predate the change.
            fetchAssets()
        } else if let assets, let details = change.changeDetails(for: assets) {
            self.assets = details.fetchResultAfterChanges
        }
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await reloadAlbums()
        }
    }

    /// PhotoKit fetches block for long on a big library, so they run off the main thread:
    /// first the current album's photos, then the album list.
    private func reload(refetch: Bool) async {
        if albumID == nil, let recents = await ImportPhotoAssets.recents() {
            guard !Task.isCancelled else { return }
            collections[recents.localIdentifier] = recents
            albums = [Album(recents)]
            albumID = recents.localIdentifier
        } else if refetch {
            fetchAssets()
        }
        await reloadAlbums()
    }

    private func reloadAlbums() async {
        let found = await ImportPhotoAssets.albums()
        guard !Task.isCancelled else { return }
        collections = Dictionary(found.map { ($0.localIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        // Same list: leave `albums` alone so the header menu isn't rebuilt.
        let updated = found.map(Album.init)
        if updated != albums { albums = updated }
        if albumID.flatMap({ collections[$0] }) == nil {
            albumID = albums.first?.id
        }
    }

    private func fetchAssets() {
        fetchTask?.cancel()
        fetchTask = nil
        guard let id = albumID, let album = collections[id] else { return }
        fetchTask = Task {
            let fetched = await ImportPhotoAssets.images(in: album)
            guard !Task.isCancelled else { return }
            assets = fetched
            fetchTask = nil
        }
    }

    static func manageLimitedAccess() {
        guard let top = UIApplication.topViewController() else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
    }

    private final class ChangeObserver: NSObject, PHPhotoLibraryChangeObserver {
        private let onChange: @MainActor (PHChange) -> Void

        init(onChange: @escaping @MainActor (PHChange) -> Void) {
            self.onChange = onChange
            super.init()
            PHPhotoLibrary.shared().register(self)
        }

        deinit {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }

        func photoLibraryDidChange(_ changeInstance: PHChange) {
            Task { @MainActor in onChange(changeInstance) }
        }
    }
}

enum ImportPhotoAssets {
    private static let imageManager = PHImageManager.default()

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
    /// `RecipeImportAPI.importImages`. Cancelling the task stops the download.
    static func importItem(for asset: PHAsset) async throws -> ImportPhotoItem {
        let request = OriginalRequest()
        let (data, uti) = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                request.start(for: asset, continuation: continuation)
            }
        } onCancel: {
            request.cancel()
        }
        guard let item = await ImportPhotoEncoding.item(data: data, utType: uti.flatMap(UTType.init)) else {
            throw ImportPhotoLoadError.unreadable
        }
        return item
    }

    /// One original-data request. Whichever comes first, the result or a cancel, resumes the caller.
    private final class OriginalRequest: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<(Data, String?), Error>?
        private var requestID: PHImageRequestID?
        private var isCancelled = false

        func start(for asset: PHAsset, continuation: CheckedContinuation<(Data, String?), Error>) {
            lock.lock()
            guard !isCancelled else {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            self.continuation = continuation
            lock.unlock()

            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.version = .current
            options.isNetworkAccessAllowed = true
            let id = PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, info in
                if let data {
                    self.finish(.success((data, uti)))
                } else if info?[PHImageCancelledKey] as? Bool == true {
                    self.finish(.failure(CancellationError()))
                } else if info?[PHImageErrorKey] != nil || info?[PHImageResultIsInCloudKey] as? Bool == true {
                    self.finish(.failure(ImportPhotoLoadError.download))
                } else {
                    self.finish(.failure(ImportPhotoLoadError.unreadable))
                }
            }

            lock.lock()
            requestID = id
            let cancelNow = isCancelled
            lock.unlock()
            if cancelNow { PHImageManager.default().cancelImageRequest(id) }
        }

        func cancel() {
            lock.lock()
            isCancelled = true
            let id = requestID
            lock.unlock()
            if let id { PHImageManager.default().cancelImageRequest(id) }
            finish(.failure(CancellationError()))
        }

        private func finish(_ result: Result<(Data, String?), Error>) {
            lock.lock()
            let continuation = continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(with: result)
        }
    }
}

/// Why a library photo couldn't be read for import. `errorDescription` is the string key,
/// as with `ImportPhotoValidator.ValidationError`.
enum ImportPhotoLoadError: LocalizedError {
    /// The original is in iCloud and didn't download.
    case download
    /// Photos gave back something that isn't an image.
    case unreadable

    var errorDescription: String? {
        switch self {
        case .download: "import.error-photo-download"
        case .unreadable: "import.error-photo-corrupt"
        }
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
            jpegWithinLimit(data)
        }.value
        guard let jpeg else { return nil }
        return ImportPhotoItem(data: jpeg, fileName: fileName(for: .jpeg), utType: .jpeg)
    }

    /// JPEG at the import's quality, scaled down while still over the size limit (huge panoramas).
    static func jpegWithinLimit(_ data: Data, limit: Int = ImportPhotoValidator.maxImageBytes) -> Data? {
        guard var image = UIImage(data: data), var jpeg = image.jpegData(compressionQuality: 0.85) else { return nil }
        while jpeg.count > limit {
            let factor = (Double(limit) / Double(jpeg.count)).squareRoot() * 0.9
            let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
            guard let smaller = image.preparingThumbnail(of: size),
                  let next = smaller.jpegData(compressionQuality: 0.85) else { return nil }
            image = smaller
            jpeg = next
        }
        return jpeg
    }

    /// A thumbnail whose short side is `minPixelSide`, decoded at that size by ImageIO —
    /// a camera shot is 12–48 MP, and `UIImage(data:)` would decode all of it.
    static func thumbnail(of data: Data, minPixelSide: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        var maxPixelSide = minPixelSide
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int,
           min(width, height) > 0 {
            // ImageIO bounds the long side; capped so a panorama stays a thumbnail.
            let aspect = min(CGFloat(max(width, height)) / CGFloat(min(width, height)), 4)
            maxPixelSide = minPixelSide * aspect
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSide,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    static func fileName(for utType: UTType) -> String {
        if utType.conforms(to: .png) { return "image.png" }
        if utType.conforms(to: .webP) { return "image.webp" }
        if utType.conforms(to: .heic) { return "image.heic" }
        return "image.jpg"
    }
}

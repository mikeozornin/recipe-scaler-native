#if !os(watchOS)
import Foundation

/// Chooses image bytes from native export ZIP entries for upload.
public enum NativeImportImagePicker {

    public enum Selection: Sendable, Equatable {
        case none
        case ready(Data)
        case tooLarge
    }

    /// Prefer `full`, fall back to `preview`. Returns `.tooLarge` when over `maxBytes`.
    public static func selection(
        from entries: [NativeRecipeImporter.ImageEntry],
        maxBytes: Int = ThirdPartyImportLimits.maxImageBytes
    ) -> Selection {
        let full = entries.first { $0.kind == .full }?.data
        let preview = entries.first { $0.kind == .preview }?.data
        guard let data = full ?? preview else { return .none }
        if data.count > maxBytes { return .tooLarge }
        return .ready(data)
    }
}
#endif

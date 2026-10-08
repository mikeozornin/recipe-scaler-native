//
//  ImportPhotoGridSection.swift
//  RecipeScalerNative
//
//  Spec 080 — Photo tab of `ImportRecipeSheet`, laid out like Telegram's attach sheet
//  (ported from scrapp's `AddSheet`): an album menu, a live camera cell first, then the
//  album's photos with numbered multi-select. Rows are Form rows, so the grid stays lazy.
//

import Photos
import PhotosUI
import RecipeScalerCore
import SwiftUI

/// One picked photo, in pick order: from the library, or shot / picked outside it.
enum ImportPhotoPick: Identifiable, Equatable {
    case asset(PHAsset)
    case item(ImportPhotoItem)

    var id: String {
        switch self {
        case let .asset(asset): "asset:\(asset.localIdentifier)"
        case let .item(item): "item:\(item.id.uuidString)"
        }
    }

    static func == (lhs: ImportPhotoPick, rhs: ImportPhotoPick) -> Bool {
        lhs.id == rhs.id
    }
}

struct ImportPhotoGridSection: View {
    @Bindable var library: ImportPhotoLibrary
    @Binding var selection: [ImportPhotoPick]
    /// Shots from the camera and photos from the system picker, newest first, shown after the camera cell.
    @Binding var extras: [ImportPhotoItem]
    let isDisabled: Bool

    @State private var camera: ImportCameraPreview?
    @State private var capture = ImportCameraCapture()
    @State private var systemPickerItems: [PhotosPickerItem] = []

    private static let columns = 3
    private static let spacing: CGFloat = 2
    private static let maxCount = ImportPhotoValidator.maxImages

    var body: some View {
        Section {
            if library.status == .limited {
                limitedAccessRow
            }
            if library.status == .denied || library.status == .restricted {
                noAccessRow
            }
            ForEach(0..<rowCount, id: \.self) { row in
                gridRow(row)
                    .listRowInsets(EdgeInsets(
                        top: 0,
                        leading: 0,
                        bottom: row == rowCount - 1 ? 0 : Self.spacing,
                        trailing: 0
                    ))
                    .listRowSeparator(.hidden)
            }
        } header: {
            header
        } footer: {
            Text("import.photo-helper")
                .appFootnote()
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            albumMenu
            Spacer(minLength: 8)
            Text(verbatim: "\(selection.count) / \(Self.maxCount)")
                .font(AppTypography.monoFootnoteDigits)
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text(countLabel))
        }
        .textCase(nil)
    }

    /// Always the same menu, so the header doesn't jump when the album list arrives;
    /// with one album the chevron is hidden and the menu doesn't open.
    private var albumMenu: some View {
        let hasChoice = library.albums.count > 1
        return Menu {
            Picker(selection: $library.albumID) {
                ForEach(library.albums) { album in
                    Text(verbatim: album.title).tag(Optional(album.id))
                }
            } label: {
                Text("import.photos.album")
            }
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: library.title)
                    .font(AppTypography.footnoteSemibold)
                    .foregroundStyle(.primary)
                AppSymbol.sizedImage("chevron.down", pointSize: 11, weight: .semibold)
                    .foregroundStyle(.primary)
                    .opacity(hasChoice ? 1 : 0)
            }
        }
        // A header menu takes the accent tint; the album name stays in the text color.
        .tint(.primary)
        .allowsHitTesting(hasChoice && !isDisabled)
    }

    private var countLabel: String {
        String(
            format: Bundle.currentLocalizedString("import.photo-count"),
            locale: AppLanguagePreference.current.locale,
            selection.count,
            Self.maxCount
        )
    }

    // MARK: - Access rows

    private var limitedAccessRow: some View {
        HStack {
            Text("import.photos.limited")
                .appFootnote()
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button {
                ImportPhotoLibrary.manageLimitedAccess()
            } label: {
                Text("import.photos.limited-manage")
                    .font(AppTypography.footnoteSemibold)
            }
            .buttonStyle(.borderless)
        }
    }

    private var noAccessRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("import.photos.no-access")
                .appFootnote()
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("import.photos.open-settings")
                        .font(AppTypography.footnoteSemibold)
                }
                .buttonStyle(.borderless)
                PhotosPicker(
                    selection: $systemPickerItems,
                    maxSelectionCount: max(1, Self.maxCount - selection.count),
                    matching: .images
                ) {
                    Text("import.choose-photos")
                        .font(AppTypography.footnoteSemibold)
                }
                .buttonStyle(.borderless)
                .disabled(isDisabled || selection.count >= Self.maxCount)
                .onChange(of: systemPickerItems) { _, items in
                    guard !items.isEmpty else { return }
                    systemPickerItems = []
                    Task { await addSystemPicks(items) }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Grid

    private var assetCount: Int {
        library.hasAccess ? library.assets?.count ?? 0 : 0
    }

    /// The camera, then the extras, then the album.
    private var cellCount: Int {
        1 + extras.count + assetCount
    }

    private var rowCount: Int {
        (cellCount + Self.columns - 1) / Self.columns
    }

    private var isFull: Bool {
        selection.count >= Self.maxCount
    }

    private func gridRow(_ row: Int) -> some View {
        HStack(spacing: Self.spacing) {
            ForEach(0..<Self.columns, id: \.self) { column in
                let index = row * Self.columns + column
                if index < cellCount {
                    cell(at: index)
                } else {
                    Color.clear.aspectRatio(1, contentMode: .fit)
                }
            }
        }
    }

    @ViewBuilder
    private func cell(at index: Int) -> some View {
        if index == 0 {
            ImportCameraCell(camera: camera, isDisabled: isDisabled || isFull, action: openCamera)
                .onAppear {
                    if camera == nil { camera = ImportCameraPreview() }
                    camera?.start()
                }
                .onDisappear { camera?.stop() }
        } else if index <= extras.count {
            let item = extras[index - 1]
            pickCell(.item(item), label: Text("import.photos.photo")) {
                ImportExtraPhotoThumbnail(item: item)
            }
        } else if let assets = library.assets {
            let asset = assets.object(at: index - 1 - extras.count)
            pickCell(.asset(asset), label: assetLabel(asset)) {
                ImportAssetThumbnail(asset: asset)
            }
        }
    }

    private func pickCell<Thumbnail: View>(
        _ pick: ImportPhotoPick,
        label: Text,
        @ViewBuilder thumbnail: () -> Thumbnail
    ) -> some View {
        let number = selection.firstIndex(of: pick).map { $0 + 1 }
        let isBlocked = number == nil && isFull
        return Button {
            toggle(pick)
        } label: {
            Color(.secondarySystemBackground)
                .aspectRatio(1, contentMode: .fit)
                .overlay { thumbnail() }
                .clipped()
                .overlay(alignment: .topTrailing) {
                    ImportSelectionBadge(number: number).padding(6)
                }
                .opacity(isBlocked ? 0.45 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isBlocked)
        .accessibilityLabel(label)
        // The badge number is the upload order; VoiceOver hears it, not just "selected".
        .accessibilityValue(number.map { Text(verbatim: localized("import.photos.pick-order", $0)) } ?? Text(verbatim: ""))
        .accessibilityAddTraits(number != nil ? .isSelected : [])
    }

    /// Cells told apart by date, as in Photos.
    private func assetLabel(_ asset: PHAsset) -> Text {
        guard let date = asset.creationDate else { return Text("import.photos.photo") }
        let locale = AppLanguagePreference.current.locale
        let dated = date.formatted(Date.FormatStyle(date: .long, time: .shortened, locale: locale))
        return Text(verbatim: localized("import.photos.photo-dated", dated))
    }

    private func localized(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: Bundle.currentLocalizedString(key),
            locale: AppLanguagePreference.current.locale,
            arguments: arguments
        )
    }

    private func toggle(_ pick: ImportPhotoPick) {
        withAnimation(.snappy(duration: 0.2)) {
            if let index = selection.firstIndex(of: pick) {
                selection.remove(at: index)
            } else if !isFull {
                selection.append(pick)
            }
        }
    }

    /// The camera opens over the sheet and needs the device to itself; the shot comes back picked.
    /// It goes through the same encoding as library photos, so an oversize shot can't fail at submit.
    private func openCamera() {
        camera?.stop()
        capture.present(onCancel: { camera?.start() }) { data in
            Task {
                if let item = await ImportPhotoEncoding.item(data: data, utType: .jpeg) {
                    withAnimation(.snappy(duration: 0.2)) {
                        extras.insert(item, at: 0)
                        if !isFull { selection.append(.item(item)) }
                    }
                }
                camera?.start()
            }
        }
    }

    @MainActor
    private func addSystemPicks(_ items: [PhotosPickerItem]) async {
        for pickerItem in items {
            guard selection.count < Self.maxCount,
                  let data = try? await pickerItem.loadTransferable(type: Data.self),
                  let item = await ImportPhotoEncoding.item(data: data, utType: pickerItem.supportedContentTypes.first)
            else { continue }
            extras.insert(item, at: 0)
            selection.append(.item(item))
        }
    }
}

// MARK: - Cells

private struct ImportCameraCell: View {
    let camera: ImportCameraPreview?
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        let isLive = camera?.isLive ?? false
        Button(action: action) {
            Color(.secondarySystemBackground)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    // Always in the tree, so the layer is ready before the feed fades in.
                    if let camera {
                        ImportCameraPreviewView(preview: camera.previewView)
                            .opacity(isLive ? 1 : 0)
                    }
                }
                .overlay {
                    // Stays put when the feed starts; only the color follows the background.
                    AppSymbol.sizedImage("camera", pointSize: 26, weight: .medium)
                        .foregroundStyle(isLive ? Color.white : Color.primary)
                        .shadow(color: .black.opacity(isLive ? 0.4 : 0), radius: 3)
                }
                .clipped()
                .opacity(isDisabled ? 0.45 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(Text("import.photos.camera"))
        .accessibilityIdentifier(AccessibilityIdentifiers.importPhotoCamera)
    }
}

private struct ImportAssetThumbnail: View {
    let asset: PHAsset
    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .task(id: asset.localIdentifier) {
                image = nil
                for await thumbnail in ImportPhotoAssets.thumbnails(for: asset, scale: displayScale) {
                    image = thumbnail
                }
            }
    }
}

private struct ImportExtraPhotoThumbnail: View {
    /// Decoded once per shot: the cell reappears on every scroll.
    private static let cache = NSCache<NSString, UIImage>()

    let item: ImportPhotoItem
    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .task(id: item.id) {
                let key = item.id.uuidString as NSString
                if let cached = Self.cache.object(forKey: key) {
                    image = cached
                    return
                }
                let data = item.data
                let side = 160 * displayScale
                let thumbnail = await Task.detached(priority: .userInitiated) {
                    ImportPhotoEncoding.thumbnail(of: data, minPixelSide: side)
                }.value
                if let thumbnail { Self.cache.setObject(thumbnail, forKey: key) }
                image = thumbnail
            }
    }
}

/// Telegram-style: an empty ring, or a filled circle with the pick order.
private struct ImportSelectionBadge: View {
    let number: Int?

    var body: some View {
        ZStack {
            if let number {
                Circle().fill(Color.primary)
                Text(verbatim: "\(number)")
                    .font(AppTypography.footnoteSemibold.monospacedDigit())
                    .foregroundStyle(Color(.systemBackground))
            } else {
                Circle().fill(.black.opacity(0.12))
            }
            Circle().strokeBorder(.white, lineWidth: 1.5)
        }
        .frame(width: 24, height: 24)
        .shadow(color: .black.opacity(0.25), radius: 2)
        .allowsHitTesting(false)
    }
}

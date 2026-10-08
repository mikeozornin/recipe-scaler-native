import RecipeScalerCore
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import RecipeScalerNative

/// Spec 080 — photos from the import grid reach the server in a format it accepts.
final class ImportPhotoEncodingTests: XCTestCase {
    private func image(_ size: CGSize = CGSize(width: 8, height: 8)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    func testSupportedFormatPassesThroughUnchanged() async throws {
        let png = try XCTUnwrap(image().pngData())
        let encoded = await ImportPhotoEncoding.item(data: png, utType: .png)
        let item = try XCTUnwrap(encoded)
        XCTAssertEqual(item.data, png)
        XCTAssertEqual(item.utType, .png)
        XCTAssertEqual(item.fileName, "image.png")
    }

    func testUnsupportedFormatIsReencodedAsJPEG() async throws {
        // Real PNG bytes labelled as TIFF: the server doesn't take TIFF, so it must go as JPEG.
        let data = try XCTUnwrap(image().pngData())
        let encoded = await ImportPhotoEncoding.item(data: data, utType: .tiff)
        let item = try XCTUnwrap(encoded)
        XCTAssertEqual(item.utType, .jpeg)
        XCTAssertEqual(item.fileName, "image.jpg")
        XCTAssertEqual(Array(item.data.prefix(2)), [0xFF, 0xD8], "JPEG SOI marker")
    }

    func testUndecodableUnsupportedDataIsDropped() async {
        let item = await ImportPhotoEncoding.item(data: Data([0x00, 0x01, 0x02]), utType: .gif)
        XCTAssertNil(item)
    }

    func testOversizeImageIsScaledDownUnderTheLimit() throws {
        // Noise doesn't compress, so the first JPEG is well over the limit.
        let size = CGSize(width: 400, height: 400)
        let noise = UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()).image { context in
            for x in stride(from: 0, to: 400, by: 2) {
                for y in stride(from: 0, to: 400, by: 2) {
                    UIColor(hue: .random(in: 0...1), saturation: 1, brightness: .random(in: 0...1), alpha: 1).setFill()
                    context.fill(CGRect(x: x, y: y, width: 2, height: 2))
                }
            }
        }
        let data = try XCTUnwrap(noise.pngData())
        let limit = 20_000
        XCTAssertGreaterThan(try XCTUnwrap(noise.jpegData(compressionQuality: 0.85)).count, limit)
        let jpeg = try XCTUnwrap(ImportPhotoEncoding.jpegWithinLimit(data, limit: limit))
        XCTAssertLessThanOrEqual(jpeg.count, limit)
        XCTAssertEqual(Array(jpeg.prefix(2)), [0xFF, 0xD8], "JPEG SOI marker")
    }

    func testLoadErrorsHaveTheirOwnMessages() {
        let download = ImportErrorLocalizer.localize(ImportPhotoLoadError.download)
        let unreadable = ImportErrorLocalizer.localize(ImportPhotoLoadError.unreadable)
        XCTAssertFalse(download.hasPrefix("import."), "resolved, not the raw key")
        XCTAssertFalse(unreadable.hasPrefix("import."), "resolved, not the raw key")
        XCTAssertNotEqual(download, unreadable, "a failed iCloud download isn't reported as a corrupt photo")
    }

    func testFileNameFollowsType() {
        XCTAssertEqual(ImportPhotoEncoding.fileName(for: .jpeg), "image.jpg")
        XCTAssertEqual(ImportPhotoEncoding.fileName(for: .png), "image.png")
        XCTAssertEqual(ImportPhotoEncoding.fileName(for: .webP), "image.webp")
        XCTAssertEqual(ImportPhotoEncoding.fileName(for: .heic), "image.heic")
    }

    func testPickEqualityFollowsTheItem() {
        let item = ImportPhotoItem(data: Data([1]), fileName: "image.jpg", utType: .jpeg)
        let other = ImportPhotoItem(data: Data([1]), fileName: "image.jpg", utType: .jpeg)
        XCTAssertEqual(ImportPhotoPick.item(item), ImportPhotoPick.item(item))
        XCTAssertNotEqual(ImportPhotoPick.item(item), ImportPhotoPick.item(other))
    }
}

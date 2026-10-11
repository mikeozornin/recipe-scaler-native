// Pixel helper for scripts/verify-ipad-layout.sh (spec 081).
//
// The script compiles this file once with `swiftc -O` into tmp/ipad-verify/.tools/
// (keyed by the source hash). Only CoreGraphics + ImageIO — no Homebrew deps.
//
// Commands:
//   diff <a.png> <b.png> [mask.png|-] [diff-out.png|-]
//       Compares two screenshots pixel by pixel. Pixels where mask.png is white
//       are ignored (unstable regions recorded with the baseline).
//       Prints: differing=<n> masked=<m> total=<t> size=<w>x<h>
//       Size mismatch prints `size-mismatch a=<w>x<h> b=<w>x<h>` and exits 2.
//       With diff-out.png, writes a dimmed copy of <b> with differing pixels in red.
//   mask <out.png> <radius> <reference.png> <other.png>...
//       White wherever any <other> frame differs from <reference>, dilated by
//       <radius> pixels. With IPAD_VERIFY_MASK_BOXES=1 (the script's default) each
//       connected unstable region is then filled to its bounding box, repeatedly,
//       until boxes stop growing: a random placeholder line or a glass shimmer halo
//       becomes one rectangle instead of the glyphs / sparkles that happened to be
//       sampled. Prints: masked=<n> total=<t> size=<w>x<h>
//   size <a.png>
//       Prints: <w> <h>
//
// Env: IPAD_VERIFY_CHANNEL_TOLERANCE (default 0) — max per-channel delta that
// still counts as "equal".
//
// Exit codes: 0 ok, 1 usage / IO error, 2 size mismatch.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Bitmap {
    let width: Int
    let height: Int
    var rgba: [UInt8]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("ipad-verify-pixels: \(message)\n".utf8))
    exit(1)
}

func load(_ path: String) -> Bitmap {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { fail("cannot read image \(path)") }
    let width = image.width
    let height = image.height
    var rgba = [UInt8](repeating: 0, count: width * height * 4)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { fail("no sRGB color space") }
    let drawn: Bool = rgba.withUnsafeMutableBytes { buffer in
        guard let context = CGContext(
            data: buffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    if !drawn { fail("cannot decode image \(path)") }
    return Bitmap(width: width, height: height, rgba: rgba)
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { fail("cannot create \(path)") }
    CGImageDestinationAddImage(destination, image, nil)
    if !CGImageDestinationFinalize(destination) { fail("cannot write \(path)") }
}

func writeGray(_ values: [UInt8], width: Int, height: Int, to path: String) {
    var copy = values
    let image: CGImage? = copy.withUnsafeMutableBytes { buffer in
        CGContext(
            data: buffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )?.makeImage()
    }
    guard let image else { fail("cannot encode mask \(path)") }
    writePNG(image, to: path)
}

func writeRGBA(_ bitmap: Bitmap, to path: String) {
    var copy = bitmap.rgba
    guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { fail("no sRGB color space") }
    let image: CGImage? = copy.withUnsafeMutableBytes { buffer in
        CGContext(
            data: buffer.baseAddress,
            width: bitmap.width,
            height: bitmap.height,
            bitsPerComponent: 8,
            bytesPerRow: bitmap.width * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage()
    }
    guard let image else { fail("cannot encode image \(path)") }
    writePNG(image, to: path)
}

let tolerance: Int = {
    guard let raw = ProcessInfo.processInfo.environment["IPAD_VERIFY_CHANNEL_TOLERANCE"],
          let value = Int(raw), value >= 0
    else { return 0 }
    return value
}()

@inline(__always)
func pixelDiffers(_ a: [UInt8], _ b: [UInt8], _ offset: Int) -> Bool {
    for channel in 0..<4 {
        let delta = Int(a[offset + channel]) - Int(b[offset + channel])
        if abs(delta) > tolerance { return true }
    }
    return false
}

/// Square dilation with a separable running window (O(width * height)).
func dilate(_ input: [UInt8], width: Int, height: Int, radius: Int) -> [UInt8] {
    guard radius > 0 else { return input }
    var horizontal = [UInt8](repeating: 0, count: input.count)
    var prefix = [Int](repeating: 0, count: max(width, height) + 1)
    for y in 0..<height {
        let row = y * width
        for x in 0..<width {
            prefix[x + 1] = prefix[x] + (input[row + x] != 0 ? 1 : 0)
        }
        for x in 0..<width {
            let lo = max(0, x - radius)
            let hi = min(width - 1, x + radius)
            if prefix[hi + 1] - prefix[lo] > 0 { horizontal[row + x] = 255 }
        }
    }
    var output = [UInt8](repeating: 0, count: input.count)
    for x in 0..<width {
        for y in 0..<height {
            prefix[y + 1] = prefix[y] + (horizontal[y * width + x] != 0 ? 1 : 0)
        }
        for y in 0..<height {
            let lo = max(0, y - radius)
            let hi = min(height - 1, y + radius)
            if prefix[hi + 1] - prefix[lo] > 0 { output[y * width + x] = 255 }
        }
    }
    return output
}

/// Fills every 4-connected region of `mask` to its bounding box until stable
/// (overlapping boxes join and are boxed again on the next round).
func fillBoxes(_ mask: inout [UInt8], width: Int, height: Int) {
    var changed = true
    while changed {
        changed = false
        var visited = [Bool](repeating: false, count: mask.count)
        var boxes: [(minX: Int, minY: Int, maxX: Int, maxY: Int)] = []
        var stack: [Int] = []
        for start in 0..<mask.count where mask[start] != 0 && !visited[start] {
            var box = (minX: width, minY: height, maxX: 0, maxY: 0)
            visited[start] = true
            stack.append(start)
            while let index = stack.popLast() {
                let x = index % width
                let y = index / width
                box.minX = min(box.minX, x)
                box.maxX = max(box.maxX, x)
                box.minY = min(box.minY, y)
                box.maxY = max(box.maxY, y)
                let neighbours = [
                    x > 0 ? index - 1 : -1,
                    x < width - 1 ? index + 1 : -1,
                    y > 0 ? index - width : -1,
                    y < height - 1 ? index + width : -1,
                ]
                for next in neighbours where next >= 0 && mask[next] != 0 && !visited[next] {
                    visited[next] = true
                    stack.append(next)
                }
            }
            boxes.append(box)
        }
        for box in boxes {
            for y in box.minY...box.maxY {
                let row = y * width
                for x in box.minX...box.maxX where mask[row + x] == 0 {
                    mask[row + x] = 255
                    changed = true
                }
            }
        }
    }
}

func loadMask(_ path: String, width: Int, height: Int) -> [UInt8] {
    let bitmap = load(path)
    guard bitmap.width == width, bitmap.height == height else {
        fail("mask \(path) is \(bitmap.width)x\(bitmap.height), expected \(width)x\(height)")
    }
    var mask = [UInt8](repeating: 0, count: width * height)
    for index in 0..<(width * height) where bitmap.rgba[index * 4] > 127 {
        mask[index] = 255
    }
    return mask
}

func runDiff(_ args: [String]) {
    guard args.count >= 2 else { fail("usage: diff <a.png> <b.png> [mask.png|-] [diff-out.png|-]") }
    let a = load(args[0])
    let b = load(args[1])
    guard a.width == b.width, a.height == b.height else {
        print("size-mismatch a=\(a.width)x\(a.height) b=\(b.width)x\(b.height)")
        exit(2)
    }
    let total = a.width * a.height
    let maskPath = args.count >= 3 && args[2] != "-" ? args[2] : nil
    let mask = maskPath.map { loadMask($0, width: a.width, height: a.height) }
    let diffOut = args.count >= 4 && args[3] != "-" ? args[3] : nil
    var differing = 0
    var masked = 0
    var visual = diffOut != nil ? b : nil
    for index in 0..<total {
        let offset = index * 4
        if let mask, mask[index] != 0 {
            masked += 1
            continue
        }
        if pixelDiffers(a.rgba, b.rgba, offset) {
            differing += 1
            if visual != nil {
                visual!.rgba[offset] = 255
                visual!.rgba[offset + 1] = 0
                visual!.rgba[offset + 2] = 0
                visual!.rgba[offset + 3] = 255
            }
        } else if visual != nil {
            for channel in 0..<3 { visual!.rgba[offset + channel] /= 3 }
        }
    }
    if let diffOut, let visual { writeRGBA(visual, to: diffOut) }
    print("differing=\(differing) masked=\(masked) total=\(total) size=\(a.width)x\(a.height)")
}

func runMask(_ args: [String]) {
    guard args.count >= 3, let radius = Int(args[1]), radius >= 0 else {
        fail("usage: mask <out.png> <radius> <reference.png> <other.png>...")
    }
    let reference = load(args[2])
    let total = reference.width * reference.height
    var raw = [UInt8](repeating: 0, count: total)
    for path in args.dropFirst(3) {
        let other = load(path)
        guard other.width == reference.width, other.height == reference.height else {
            print("size-mismatch a=\(reference.width)x\(reference.height) b=\(other.width)x\(other.height)")
            exit(2)
        }
        for index in 0..<total where raw[index] == 0 && pixelDiffers(reference.rgba, other.rgba, index * 4) {
            raw[index] = 255
        }
    }
    var mask = dilate(raw, width: reference.width, height: reference.height, radius: radius)
    if ProcessInfo.processInfo.environment["IPAD_VERIFY_MASK_BOXES"] == "1" {
        fillBoxes(&mask, width: reference.width, height: reference.height)
    }
    let masked = mask.reduce(0) { $0 + ($1 != 0 ? 1 : 0) }
    writeGray(mask, width: reference.width, height: reference.height, to: args[0])
    print("masked=\(masked) total=\(total) size=\(reference.width)x\(reference.height)")
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { fail("usage: diff | mask | size") }
let rest = Array(arguments.dropFirst())
switch command {
case "diff":
    runDiff(rest)
case "mask":
    runMask(rest)
case "size":
    guard let path = rest.first else { fail("usage: size <a.png>") }
    let bitmap = load(path)
    print("\(bitmap.width) \(bitmap.height)")
default:
    fail("unknown command \(command)")
}

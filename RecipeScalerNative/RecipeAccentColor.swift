import SwiftUI
import UIKit

/// Maps recipe accent strings (oklch / hex) to SwiftUI `Color` and back for `ColorPicker`.
enum RecipeAccentColor {
    private static let defaultStored = "oklch(0.65 0.25 270)"

    private static let knownOklch: [String: (r: Double, g: Double, b: Double)] = [
        "oklch(0.65 0.25 270)": (0.45, 0.35, 0.95),
        "oklch(0.70 0.20 145)": (0.25, 0.75, 0.45),
        "oklch(0.75 0.18 50)": (0.95, 0.72, 0.25),
        "oklch(0.68 0.22 25)": (0.95, 0.42, 0.28),
        "oklch(0.62 0.20 320)": (0.82, 0.35, 0.88),
    ]

    static func uiColor(from stored: String) -> UIColor {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return uiColor(from: defaultStored) }
        if let rgb = knownOklch[trimmed] {
            return UIColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
        }
        if trimmed.hasPrefix("#"), let parsed = UIColor(hex: trimmed) {
            return parsed
        }
        return UIColor(red: 0.45, green: 0.35, blue: 0.95, alpha: 1)
    }

    static func color(from stored: String) -> Color {
        Color(uiColor(from: stored))
    }

    /// User folders use their accent; virtual collections use the default label color.
    static func folderIconColor(folderId: String, folder: RecipeFolder?) -> Color {
        guard let stored = RecipeFolderConstants.presentationStoredColor(folderId: folderId, folder: folder) else {
            return .primary
        }
        return color(from: stored)
    }

    /// Safe sRGB hex for Y.Doc (ColorPicker colors may be non-RGB).
    static func storedValue(from color: Color) -> String {
        let ui = UIColor(color)
        if let rgb = ui.cgColor.converted(
            to: CGColorSpaceCreateDeviceRGB(),
            intent: .defaultIntent,
            options: nil
        )?.components, rgb.count >= 3 {
            let r = Int((rgb[0] * 255).rounded())
            let g = Int((rgb[1] * 255).rounded())
            let b = Int((rgb[2] * 255).rounded())
            return normalizedStored(String(format: "#%02X%02X%02X", r, g, b))
        }
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return normalizedStored(String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255)))
        }
        return normalizedStored(defaultStored)
    }

    static func normalizedStored(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return defaultStored }
        if trimmed.hasPrefix("#") { return trimmed.uppercased() }
        return trimmed
    }
}

private extension UIColor {
    convenience init?(hex: String) {
        var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
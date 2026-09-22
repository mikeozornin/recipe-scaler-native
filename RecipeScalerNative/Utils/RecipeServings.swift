import Foundation

/// Servings parsing aligned with web `@shared/utils/recipe-servings`.
enum RecipeServings {
    static func normalize(_ value: Double) -> Int? {
        guard value.isFinite, value > 0 else { return nil }
        return max(1, Int(clampingFinite: value.rounded()))
    }

    static func normalize(_ value: Int) -> Int? {
        guard value > 0 else { return nil }
        return value
    }

    static func normalize(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let parsed = Double(normalized), parsed.isFinite, parsed > 0 else { return nil }
        return max(1, Int(clampingFinite: parsed.rounded()))
    }

    /// Base servings from Y.Doc `servings` (int, float, or string). `nil` when missing/invalid.
    static func normalized(from map: YrsMap, txn: OpaquePointer) -> Int? {
        if map.isNullOrMissing(key: "servings", txn: txn) {
            return nil
        }
        if let intValue = map.int(key: "servings", txn: txn) {
            return normalize(intValue)
        }
        if let doubleValue = map.double(key: "servings", txn: txn) {
            return normalize(doubleValue)
        }
        if let stringValue = map.scalarString(key: "servings", txn: txn) {
            return normalize(stringValue)
        }
        return nil
    }

    static func baseServings(from map: YrsMap, txn: OpaquePointer) -> Int {
        normalized(from: map, txn: txn) ?? 1
    }

    /// Continuous servings = base × scale (web `getCurrentServings`). Not integer-rounded.
    static func currentServings(base: Int, scaleFactor: Double) -> Double {
        let normalizedBase = Double(max(1, base))
        let scale = scaleFactor.isFinite && scaleFactor > 0 ? scaleFactor : 1
        return normalizedBase * scale
    }

    /// Web `roundServingsForDisplay` — one decimal for UI label.
    static func roundForDisplay(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return (value * 10).rounded() / 10
    }

    static func formatDisplay(_ value: Double) -> String {
        let rounded = roundForDisplay(value)
        let nearest = rounded.rounded()
        if abs(rounded - nearest) < 0.001, abs(nearest) < Double(Int.max) {
            return String(Int(nearest))
        }
        return AppNumberFormat.string(rounded, maximumFractionDigits: 1)
    }

    /// Integer servings snap — only for legacy call sites; prefer `currentServings` + stepper.
    static func scaledServings(base: Int, scaleFactor: Double) -> Int {
        let current = currentServings(base: base, scaleFactor: scaleFactor)
        return max(1, Int(clampingFinite: roundForDisplay(current).rounded()))
    }

    /// Next/previous whole serving (web increment/decrement: `Math.round(current) ± 1`).
    static func steppedServings(base: Int, scaleFactor: Double, delta: Int) -> Int {
        let roundedCurrent = roundForDisplay(currentServings(base: base, scaleFactor: scaleFactor))
        return max(1, min(99, Int(clampingFinite: roundedCurrent.rounded()) + delta))
    }
}

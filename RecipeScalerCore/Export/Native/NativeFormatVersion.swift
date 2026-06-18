import Foundation

/// Recipe Scaler export format version.
/// Mirrors `normalizeVersion` from the web `export-validator.ts`.
public enum NativeFormatVersion: String, Sendable, CaseIterable, Comparable {
    case v1_0 = "1.0"
    case v1_1 = "1.1"
    case v1_2 = "1.2"
    case v1_3 = "1.3"
    case v1_4 = "1.4"
    case v1_5 = "1.5"

    /// The `metadata.type` value for this version (where applicable).
    public var typeString: String? {
        switch self {
        case .v1_0: nil
        case .v1_1: nil
        case .v1_2: "recipes-v1.2"
        case .v1_3: "recipes-v1.3"
        case .v1_4: "recipes-v1.4"
        case .v1_5: "recipes-v1.5"
        }
    }

    /// Whether this version supports folders in the export.
    public var supportsFolders: Bool {
        self >= .v1_4
    }

    /// Whether this version supports servings.
    public var supportsServings: Bool {
        self >= .v1_3
    }

    /// Whether this version supports nutrition.
    public var supportsNutrition: Bool {
        self >= .v1_2
    }

    /// Whether this version supports the dedicated `amountText` field for
    /// non-numeric ingredient amounts (e.g. `"1/2"`, `"to taste"`).
    /// Introduced in v1.5 (finding #15). Older native exports lose such
    /// amounts on roundtrip; web v1.4 emits them as a string `originalAmount`
    /// and is parsed back via the polymorphic decoder on `NativeIngredient`.
    public var supportsAmountText: Bool {
        self >= .v1_5
    }

    public static func < (lhs: NativeFormatVersion, rhs: NativeFormatVersion) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    private var sortOrder: Int {
        switch self {
        case .v1_0: 0
        case .v1_1: 1
        case .v1_2: 2
        case .v1_3: 3
        case .v1_4: 4
        case .v1_5: 5
        }
    }
}

/// Normalize a raw version string (or absence) into a concrete `NativeFormatVersion`.
/// Mirrors the web `normalizeVersion` from `export-validator.ts`.
///
/// - Missing `metadata.version` and `metadata.type` → `.v1_0`
/// - `recipes-simple` type → `.v1_0`
/// - `recipes-v1.X` type → `.v1_X`
public func normalizeNativeFormatVersion(
    version: String?,
    type: String?
) -> NativeFormatVersion {
    if let version, !version.isEmpty {
        if let parsed = NativeFormatVersion(rawValue: version) {
            return parsed
        }
    }
    if let type {
        switch type {
        case "recipes-v1.5": return .v1_5
        case "recipes-v1.4": return .v1_4
        case "recipes-v1.3": return .v1_3
        case "recipes-v1.2": return .v1_2
        case "recipes-simple": return .v1_0
        default: break
        }
    }
    return .v1_0
}

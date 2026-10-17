import Foundation

/// Locale-aware decimal formatting/parsing for UI numbers.
///
/// The app switches language in-app (`AppLanguagePreference`); `Locale.current`
/// does not follow that choice, so formatters must use `AppNumberFormat.current`.
/// `String(format:)` without an explicit locale always renders `.` — never use it
/// for user-facing numbers (docs/I18N.md, «Форматирование»).
enum AppNumberFormat {
    /// Locale matching the app language preference (ru → comma, en → dot).
    static var current: Locale {
        AppLanguagePreference.current.locale
    }

    /// Formats a finite double without grouping separators.
    /// NaN/Inf → `""`. Integral values render without a fraction part
    /// (`minimumFractionDigits: 0`), trailing zeros are trimmed by the formatter.
    static func string(
        _ value: Double,
        minimumFractionDigits: Int = 0,
        maximumFractionDigits: Int,
        locale: Locale = AppNumberFormat.current
    ) -> String {
        guard value.isFinite else { return "" }
        let formatter = formatter(
            locale: locale,
            minimumFractionDigits: minimumFractionDigits,
            maximumFractionDigits: maximumFractionDigits
        )
        return formatter.string(from: NSNumber(value: value)) ?? ""
    }

    private struct FormatterKey: Hashable {
        let locale: Locale
        let minimumFractionDigits: Int
        let maximumFractionDigits: Int
    }

    private static let formattersLock = NSLock()
    private static var formatters: [FormatterKey: NumberFormatter] = [:]

    /// Ingredient rows and nutrition lines format numbers on every render; creating a
    /// `NumberFormatter` each time showed up in the recipe open trace. Formatters are never
    /// mutated after setup, and formatting with a shared one is thread-safe.
    /// The returned formatter is shared: never change its settings.
    static func formatter(
        locale: Locale,
        minimumFractionDigits: Int,
        maximumFractionDigits: Int
    ) -> NumberFormatter {
        let key = FormatterKey(
            locale: locale,
            minimumFractionDigits: minimumFractionDigits,
            maximumFractionDigits: maximumFractionDigits
        )
        formattersLock.lock()
        defer { formattersLock.unlock() }
        if let cached = formatters[key] { return cached }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.maximumFractionDigits = maximumFractionDigits
        formatters[key] = formatter
        return formatter
    }

    /// Parses user/Y.Doc text with either decimal separator (`,` and `.`);
    /// whitespace and grouping spaces are ignored.
    static func parse(_ text: String, locale: Locale = AppNumberFormat.current) -> Double? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        trimmed = trimmed.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{00A0}", with: "")
        if trimmed.contains(",") && trimmed.contains(".") {
            // Mixed separators: treat the last one as decimal, the other as grouping.
            if trimmed.lastIndex(of: ",")! > trimmed.lastIndex(of: ".")! {
                trimmed = trimmed.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                trimmed = trimmed.replacingOccurrences(of: ",", with: "")
            }
        } else if trimmed.contains(",") {
            trimmed = trimmed.replacingOccurrences(of: ",", with: ".")
        }
        return Double(trimmed)
    }
}

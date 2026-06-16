import SwiftUI

/// Linear progress bar with a localized `completed / total` caption.
/// Used for native data import/export in profile and file import in `ImportRecipeSheet`.
struct FractionProgressView: View {
    let completed: Int
    let total: Int
    let messageKey: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: progressFraction)
            Text(verbatim: Self.formattedMessage(completed: completed, total: total, key: messageKey))
                .appBody()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressFraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(completed) / Double(total))
    }

    static func formattedMessage(completed: Int, total: Int, key: String) -> String {
        String(
            format: Bundle.currentLocalizedString(key),
            locale: AppLanguagePreference.current.locale,
            completed,
            total
        )
    }
}

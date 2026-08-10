import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// SF Symbols with consistent semibold weight across the app.
enum AppSymbol {
#if canImport(UIKit)
    private static let configuration = UIImage.SymbolConfiguration(weight: .semibold)
    private static let toolbarConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
    /// Timer panel controls — footnote-scale SF Symbols (~17 pt).
    private static let compactControlConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)

    static func image(_ systemName: String) -> Image {
        symbolImage(systemName, configuration: configuration)
    }

    /// Recipe detail nav bar actions (web `w-5 h-5`, stroke semibold).
    static func toolbarImage(_ systemName: String) -> Image {
        symbolImage(systemName, configuration: toolbarConfiguration)
    }

    static func compactControlImage(_ systemName: String) -> Image {
        symbolImage(systemName, configuration: compactControlConfiguration)
    }

    /// Large decorative symbol for empty states (`AppTypography.emptyStateIconSize`, 48 pt).
    static func emptyStateImage(_ systemName: String) -> Image {
        Image(systemName: systemName)
    }

    /// Placeholder / decorative symbol at an explicit point size (UIImage-backed, scales reliably).
    static func sizedImage(
        _ systemName: String,
        pointSize: CGFloat,
        weight: UIImage.SymbolWeight = .regular
    ) -> Image {
        symbolImage(
            systemName,
            configuration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        )
    }

    private static func symbolImage(_ systemName: String, configuration: UIImage.SymbolConfiguration) -> Image {
        guard let uiImage = UIImage(systemName: systemName, withConfiguration: configuration)?
            .withRenderingMode(.alwaysTemplate) else {
            return Image(systemName: systemName)
        }
        return Image(uiImage: uiImage)
            .renderingMode(.template)
    }
#else
    static func image(_ systemName: String) -> Image {
        Image(systemName: systemName)
    }

    /// macOS uses SwiftUI's symbol metrics instead of UIKit's UIImage configuration.
    static func toolbarImage(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 20, weight: .semibold))
    }

    static func compactControlImage(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
    }

    static func emptyStateImage(_ systemName: String) -> Image {
        Image(systemName: systemName)
    }

    static func sizedImage(
        _ systemName: String,
        pointSize: CGFloat,
        weight: Font.Weight = .regular
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: pointSize, weight: weight))
    }
#endif
}

enum AppLabel {
    static func make(_ title: String, symbol systemName: String) -> some View {
        Label {
            Text(verbatim: Bundle.currentLocalizedString(title))
                .appBody()
        } icon: {
            AppSymbol.image(systemName)
        }
    }

    static func make(_ titleKey: LocalizedStringKey, symbol systemName: String) -> some View {
        Label {
            Text(titleKey)
                .appBody()
        } icon: {
            AppSymbol.image(systemName)
        }
    }
}

/// Label + 48 pt icon for `ContentUnavailableView` title slots.
enum AppEmptyState {
    @ViewBuilder
    static func icon(_ systemName: String, weight: Font.Weight = .light) -> some View {
        AppSymbol.emptyStateImage(systemName)
            .font(.system(size: AppTypography.emptyStateIconSize, weight: weight))
    }

    static func label(_ title: String, symbol systemName: String) -> some View {
        Label {
            Text(verbatim: Bundle.currentLocalizedString(title))
                .appBody()
        } icon: {
            icon(systemName)
        }
    }

    static func label(_ titleKey: LocalizedStringKey, symbol systemName: String) -> some View {
        Label {
            Text(titleKey)
                .appBody()
        } icon: {
            icon(systemName)
        }
    }
}

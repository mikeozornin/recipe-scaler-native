import SwiftUI
import UIKit

/// SF Symbols with consistent semibold weight across the app.
enum AppSymbol {
    private static let configuration = UIImage.SymbolConfiguration(weight: .semibold)
    private static let toolbarConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)

    static func image(_ systemName: String) -> Image {
        symbolImage(systemName, configuration: configuration)
    }

    /// Recipe detail nav bar actions (web `w-5 h-5`, stroke semibold).
    static func toolbarImage(_ systemName: String) -> Image {
        symbolImage(systemName, configuration: toolbarConfiguration)
    }

    private static func symbolImage(_ systemName: String, configuration: UIImage.SymbolConfiguration) -> Image {
        guard let uiImage = UIImage(systemName: systemName, withConfiguration: configuration)?
            .withRenderingMode(.alwaysTemplate) else {
            return Image(systemName: systemName)
        }
        return Image(uiImage: uiImage)
            .renderingMode(.template)
    }
}

enum AppLabel {
    static func make(_ title: String, symbol systemName: String) -> Label<Text, Image> {
        Label {
            Text(title)
                .font(AppTypography.body)
        } icon: {
            AppSymbol.image(systemName)
        }
    }

    static func make(_ titleKey: LocalizedStringKey, symbol systemName: String) -> Label<Text, Image> {
        Label {
            Text(titleKey)
                .font(AppTypography.body)
        } icon: {
            AppSymbol.image(systemName)
        }
    }
}
import SwiftUI
import UIKit

/// SF Symbols with consistent semibold weight across the app.
enum AppSymbol {
    private static let configuration = UIImage.SymbolConfiguration(weight: .semibold)

    static func image(_ systemName: String) -> Image {
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
        } icon: {
            AppSymbol.image(systemName)
        }
    }

    static func make(_ titleKey: LocalizedStringKey, symbol systemName: String) -> Label<Text, Image> {
        Label {
            Text(titleKey)
        } icon: {
            AppSymbol.image(systemName)
        }
    }
}
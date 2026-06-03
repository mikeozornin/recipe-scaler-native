//
//  RecipeSymbol.swift
//  RecipeScalerNative
//
//  Custom symbol images from Assets (`rs.*.symbolset`), generated from web icons.
//  See scripts/build-recipe-sf-symbol-pack.py and RecipeSymbols.manifest.json.
//

import SwiftUI
import UIKit

/// Web icon → asset catalog symbol name (`rs.<camelCase>`).
enum RecipeSymbol: String, CaseIterable, Sendable {
    case activity = "rs.activity"
    case aiChatFace = "rs.aiChatFace"
    case alarmClock = "rs.alarmClock"
    case alertCircle = "rs.alertCircle"
    case alertTriangle = "rs.alertTriangle"
    case arrowDownFromLine = "rs.arrowDownFromLine"
    case arrowLeft = "rs.arrowLeft"
    case bell = "rs.bell"
    case bold = "rs.bold"
    case bookOpen = "rs.bookOpen"
    case bowl = "rs.bowl"
    case check = "rs.check"
    case checkOffsetCircle = "rs.checkOffsetCircle"
    case chevronDown = "rs.chevronDown"
    case chevronRight = "rs.chevronRight"
    case chevronUp = "rs.chevronUp"
    case circle = "rs.circle"
    case clipboardText = "rs.clipboardText"
    case clockCcw = "rs.clockCcw"
    case coffee = "rs.coffee"
    case copy = "rs.copy"
    case download = "rs.download"
    case forkKnife = "rs.forkKnife"
    case gripVertical = "rs.gripVertical"
    case heading01 = "rs.heading01"
    case info = "rs.info"
    case link = "rs.link"
    case listOrdered = "rs.listOrdered"
    case listUnordered = "rs.listUnordered"
    case loaderCircle = "rs.loaderCircle"
    case logOut = "rs.logOut"
    case mathOperations = "rs.mathOperations"
    case minus = "rs.minus"
    case moon = "rs.moon"
    case moreVertical = "rs.moreVertical"
    case paperPlane = "rs.paperPlane"
    case pause = "rs.pause"
    case pencil = "rs.pencil"
    case pin = "rs.pin"
    case pinOff = "rs.pinOff"
    case play = "rs.play"
    case plus = "rs.plus"
    case printer = "rs.printer"
    case redo = "rs.redo"
    case refreshCw = "rs.refreshCw"
    case scan = "rs.scan"
    case search = "rs.search"
    case share = "rs.share"
    case share2 = "rs.share2"
    case shoppingCart = "rs.shoppingCart"
    case sparkles = "rs.sparkles"
    case square = "rs.square"
    case squareImage = "rs.squareImage"
    case sun = "rs.sun"
    case sunMoon = "rs.sunMoon"
    case trash = "rs.trash"
    case trendingUp = "rs.trendingUp"
    case undo = "rs.undo"
    case unplug = "rs.unplug"
    case upload = "rs.upload"
    case user = "rs.user"
    case users = "rs.users"
    case x = "rs.x"
    case xMarkCircle = "rs.xMarkCircle"

    var assetName: String { rawValue }

    /// SwiftUI image; scales with Dynamic Type when used with `.font(...)` like SF Symbols.
    func image(
        textStyle: UIFont.TextStyle = .body,
        weight: UIImage.SymbolWeight = .semibold,
        scale: UIImage.SymbolScale = .medium
    ) -> Image {
        let font = UIFontMetrics(forTextStyle: textStyle).scaledFont(for: UIFont.systemFont(ofSize: AppTypography.bodySize))
        let config = UIImage.SymbolConfiguration(font: font, scale: scale)
            .applying(UIImage.SymbolConfiguration(weight: weight))
        guard let uiImage = UIImage(named: assetName, in: .main, with: config)?
            .withRenderingMode(.alwaysTemplate) else {
            return Image(assetName)
        }
        return Image(uiImage: uiImage).renderingMode(.template)
    }

    /// Toolbar-sized symbol (20 pt reference, scaled for accessibility).
    func toolbarImage() -> Image {
        let pointSize = UIFontMetrics(forTextStyle: .body).scaledValue(for: AppToolbarStyle.iconSide)
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold, scale: .medium)
        guard let uiImage = UIImage(named: assetName, in: .main, with: config)?
            .withRenderingMode(.alwaysTemplate) else {
            return Image(assetName)
        }
        return Image(uiImage: uiImage).renderingMode(.template)
    }
}

enum RecipeLabel {
    static func make(_ title: String, symbol: RecipeSymbol) -> Label<Text, Image> {
        Label {
            Text(title).font(AppTypography.body)
        } icon: {
            symbol.image()
        }
    }

    static func make(_ titleKey: LocalizedStringKey, symbol: RecipeSymbol) -> Label<Text, Image> {
        Label {
            Text(titleKey).font(AppTypography.body)
        } icon: {
            symbol.image()
        }
    }
}
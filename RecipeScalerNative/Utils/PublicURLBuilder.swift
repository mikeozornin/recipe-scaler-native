//
//  PublicURLBuilder.swift
//  RecipeScalerNative
//

import Foundation
import RecipeScalerCore

/// Builds public web URLs for share sheets and in-app Safari.
///
/// Share links are **path-based** (`/public/...`, no hash) so social crawlers
/// receive Open Graph HTML from the server. SPA still opens via server handoff
/// to `/#/public/...`. See recipe-scaler-web OG public pages.
/// About/privacy stay on HashRouter routes.
enum PublicURLBuilder {
    static func recipeShareURL(recipeId: String) -> URL? {
        URL(string: "\(Config.baseURL)/public/\(recipeId)")
    }

    static func publicProfileURL(username: String) -> URL? {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        return URL(string: "\(Config.baseURL)/public/@/\(encoded)")
    }

    static func profileRecipeURL(username: String, recipeId: String) -> URL? {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        return URL(string: "\(Config.baseURL)/public/@/\(encoded)/\(recipeId)")
    }

    static func shoppingListShareURL(publicId: String) -> URL? {
        URL(string: "\(Config.baseURL)/public/shopping-list/\(publicId)")
    }

    /// HashRouter About page with app language for web `usePageLanguageOverride`.
    static var aboutURL: URL {
        URL(string: "\(Config.baseURL)/#/about?lang=\(AppLanguagePreference.current.rawValue)")!
    }

    /// HashRouter Privacy page with app language for web `usePageLanguageOverride`.
    static var privacyURL: URL {
        URL(string: "\(Config.baseURL)/#/privacy?lang=\(AppLanguagePreference.current.rawValue)")!
    }

    /// Apple's Standard EULA used as the app Terms of Use (App Store Connect
    /// License Agreement selects the standard license). Required next to the
    /// purchase flow per guideline 3.1.2(c).
    static let termsOfUseURL = URL(
        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    )!
}
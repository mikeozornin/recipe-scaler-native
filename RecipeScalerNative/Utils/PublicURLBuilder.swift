//
//  PublicURLBuilder.swift
//  RecipeScalerNative
//

import Foundation

enum PublicURLBuilder {
    static func recipeShareURL(recipeId: String) -> URL? {
        URL(string: "\(Config.baseURL)/#/public/\(recipeId)")
    }

    static func publicProfileURL(username: String) -> URL? {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        return URL(string: "\(Config.baseURL)/#/public/@/\(encoded)")
    }

    static func profileRecipeURL(username: String, recipeId: String) -> URL? {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        return URL(string: "\(Config.baseURL)/#/public/@/\(encoded)/\(recipeId)")
    }

    static func shoppingListShareURL(publicId: String) -> URL? {
        URL(string: "\(Config.baseURL)/#/public/shopping-list/\(publicId)")
    }

    static var aboutURL: URL {
        URL(string: "\(Config.baseURL)/#/about")!
    }
}
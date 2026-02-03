//
//  AccessibilityIdentifiers.swift
//  RecipeScalerNative
//

import Foundation

enum AccessibilityIdentifiers {
    static let rootContent = "root_content"
    static let splashView = "splash_view"
    static let authRoot = "auth_root"
    static let authNewUserButton = "auth_new_user_button"
    static let authExistingUserButton = "auth_existing_user_button"
    static let authSeedTextEditor = "auth_seed_text_editor"
    static let authLoginButton = "auth_login_button"
    static let authBackButton = "auth_back_button"
    static let authQRCodeButton = "auth_qr_code_button"
    static let qrScannerCancel = "qr_scanner_cancel"

    static let recipeList = "recipe_list"
    static let recipeRowPrefix = "recipe_row_"
    static let profileButton = "profile_button"
    static let scaleMinusButton = "scale_minus_button"
    static let scalePlusButton = "scale_plus_button"
    static let scaleSlider = "scale_slider"
    static let ingredientsSection = "ingredients_section"
    static let stepsSection = "steps_section"

    static func recipeRow(id: String) -> String {
        "\(recipeRowPrefix)\(id)"
    }
}

//
//  SplashView.swift
//  RecipeScalerNative
//
//

import RecipeScalerCore
import SwiftUI

struct SplashView: View {
    private var appDisplayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? String(localized: "splash.app-name")
    }

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(.systemBackground))
                        .shadow(color: Color(red: 0.88, green: 0.22, blue: 0.00, opacity: 0.30), radius: 20, x: 0, y: 10)
                        .frame(width: 96, height: 96)

                    Image(RecipeScalerFlavor.appLogoAssetName)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }

                Text(verbatim: appDisplayName)
                    .font(AppTypography.display(AppTypography.splashTitleSize))
            }
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.splashView)
    }
}

#Preview {
    SplashView()
}

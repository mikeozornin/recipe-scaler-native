//
//  SplashView.swift
//  RecipeScalerNative
//
//

import SwiftUI

struct SplashView: View {
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

                    Image("AppLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }

                Text("splash.app-name")
                    .font(AppTypography.display(AppTypography.splashTitleSize))
            }
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.splashView)
    }
}

#Preview {
    SplashView()
}

//
//  ScreenAwakeStatusBanner.swift
//  RecipeScalerNative
//

import SwiftUI

/// Sticky status strip when keep-awake is on (web `common.screen-always-on` banner).
struct ScreenAwakeStatusBanner: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var indicatorPulse = false

    private var bannerBackground: Color {
        colorScheme == .dark ? Color.green.opacity(0.22) : Color.green.opacity(0.14)
    }

    private var bannerBorder: Color {
        colorScheme == .dark ? Color.green.opacity(0.38) : Color.green.opacity(0.28)
    }

    private var bannerText: Color {
        colorScheme == .dark ? Color(red: 0.55, green: 0.85, blue: 0.65) : Color(red: 0.1, green: 0.45, blue: 0.2)
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .opacity(indicatorPulse ? 1 : 0.45)
            Text("common.screen-always-on")
                .appBody()
                .foregroundStyle(bannerText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(bannerBackground)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(bannerBorder)
                .frame(height: 0.5)
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.screenAwakeBanner)
        .onAppear {
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                indicatorPulse = true
            }
        }
    }
}
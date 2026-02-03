//
//  ContentView.swift
//  RecipeScalerNative
//
//

import SwiftUI

struct ContentView: View {
    @StateObject private var authService = AuthService.shared
    @State private var showSplash = true
    private let isUITesting = ProcessInfo.processInfo.arguments.contains("ui-testing")

    var body: some View {
        ZStack {
            if showSplash {
                SplashView()
            } else if authService.isAuthenticated {
                RecipeListView()
            } else {
                AuthView()
            }
        }
        .task {
            if isUITesting {
                showSplash = false
            } else {
                try? await Task.sleep(nanoseconds: 500_000_000)
                showSplash = false
            }
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.rootContent)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Recipe.self, inMemory: true)
}

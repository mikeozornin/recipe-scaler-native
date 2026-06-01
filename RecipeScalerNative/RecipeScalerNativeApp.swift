//
//  RecipeScalerNativeApp.swift
//  RecipeScalerNative
//
//

import SwiftUI
import SwiftData
import UIKit
#if DEBUG
import Agentation
#endif

@main
struct RecipeScalerNativeApp: App {
    init() {
        configureNavigationBarFonts()
        #if DEBUG
        Agentation.shared.install()
        #endif
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Recipe.self,
            Ingredient.self,
            RecipeTimer.self,
            ApiCacheEntry.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }

    private func configureNavigationBarFonts() {
        let largeTitleFont = UIFont(name: AppFonts.display, size: 34) ?? UIFont.systemFont(ofSize: 34, weight: .bold)
        let inlineTitleFont = UIFont(name: AppFonts.sansMedium, size: 17) ?? UIFont.systemFont(ofSize: 17, weight: .semibold)

        let navBar = UINavigationBar.appearance()
        navBar.largeTitleTextAttributes = [
            .font: largeTitleFont,
            .foregroundColor: UIColor.label
        ]
        navBar.titleTextAttributes = [
            .font: inlineTitleFont,
            .foregroundColor: UIColor.label
        ]
    }
}

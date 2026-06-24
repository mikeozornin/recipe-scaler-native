//
//  AuthAvatarImage.swift
//  RecipeScalerNative
//

import SwiftUI
import RecipeScalerCore

/// Loads an avatar URL with the app's auth header (x-user-id / Bearer).
/// AsyncImage uses bare URLSession and won't pass auth — use this instead.
/// Network/caching lives in `AvatarImageService` (composition root); the view
/// never touches `APIClient.shared` directly.
@MainActor
struct AuthAvatarImage: View {
    let url: URL

    @Environment(\.appContainer) private var appContainer
    @State private var uiImage: UIImage?

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage).resizable().scaledToFill()
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .task(id: url) {
            guard let service = appContainer?.avatar else { return }
            uiImage = await service.image(for: url)
        }
    }
}

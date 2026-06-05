//
//  AuthAvatarImage.swift
//  RecipeScalerNative
//

import SwiftUI

/// Loads an avatar URL with the app's auth header (x-user-id / Bearer).
/// AsyncImage uses bare URLSession and won't pass auth — use this instead.
@MainActor
struct AuthAvatarImage: View {
    let url: URL

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
        .task(id: url) { await load() }
    }

    private func load() async {
        let req = APIClient.shared.recipeImageDownloadRequest(
            remoteURL: url,
            etag: nil,
            lastModified: nil
        )
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let img = UIImage(data: data) else { return }
        uiImage = img
    }
}

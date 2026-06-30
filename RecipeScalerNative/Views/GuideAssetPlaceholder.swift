//
//  GuideAssetPlaceholder.swift
//  RecipeScalerNative
//
//  Spec 040 — gray placeholder shown where a real screenshot or video will
//  live once assets are produced. Used in #Preview and as runtime fallback
//  when an imageset/mp4 is missing from the bundle.
//

import SwiftUI

struct GuideAssetPlaceholder: View {
    /// Human-readable name, e.g. "guide_sent_assistant_message_ex_01" or
    /// "guide_imported_recipe_video". Shown in the placeholder so it's
    /// obvious which asset is missing during development.
    let name: String

    /// 9:19.5 ≈ 0.46 — matches portrait screenshot frames used in guides.
    static let defaultAspectRatio: CGFloat = 9.0 / 19.5

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemFill))
            VStack(spacing: 6) {
                Image(systemName: "photo")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(.secondary)
                Text(verbatim: name)
                    .font(AppTypography.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
        }
        .aspectRatio(Self.defaultAspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

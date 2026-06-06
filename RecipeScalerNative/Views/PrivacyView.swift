//
//  PrivacyView.swift
//  RecipeScalerNative
//
//  Static privacy & security page — mirrors the content from
//  https://recipe-scaler.ru/#/privacy as native SwiftUI.
//

import SwiftUI

struct PrivacyView: View {
    @Environment(\.locale) private var locale

    var body: some View {
        // Read locale so the view re-evaluates on language switch.
        _ = locale
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                introSection
                pointsSection
                feedbackSection
            }
            .padding()
        }
        .appListBodyTypography()
    }

    // MARK: - Intro

    @ViewBuilder
    private var introSection: some View {
        Text("privacy.intro")
            .appBody()
            .foregroundStyle(.secondary)
    }

    // MARK: - Points

    @ViewBuilder
    private var pointsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            point(number: 1, key: "privacy.point.1")

            VStack(alignment: .leading, spacing: 8) {
                point(number: 2, key: "privacy.point.2")
                serverKnowsList
            }

            point(number: 3, key: "privacy.point.3")

            VStack(alignment: .leading, spacing: 8) {
                point(number: 4, key: "privacy.point.4")
                aiServicesList
            }

            point(number: 5, key: "privacy.point.5")
            point(number: 6, key: "privacy.point.6")
            point(number: 7, key: "privacy.point.7")
            point(number: 8, key: "privacy.point.8")
            point(number: 9, key: "privacy.point.9")
        }
    }

    private func point(number: Int, key: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(verbatim: "\(number).")
                .font(AppTypography.body)
                .fontWeight(.medium)
                .frame(minWidth: 20, alignment: .trailing)
            Text(verbatim: localized(key))
                .appBody()
        }
    }

    // MARK: - Sub-lists

    @ViewBuilder
    private var serverKnowsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(1...7, id: \.self) { index in
                HStack(alignment: .top, spacing: 6) {
                    Text(verbatim: "\u{2022}")
                        .font(AppTypography.body)
                        .frame(minWidth: 12, alignment: .center)
                    Text(verbatim: localized("privacy.serverKnows.\(index)"))
                        .appBody()
                }
            }
        }
        .padding(.leading, 24)
    }

    @ViewBuilder
    private var aiServicesList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(1...4, id: \.self) { index in
                HStack(alignment: .top, spacing: 4) {
                    Text(verbatim: "4.\(index).")
                        .font(AppTypography.body)
                        .fontWeight(.medium)
                        .frame(minWidth: 28, alignment: .trailing)
                    Text(verbatim: localized("privacy.aiServices.\(index)"))
                        .appBody()
                }
            }
        }
        .padding(.leading, 24)
    }

    // MARK: - Feedback

    @ViewBuilder
    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            Text("privacy.feedback.title")
                .font(AppTypography.title3)
                .padding(.top, 4)

            (
                Text("privacy.feedback.text")
                    .font(AppTypography.body)
                + Text(verbatim: " ")
                + Text("[mike.ozornin@gmail.com](mailto:mike.ozornin@gmail.com)")
                    .font(AppTypography.body)
            )
        }
    }

    // MARK: - Helpers

    /// Resolves a localization key through `Bundle.currentLocalizedString`
    /// which honors the runtime language override (`AppLanguagePreference`).
    /// `LocalizedStringKey(stringInterpolation:)` with variables does NOT
    /// pick up the bundle override — hence this helper.
    private func localized(_ key: String) -> String {
        Bundle.currentLocalizedString(key)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        PrivacyView()
            .localizedNavigationTitle("privacy.title")
    }
}
#endif

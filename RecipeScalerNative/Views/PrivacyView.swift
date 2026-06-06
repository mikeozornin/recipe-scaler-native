//
//  PrivacyView.swift
//  RecipeScalerNative
//
//  Static privacy & security page — mirrors the content from
//  https://recipe-scaler.ru/#/privacy as native SwiftUI.
//

import SwiftUI

struct PrivacyView: View {
    var body: some View {
        ScrollView {
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

    @ViewBuilder
    private func point(number: Int, key: LocalizedStringKey) -> some View {
        Text(verbatim: "\(number). ")
            .font(AppTypography.body)
            .fontWeight(.medium)
        + Text(key)
            .appBody()
    }

    // MARK: - Sub-lists

    @ViewBuilder
    private var serverKnowsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(1...7, id: \.self) { index in
                bullet(key: LocalizedStringKey("privacy.serverKnows.\(index)"))
            }
        }
        .padding(.leading, 24)
    }

    @ViewBuilder
    private var aiServicesList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(1...4, id: \.self) { index in
                Text(verbatim: "4.\(index). ")
                    .font(AppTypography.body)
                    .fontWeight(.medium)
                + Text(LocalizedStringKey("privacy.aiServices.\(index)"))
                    .appBody()
            }
        }
        .padding(.leading, 24)
    }

    @ViewBuilder
    private func bullet(key: LocalizedStringKey) -> some View {
        Text(verbatim: "\u{2022} ")
            .font(AppTypography.body)
        + Text(key)
            .appBody()
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
                    .appBody()
                + Text(verbatim: " ")
                + Text("[mike.ozornin@gmail.com](mailto:mike.ozornin@gmail.com)")
                    .appBody()
            )
        }
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

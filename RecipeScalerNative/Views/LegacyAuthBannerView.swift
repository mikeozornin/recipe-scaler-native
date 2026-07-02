//
//  LegacyAuthBannerView.swift
//  RecipeScalerNative
//
//  Spec 041 AC18 — grace-period banner on Account screen.
//

import SwiftUI

struct LegacyAuthBannerView: View {
    let userId: String
    @Environment(\.locale) private var locale

    @State private var isEligible = false
    @State private var shouldShowAlert = true
    @State private var cutoffAt: Date?
    @State private var detailsExpanded = false

    var body: some View {
        Group {
            if isEligible, shouldShowAlert, let cutoffAt {
                bannerContent(cutoffAt: cutoffAt)
            }
        }
        .task(id: userId) {
            await refresh()
        }
    }

    @ViewBuilder
    private func bannerContent(cutoffAt: Date) -> some View {
        let days = daysUntil(cutoffAt)
        let dateLabel = formatCutoffDate(cutoffAt)

        VStack(alignment: .leading, spacing: 8) {
            Text(
                String(
                    format: Bundle.currentLocalizedString("legacyAuth.banner.message"),
                    locale: locale,
                    days,
                    dateLabel
                )
            )
            .appFootnote()
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if detailsExpanded {
                Text("legacyAuth.banner.details")
                    .appFootnote()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 16) {
                Button {
                    withAnimation { detailsExpanded.toggle() }
                } label: {
                    Text("legacyAuth.banner.more")
                        .appFootnote()
                }
                .buttonStyle(.borderless)

                Spacer(minLength: 0)

                Button {
                    LegacyAuthBannerReminder.postpone(userId: userId)
                    shouldShowAlert = false
                } label: {
                    AppSymbol.image("xmark")
                        .font(AppTypography.footnote)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Bundle.currentLocalizedString("common.close"))
            }
        }
        .padding(.vertical, 4)
    }

    private func refresh() async {
        guard LegacyAuthBannerReminder.shouldShow(userId: userId) else {
            isEligible = false
            shouldShowAlert = false
            return
        }

        do {
            let status = try await AccountAPI.fetchLegacyAuthStatus()
            guard let cutoffString = status.legacyAuthCutoffAt,
                  let cutoff = ISO8601DateFormatter().date(from: cutoffString)
                    ?? legacyCutoffDateParser(cutoffString)
            else {
                isEligible = false
                return
            }
            if status.allMigrated || !status.hasOtherUnmigratedDevices || cutoff <= Date() {
                isEligible = false
                return
            }
            cutoffAt = cutoff
            isEligible = true
            shouldShowAlert = LegacyAuthBannerReminder.shouldShow(userId: userId)
        } catch {
            isEligible = false
        }
    }

    private func daysUntil(_ date: Date) -> Int {
        max(0, Int(ceil(date.timeIntervalSinceNow / (24 * 60 * 60))))
    }

    private func formatCutoffDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month().year().locale(locale))
    }

    /// Server may return Postgres timestamptz without fractional seconds.
    private func legacyCutoffDateParser(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"
        if let d = formatter.date(from: value) { return d }
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter.date(from: value)
    }
}
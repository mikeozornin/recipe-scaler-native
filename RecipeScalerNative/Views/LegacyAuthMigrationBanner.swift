//
//  LegacyAuthMigrationBanner.swift
//  RecipeScalerNative
//
//  Spec 041 AC18 — grace-period reminder on Account screen.
//

import SwiftUI

struct LegacyAuthMigrationBanner: View {
    let cutoffDate: Date
    let daysRemaining: Int
    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(verbatim: bannerBodyText)
                    .appBody()
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                AppSymbol.image("lock.shield")
                    .foregroundStyle(.secondary)
            }

            Button {
                showsDetails = true
            } label: {
                Text("account.legacy-auth.banner.more")
                    .appFootnote()
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showsDetails) {
            NavigationStack {
                ScrollView {
                    Text("account.legacy-auth.banner.details")
                        .appBody()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .localizedNavigationTitle("account.legacy-auth.banner.more")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showsDetails = false
                        } label: {
                            Text("common.done")
                        }
                    }
                }
            }
            .appOpaqueSheetPresentationPlain()
        }
    }

    private var bannerBodyText: String {
        let dateText = cutoffDate.formatted(date: .abbreviated, time: .omitted)
        let format = Bundle.currentLocalizedString("account.legacy-auth.banner.body")
        return String(format: format, locale: Locale.current, daysRemaining, dateText)
    }
}
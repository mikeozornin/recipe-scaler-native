//
//  SystemBannerChrome.swift
//  RecipeScalerNative
//
//  Spec 061 — places the system banner inside scrollable recipe-list content
//  so it scrolls away with the list (not sticky above the scroll view).
//

import SwiftUI

/// Renders the active system banner when present. Reads `SystemBannerStore`
/// from the environment; no-op when there is nothing to show.
struct SystemBannerChrome: View {
    @Environment(SystemBannerStore.self) private var systemBannerStore

    private var bannerToShow: SystemBannerDTO? {
        guard let banner = systemBannerStore.activeBanner else { return nil }
        #if DEBUG
        if DebugLaunchOptions.screenshotCapture { return nil }
        #endif
        return banner
    }

    var body: some View {
        if let banner = bannerToShow {
            SystemBannerView(banner: banner) {
                Task { await systemBannerStore.dismiss() }
            }
        }
    }
}

/// List-row wrapper so the banner sits inside a `List` and scrolls with rows.
struct SystemBannerListRow: View {
    var body: some View {
        SystemBannerChrome()
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

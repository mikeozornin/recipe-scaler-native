//
//  SystemBannerChrome.swift
//  RecipeScalerNative
//
//  Spec 061 — places the system banner inside scrollable recipe-list content
//  so it scrolls away with the list (not sticky above the scroll view).
//

import SwiftUI

/// Renders the active system banner when present.
///
/// `systemBannerStore` is injected (not `@Environment`) on the recipes
/// navigation path — after the assistant sheet dismisses, iOS 26 measures nav
/// chrome in a fallback environment and `@Environment(SystemBannerStore.self)`
/// traps.
struct SystemBannerChrome: View {
    let systemBannerStore: SystemBannerStore

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
    let systemBannerStore: SystemBannerStore

    var body: some View {
        SystemBannerChrome(systemBannerStore: systemBannerStore)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

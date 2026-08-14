//
//  AccountTipsSection.swift
//  RecipeScalerNative
//

import StoreKit
import SwiftUI

/// Parent profile row for the StoreKit-backed support submenu.
struct AccountTipsSection: View {
    var body: some View {
        Section {
            NavigationLink {
                AccountTipsView()
            } label: {
                Text("account.tips.menu")
                    .appBody()
                    .foregroundStyle(.primary)
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.accountTipsMenu)
            .tint(.primary)

            NavigationLink {
                AccountFeedbackView()
            } label: {
                Text("account.feedback.menu")
                    .appBody()
                    .foregroundStyle(.primary)
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.accountFeedbackMenu)
            .tint(.primary)
        } header: {
            AppSectionHeader("account.section.tips")
        }
        .appListSectionHeaderStyle()
        .accessibilityIdentifier(AccessibilityIdentifiers.accountTipsSection)
    }
}

/// One-time tips and the monthly subscription shown inside the profile submenu.
struct AccountTipsView: View {
    @Environment(TipPurchaseService.self) private var tips
    @State private var isManageSubscriptionsPresented = false
    @State private var legalLink: LegalLink?

    private enum LegalLink: String, Identifiable {
        case terms, privacy

        var id: String { rawValue }

        var url: URL {
            switch self {
            case .terms:
                return PublicURLBuilder.termsOfUseURL
            case .privacy:
                return PublicURLBuilder.privacyURL
            }
        }
    }

    var body: some View {
        storeKitList
        .localizedNavigationTitle("account.tips.menu")
        .listStyle(.insetGrouped)
        .appListBodyTypography()
        .tint(.primary)
        .task {
            await tips.loadProducts()
        }
        .manageSubscriptionsSheet(isPresented: $isManageSubscriptionsPresented)
        .sheet(item: $legalLink) { link in
            InAppSafariView(url: link.url)
                .ignoresSafeArea()
                .appOpaqueSheetPresentationPlain()
        }
    }

    private var storeKitList: some View {
        List {
            if tips.isLoading && tips.products.isEmpty {
                loadingSection
            } else if tips.products.isEmpty {
                unavailableSection
                legalSection
            } else {
                oneTimeTipsSection
                monthlySection
                subscriptionActionsSection
                statusSection
                legalSection
            }
        }
    }

    private var loadingSection: some View {
        Section {
            HStack(spacing: 12) {
                ProgressView()
                Text("account.tips.loading")
                    .appBody()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var unavailableSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("account.tips.unavailable")
                    .appBody()
                    .foregroundStyle(.secondary)

                Button {
                    Task { await tips.loadProducts(force: true) }
                } label: {
                    Label {
                        Text("account.tips.retry")
                            .appBody()
                    } icon: {
                        AppSymbol.image("arrow.clockwise")
                    }
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .disabled(tips.isBusy)
                .accessibilityIdentifier(AccessibilityIdentifiers.accountTipsRetry)
            }
        }
    }

    private var oneTimeTipsSection: some View {
        Section {
            ForEach(TipProductID.oneTime) { productID in
                if let product = tips.product(for: productID) {
                    productRow(productID: productID, product: product)
                }
            }
        } header: {
            AppSectionHeader("account.tips.one-time")
        }
        .appListSectionHeaderStyle()
    }

    @ViewBuilder
    private var monthlySection: some View {
        if let monthlyProduct = tips.product(for: .monthly) {
            Section {
                productRow(productID: .monthly, product: monthlyProduct)
            } header: {
                AppSectionHeader("account.tips.monthly")
            }
            .appListSectionHeaderStyle()
        }
    }

    @ViewBuilder
    private var subscriptionActionsSection: some View {
        if tips.product(for: .monthly) != nil {
            Section {
                if tips.isMonthlySubscriptionActive {
                    Button {
                        isManageSubscriptionsPresented = true
                    } label: {
                        Label {
                            Text("account.tips.manage")
                                .appBody()
                        } icon: {
                            AppSymbol.image("arrow.up.right.square")
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(AccessibilityIdentifiers.accountTipsManage)
                } else {
                    Button {
                        Task { await tips.restorePurchases() }
                    } label: {
                        HStack {
                            Text("account.tips.restore")
                                .appBody()
                            Spacer()
                            if tips.purchaseState == .restoring {
                                ProgressView()
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(tips.isBusy)
                    .accessibilityIdentifier(AccessibilityIdentifiers.accountTipsRestore)
                }
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if let message = tips.lastMessage {
            Section {
                Text(LocalizedStringKey(message.localizationKey))
                    .appFootnote()
                    .foregroundStyle(.secondary)
            }
        }

        if let error = tips.lastError {
            Section {
                Text(LocalizedStringKey(error.localizationKey))
                    .appFootnote()
                    .foregroundStyle(.red)
            }
        }
    }

    /// Guideline 3.1.2(c): functional Terms of Use (EULA) and Privacy Policy
    /// links must be part of the purchase flow itself, not only in metadata.
    /// The screen root applies `.tint(.primary)`, which also overrides
    /// `Color.accentColor` resolution inside this subtree — so use the
    /// concrete system blue (app default accent) instead of a semantic color.
    private var legalSection: some View {
        Section {
            Button {
                legalLink = .terms
            } label: {
                Text("account.tips.legal.terms")
                    .appBody()
                    .foregroundStyle(Color(uiColor: .systemBlue))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityIdentifiers.accountTipsTermsLink)

            Button {
                legalLink = .privacy
            } label: {
                Text("account.tips.legal.privacy")
                    .appBody()
                    .foregroundStyle(Color(uiColor: .systemBlue))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityIdentifiers.accountTipsPrivacyLink)
        }
    }

    @ViewBuilder
    private func productRow(
        productID: TipProductID,
        product: Product
    ) -> some View {
        Button {
            Task { await tips.purchase(productID) }
        } label: {
            HStack(spacing: 12) {
                Text(verbatim: product.displayName)
                    .appBody()
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                if tips.isPurchasing(productID) {
                    ProgressView()
                } else {
                    Text(verbatim: product.displayPrice)
                        .appBody()
                        .foregroundStyle(.primary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .disabled(tips.isBusy)
        .accessibilityIdentifier(AccessibilityIdentifiers.accountTipPurchase(productID: productID.rawValue))
        .accessibilityValue(Text(verbatim: product.displayPrice))
    }
}

#if DEBUG
#Preview {
    List {
        AccountTipsSection()
    }
    .listStyle(.insetGrouped)
    .appListBodyTypography()
    .environment(TipPurchaseService())
}
#endif

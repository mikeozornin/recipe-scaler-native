//
//  TipPurchaseService.swift
//  RecipeScalerNative
//

import Foundation
import Observation
import StoreKit

/// Product identifiers configured in App Store Connect for the in-app tips.
enum TipProductID: String, CaseIterable, Identifiable, Sendable {
    case one = "ru.recipescaler.tip.1"
    case two = "ru.recipescaler.tip.2"
    case five = "ru.recipescaler.tip.5"
    case ten = "ru.recipescaler.tip.10"
    case monthly = "ru.recipescaler.support.monthly"

    var id: String { rawValue }

    static let oneTime: [TipProductID] = [.one, .two, .five, .ten]
}

enum TipPurchaseState: Equatable, Sendable {
    case idle
    case purchasing(TipProductID)
    case restoring
}

enum TipPurchaseMessage: Equatable, Sendable {
    case purchasePending

    var localizationKey: String {
        switch self {
        case .purchasePending:
            return "account.tips.purchase-pending"
        }
    }
}

enum TipPurchaseError: Error, Equatable, Sendable {
    case productsUnavailable
    case purchaseFailed
    case purchaseVerificationFailed
    case restoreFailed

    var localizationKey: String {
        switch self {
        case .productsUnavailable:
            return "account.tips.unavailable"
        case .purchaseFailed, .purchaseVerificationFailed:
            return "account.tips.purchase-failed"
        case .restoreFailed:
            return "account.tips.restore-failed"
        }
    }
}

/// Owns StoreKit 2 product loading, purchases, transaction updates, and the
/// monthly subscription entitlement. The store is app-scoped because StoreKit
/// transactions belong to the Apple account, not to the Recipe Scaler account.
@MainActor
@Observable
final class TipPurchaseService {
    private(set) var products: [TipProductID: Product] = [:]
    private(set) var isLoading = false
    private(set) var purchaseState: TipPurchaseState = .idle
    private(set) var lastError: TipPurchaseError?
    private(set) var lastMessage: TipPurchaseMessage?
    private(set) var isMonthlySubscriptionActive = false

    private var didLoadProducts = false
    private var transactionUpdatesTask: Task<Void, Never>?

    init() {
        transactionUpdatesTask = Task { @MainActor [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                await self.handleTransactionUpdate(result)
            }
        }
    }

    var isBusy: Bool {
        purchaseState != .idle
    }

    func product(for productID: TipProductID) -> Product? {
        products[productID]
    }

    func isPurchasing(_ productID: TipProductID) -> Bool {
        purchaseState == .purchasing(productID)
    }

    /// Loads products once per app session. The retry action uses `force` so a
    /// product can appear after a temporary network/App Store failure.
    func loadProducts(force: Bool = false) async {
        guard !isLoading else { return }
        guard force || !didLoadProducts else { return }

        isLoading = true
        lastError = nil
        lastMessage = nil
        defer {
            isLoading = false
            didLoadProducts = true
        }

        let requestedProductIDs = TipProductID.allCases.map(\.rawValue)

        // #region agent log
        AppLog.info(.app, "tips_products_load_started", data: [
            "requested_count": String(requestedProductIDs.count),
            "product_ids": requestedProductIDs.joined(separator: ","),
            "force": force ? "true" : "false",
            "hypothesis_id": "A/B/C/D"
        ])
        // #endregion

        do {
            let fetchedProducts = try await Product.products(for: requestedProductIDs)
            let loadedProducts = fetchedProducts.reduce(
                into: [TipProductID: Product]()
            ) { result, product in
                guard let productID = TipProductID(rawValue: product.id) else { return }
                result[productID] = product
            }

            // #region agent log
            let fetchedProductIDs = fetchedProducts.map(\.id).sorted()
            let recognizedProductIDs = loadedProducts.keys.map(\.rawValue).sorted()
            AppLog.info(.app, "tips_products_load_succeeded", data: [
                "requested_count": String(requestedProductIDs.count),
                "received_count": String(fetchedProducts.count),
                "recognized_count": String(loadedProducts.count),
                "received_product_ids": fetchedProductIDs.joined(separator: ","),
                "recognized_product_ids": recognizedProductIDs.joined(separator: ","),
                "hypothesis_id": fetchedProducts.isEmpty ? "A" : "C"
            ])
            // #endregion

            if loadedProducts.isEmpty {
                // #region agent log
                AppLog.info(.app, "tips_products_load_empty", data: [
                    "requested_count": String(requestedProductIDs.count),
                    "received_count": String(fetchedProducts.count),
                    "hypothesis_id": "A"
                ])
                // #endregion
                if products.isEmpty {
                    lastError = .productsUnavailable
                }
                return
            }

            products = loadedProducts
            lastError = nil
            await refreshSubscriptionState()
        } catch {
            // #region agent log
            AppLog.info(.app, "tips_products_load_failed", data: [
                "error_type": String(describing: type(of: error)),
                "error": String(describing: error),
                "requested_count": String(requestedProductIDs.count),
                "hypothesis_id": "B"
            ])
            // #endregion
            if products.isEmpty {
                lastError = .productsUnavailable
            }
        }
    }

    func purchase(_ productID: TipProductID) async {
        guard purchaseState == .idle, let product = products[productID] else { return }

        purchaseState = .purchasing(productID)
        lastError = nil
        lastMessage = nil
        defer { purchaseState = .idle }

        do {
            switch try await product.purchase() {
            case .success(let verificationResult):
                let transaction = try verifiedTransaction(from: verificationResult)
                await transaction.finish()
                await refreshSubscriptionState()
            case .userCancelled:
                break
            case .pending:
                lastMessage = .purchasePending
            @unknown default:
                throw TipPurchaseError.purchaseFailed
            }
        } catch let error as TipPurchaseError {
            lastError = error
            logPurchaseFailure(productID: productID, error: error)
        } catch {
            lastError = .purchaseFailed
            logPurchaseFailure(productID: productID, error: error)
        }
    }

    /// Restores the renewable subscription. Consumable tips are intentionally
    /// not restored, matching StoreKit's consumable product semantics.
    func restorePurchases() async {
        guard purchaseState == .idle else { return }

        purchaseState = .restoring
        lastError = nil
        lastMessage = nil
        defer { purchaseState = .idle }

        do {
            try await AppStore.sync()
            await refreshSubscriptionState()
        } catch {
            AppLog.info(.app, "tips_restore_failed", data: [
                "reason": String(describing: type(of: error))
            ])
            lastError = .restoreFailed
        }
    }

    func refreshSubscriptionState() async {
        var isActive = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == TipProductID.monthly.rawValue,
                  transaction.revocationDate == nil else {
                continue
            }

            if let expirationDate = transaction.expirationDate,
               expirationDate <= Date() {
                continue
            }

            isActive = true
            break
        }

        isMonthlySubscriptionActive = isActive
    }

    private func handleTransactionUpdate(
        _ result: VerificationResult<Transaction>
    ) async {
        guard case .verified(let transaction) = result else { return }
        await transaction.finish()
        await refreshSubscriptionState()
    }

    private func verifiedTransaction(
        from result: VerificationResult<Transaction>
    ) throws -> Transaction {
        guard case .verified(let transaction) = result else {
            throw TipPurchaseError.purchaseVerificationFailed
        }
        return transaction
    }

    private func logPurchaseFailure(productID: TipProductID, error: Error) {
        AppLog.info(.app, "tips_purchase_failed", data: [
            "product_id": productID.rawValue,
            "reason": String(describing: type(of: error))
        ])
    }
}

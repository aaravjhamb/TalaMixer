//
//  LicenseStore.swift
//  TalaMixer
//
//  Full-mode licensing through StoreKit 2. Simplified mode is free; the full
//  surface is an auto-renewable subscription. Entitlement is whatever Apple
//  says it is — `Transaction.currentEntitlements` — so purchases, renewals,
//  refunds, offer codes and family sharing all just work, on every device
//  signed into the same Apple ID, with no server of our own.
//

import Foundation
import StoreKit

@Observable @MainActor
final class LicenseStore {

    /// Both plans unlock the same thing; they differ only in period.
    static let productIDs = ["talamixer.full.monthly", "talamixer.full.yearly"]

    private(set) var products: [Product] = []
    private(set) var isFull = false
    /// Set while a purchase or restore is in flight, to disable the buttons.
    private(set) var isWorking = false
    private(set) var lastError: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        // Refunds and renewals arrive here even while the app is running.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if let transaction = try? update.payloadValue {
                    await transaction.finish()
                }
                await self?.refreshEntitlement()
            }
        }

        Task {
            await loadProducts()
            await refreshEntitlement()
        }
    }

    func loadProducts() async {
        do {
            products = try await Product.products(for: Self.productIDs)
                .sorted { $0.price < $1.price }
            if products.isEmpty {
                // Reachable but empty: the store has no such products. Locally
                // that means the run started without the StoreKit configuration.
                lastError = "The App Store returned no plans. Running from Xcode? Check Edit Scheme › Run › Options › StoreKit Configuration is set to TalaMixer.storekit."
            } else {
                lastError = nil
            }
        } catch {
            lastError = "Couldn't load plans: \(error.localizedDescription)"
        }
    }

    func refreshEntitlement() async {
        #if DEBUG
        // Developer comp: `defaults write aarav.j.TalaMixer fullOverride -bool true`
        // or the "-fullOverride 1" launch argument. Debug builds only — release
        // builds answer to StoreKit alone.
        if UserDefaults.standard.bool(forKey: "fullOverride") {
            isFull = true
            return
        }
        #endif

        var full = false
        for await entitlement in Transaction.currentEntitlements {
            if let transaction = try? entitlement.payloadValue,
               Self.productIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                full = true
            }
        }
        isFull = full
    }

    func purchase(_ product: Product) async {
        isWorking = true
        lastError = nil
        defer { isWorking = false }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                let transaction = try verification.payloadValue
                await transaction.finish()
                await refreshEntitlement()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restore() async {
        isWorking = true
        lastError = nil
        defer { isWorking = false }

        try? await AppStore.sync()
        await refreshEntitlement()
    }
}

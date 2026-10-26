import Foundation
import MelodyPopKit
import Observation
import StoreKit

/// StoreKit 2: one non-consumable, "Say Piano Plus", that unlocks lessons 11–30 and the premium songs.
/// Purchases are only offered behind the parental gate in the Parent Dashboard.
@Observable
@MainActor
final class StoreManager {
    enum State: Equatable {
        case loading
        case ready
        case unavailable(String)
    }

    private(set) var product: Product?
    private(set) var hasPlus = false
    private(set) var state: State = .loading
    private(set) var purchaseMessage: String?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init() {
        if ProcessInfo.processInfo.arguments.contains("-uitest-plus") { hasPlus = true }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                    await self?.refreshEntitlements()
                }
            }
        }
    }

    deinit { updatesTask?.cancel() }

    func load() async {
        await refreshEntitlements()
        do {
            let products = try await Product.products(for: [Entitlements.plusProductID])
            product = products.first
            state = product == nil ? .unavailable("Say Piano Plus isn't available in this region or build yet.") : .ready
        } catch {
            state = .unavailable(error.localizedDescription)
        }
    }

    func refreshEntitlements() async {
        var owned = ProcessInfo.processInfo.arguments.contains("-uitest-plus")
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Entitlements.plusProductID, t.revocationDate == nil {
                owned = true
            }
        }
        hasPlus = owned
    }

    func purchase() async {
        guard let product else { return }
        purchaseMessage = nil
        do {
            switch try await product.purchase() {
            case .success(let verification):
                switch verification {
                case .verified(let t):
                    await t.finish()
                    await refreshEntitlements()
                    purchaseMessage = "Thank you! Everything is unlocked."
                case .unverified:
                    purchaseMessage = "The purchase couldn't be verified."
                }
            case .pending:
                purchaseMessage = "The purchase is waiting for approval."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseMessage = error.localizedDescription
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            purchaseMessage = hasPlus ? "Purchases restored." : "No previous purchase was found."
        } catch {
            purchaseMessage = error.localizedDescription
        }
    }
}

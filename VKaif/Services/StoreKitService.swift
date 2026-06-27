import StoreKit
import Combine

/// ID продукта — нужно создать в App Store Connect с таким же ID.
let premiumProductID = "com.vsharavin.vkaif.premium"

@MainActor
final class StoreKitService: ObservableObject {
    static let shared = StoreKitService()

    @Published var isPremium = false
    @Published var product: Product? = nil
    @Published var purchaseState: PurchaseState = .idle

    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case success
        case failed(String)
        case restored
    }

    private var updates: Task<Void, Never>? = nil

    private init() {
        updates = listenForTransactions()
        Task { await loadProducts() }
        Task { await refreshPurchaseStatus() }
    }

    deinit { updates?.cancel() }

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [premiumProductID])
            product = products.first
        } catch {
            print("StoreKit: loadProducts failed: \(error)")
        }
    }

    func purchase() async {
        guard let product else {
            purchaseState = .failed("Продукт недоступен")
            return
        }
        purchaseState = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                isPremium = true
                purchaseState = .success
            case .userCancelled:
                purchaseState = .idle
            case .pending:
                purchaseState = .idle
            @unknown default:
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    func restore() async {
        purchaseState = .purchasing
        do {
            try await AppStore.sync()
            await refreshPurchaseStatus()
            if isPremium {
                purchaseState = .restored
            } else {
                purchaseState = .failed("Активных покупок не найдено")
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    func refreshPurchaseStatus() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == premiumProductID,
               transaction.revocationDate == nil {
                isPremium = true
                return
            }
        }
        isPremium = false
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task(priority: .background) {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await MainActor.run { self.isPremium = true }
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw StoreKitError.unverified
        case .verified(let value): return value
        }
    }
}

enum StoreKitError: Error { case unverified }
